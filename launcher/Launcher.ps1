param([string]$Root = (Join-Path $env:LOCALAPPDATA 'BrasslineLauncher'), [string]$Seed = (Split-Path -Parent $PSScriptRoot), [switch]$SmokeTest)
. (Join-Path $PSScriptRoot 'Core.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
if (![Environment]::Is64BitOperatingSystem) { throw 'BRASSLINE needs 64-bit Windows 10 or 11.' }
[IO.Directory]::CreateDirectory($Root) | Out-Null
try { $instanceLock = [IO.File]::Open((Join-Path $Root 'launcher.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
catch { throw 'BRASSLINE launcher is already open.' }
$script:job = $null
$script:playAfter = $false
$script:latest = $null
$script:jobFailed = $false
$script:corePath = Join-Path $PSScriptRoot 'Core.ps1'
$form = New-Object Windows.Forms.Form
$form.Text = 'BRASSLINE Launcher'
$form.ClientSize = New-Object Drawing.Size(760, 490)
$form.MinimumSize = $form.Size
$form.MaximumSize = $form.Size
$form.StartPosition = 'CenterScreen'
$form.BackColor = [Drawing.Color]::FromArgb(15, 21, 29)
$form.ForeColor = [Drawing.Color]::FromArgb(231, 238, 244)
$form.Font = New-Object Drawing.Font('Segoe UI', 10)
$form.AutoScaleMode = 'Dpi'
function Label-At([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height, [int]$Size = 10) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $Text; $label.Location = New-Object Drawing.Point($X, $Y)
    $label.Size = New-Object Drawing.Size($Width, $Height)
    $label.Font = New-Object Drawing.Font('Segoe UI', $Size)
    $form.Controls.Add($label)
    return $label
}
function Button-At([string]$Text, [int]$X, [int]$Y, [int]$Width) {
    $button = New-Object Windows.Forms.Button
    $button.Text = $Text; $button.Location = New-Object Drawing.Point($X, $Y)
    $button.Size = New-Object Drawing.Size($Width, 42)
    $button.FlatStyle = 'Flat'; $button.FlatAppearance.BorderSize = 0
    $button.BackColor = [Drawing.Color]::FromArgb(35, 47, 61)
    $form.Controls.Add($button)
    return $button
}
$title = Label-At 'BRASSLINE' 30 25 600 60 34
$title.Font = New-Object Drawing.Font('Segoe UI', 34, ([Drawing.FontStyle]::Bold))
$title.ForeColor = [Drawing.Color]::FromArgb(242, 194, 91)
$null = Label-At 'GET IN. GET MOVING.' 34 88 600 30 12
$installed = Label-At 'No game installed yet' 34 144 690 25
$available = Label-At 'Checking for updates...' 34 172 690 25
$status = Label-At 'Welcome to BRASSLINE.' 34 213 690 48
$progress = New-Object Windows.Forms.ProgressBar
$progress.Location = New-Object Drawing.Point(34, 268)
$progress.Size = New-Object Drawing.Size(690, 8)
$form.Controls.Add($progress)
$primary = Button-At 'INSTALL & PLAY' 34 298 250
$primary.BackColor = [Drawing.Color]::FromArgb(242, 194, 91)
$primary.ForeColor = [Drawing.Color]::FromArgb(15, 21, 29)
$primary.Font = New-Object Drawing.Font('Segoe UI', 11, ([Drawing.FontStyle]::Bold))
$offline = Button-At 'Play installed' 296 298 160
$check = Button-At 'Check updates' 468 298 125
$repair = Button-At 'Repair' 605 298 119
$rollback = Button-At 'Previous version' 34 355 160
$server = Button-At 'Dedicated server' 206 355 160
$folder = Button-At 'Game folder' 378 355 160
$shortcut = Button-At 'Desktop shortcut' 550 355 174
$null = Label-At 'Free updates. Your progress stays saved on this Windows account.' 34 421 690 24 9
$null = Label-At 'Online players and the host should all use the same version.' 34 447 690 24 9
function Refresh-Install {
    $local = $null
    try { $local = Get-Install $Root } catch { $status.Text = 'Installed files need repair. Click Repair.' }
    if ($local) {
        $installed.Text = "Installed: $($local.Manifest.version)"
        $primary.Text = 'UPDATE & PLAY'
        if ($script:latest -and $script:latest.commit -eq $local.Manifest.commit) { $primary.Text = 'PLAY' }
    } else { $installed.Text = 'No game installed yet'; $primary.Text = 'INSTALL & PLAY' }
    $offline.Enabled = ($null -ne $local) -and !$script:job
    $server.Enabled = $offline.Enabled
    $folder.Enabled = $null -ne $local
    $rollback.Enabled = !$script:job -and (Test-Path -LiteralPath (Join-Path $Root 'active.json'))
}
function Set-Busy([bool]$Busy) {
    foreach ($button in @($primary, $check, $repair, $offline, $rollback, $server)) { $button.Enabled = !$Busy }
    if ($Busy) { $progress.Style = 'Marquee' } else { $progress.Style = 'Continuous'; Refresh-Install }
}
function Start-Task([string]$Action, [bool]$Play = $false) {
    if ($script:job) { return }
    $script:playAfter = $Play
    $script:jobFailed = $false
    $status.Text = 'Connecting to the update service...'
    Set-Busy $true
    $script:job = Start-Job -ArgumentList @($script:corePath, $Root, $Seed, $Action) -ScriptBlock {
        param($Core, $InstallRoot, $SeedRoot, $Task)
        . $Core
        try {
            if ($Task -eq 'rollback') { Restore-Previous $InstallRoot; return }
            $manifest = Get-Channel $InstallRoot
            Write-Output ([pscustomobject]@{ Kind = 'channel'; Manifest = $manifest })
            if ($Task -ne 'check') { Install-Update $InstallRoot $manifest $SeedRoot }
        } catch { Write-Output ([pscustomobject]@{ Kind = 'failure'; Message = $_.Exception.Message }) }
    }
}
function Launch-Game([bool]$Dedicated = $false) {
    $lock = $null
    try {
        $lock = Get-UpdateLock $Root
        Assert-GameStopped $Root
        $local = Get-Install $Root
        $status.Text = 'Verifying installed files...'
        $form.Refresh()
        if (!(Test-Installed $local $Root)) { throw 'Some installed files are missing or damaged. Click Repair.' }
        $exe = Get-EnginePath $Root $local.Manifest
        $args = @('--path', ('"' + $local.Path + '"'), '--log-file', ('"' + (Join-Path $Root 'brassline.log') + '"'))
        if ($Dedicated) {
            Copy-Item -LiteralPath (Join-Path $Root 'server.cfg') -Destination (Join-Path $local.Path 'server.cfg') -Force
            $args += @('--headless', '--', '--server')
        }
        Start-Process -FilePath $exe -ArgumentList $args -WorkingDirectory $local.Path | Out-Null
        $status.Text = 'Game started. Close it before installing another update.'
    } catch { $status.Text = $_.Exception.Message }
    finally { if ($lock) { $lock.Dispose() } }
}
$primary.Add_Click({ Start-Task 'update' $true })
$offline.Add_Click({ Launch-Game })
$server.Add_Click({ Launch-Game $true })
$check.Add_Click({ Start-Task 'check' })
$repair.Add_Click({ Start-Task 'update' })
$rollback.Add_Click({ Start-Task 'rollback' })
$folder.Add_Click({ Start-Process explorer.exe -ArgumentList ('"' + $Root + '"') })
$shortcut.Add_Click({
    try {
        # Keep the bootstrap and fallback scripts in a stable local directory.
        $bootstrapDir = Join-Path $Root 'bootstrap'
        [IO.Directory]::CreateDirectory($bootstrapDir) | Out-Null
        foreach ($name in @('Bootstrap.ps1', 'Launcher.ps1', 'Core.ps1')) {
            $source = Join-Path (Join-Path $Seed 'launcher') $name
            $dest = Join-Path $bootstrapDir $name
            if ([IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($dest)) { Copy-Item -LiteralPath $source -Destination $dest -Force }
        }
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'BRASSLINE.lnk'))
        $link.TargetPath = Join-Path $PSHOME 'powershell.exe'
        $link.Arguments = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $bootstrapDir 'Bootstrap.ps1') + '" -Seed "' + $Seed + '"'
        $link.WorkingDirectory = $Root
        $link.Description = 'Update and play BRASSLINE'
        $link.Save()
        $status.Text = 'BRASSLINE shortcut added to your desktop.'
    } catch { $status.Text = $_.Exception.Message }
})
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 200
$timer.Add_Tick({
    if (!$script:job) { return }
    foreach ($event in @(Receive-Job $script:job -ErrorAction SilentlyContinue)) {
        switch ($event.Kind) {
            'channel' {
                $script:latest = $event.Manifest
                $available.Text = "Available: $($event.Manifest.version)"
                $status.Text = 'Ready. Click Update & Play, or play the installed version offline.'
            }
            'progress' {
                $status.Text = $event.Message
                if ($event.Percent -ge 0) { $progress.Style = 'Continuous'; $progress.Value = [Math]::Min(100, $event.Percent) }
            }
            'failure' {
                $script:jobFailed = $true
                $status.Text = $event.Message + ' You can retry or use Play installed.'
                if (!$script:latest) { $available.Text = 'Update service unavailable. Installed games still work offline.' }
                Add-Content -LiteralPath (Join-Path $Root 'launcher.log') -Value "$(Get-Date -Format o) $($event.Message)"
            }
        }
    }
    if ($script:job.State -in @('Completed', 'Failed', 'Stopped')) {
        $success = !$script:jobFailed -and $script:job.State -eq 'Completed'
        if ($script:job.State -eq 'Failed') { $status.Text = 'Update worker stopped. Retry, or use Play installed.' }
        Remove-Job $script:job -Force
        $script:job = $null
        Set-Busy $false
        if ($script:playAfter -and $success) { Launch-Game }
    }
})
$form.Add_Shown({
    Refresh-Install
    if ($SmokeTest) {
        $installed.Text = 'Installed: 0.9.0'; $available.Text = 'Available: 0.9.0'
        $status.Text = 'Ready. Your next match is one click away.'
        $primary.Text = 'PLAY'
        $bitmap = New-Object Drawing.Bitmap($form.Width, $form.Height)
        try { $form.DrawToBitmap($bitmap, $form.ClientRectangle); $bitmap.Save((Join-Path $Root 'launcher-preview.png')) }
        finally { $bitmap.Dispose() }
        $form.Close()
    } else { Start-Task 'check' }
})
$form.Add_FormClosing({
    if ($script:job) { Stop-Job $script:job; Remove-Job $script:job -Force; $script:job = $null }
})
try { $timer.Start(); [Windows.Forms.Application]::Run($form) }
finally { $timer.Dispose(); $form.Dispose(); $instanceLock.Dispose() }
