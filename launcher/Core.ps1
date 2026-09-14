# BRASSLINE launcher core. Windows PowerShell 5.1; no administrator privileges.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:ChannelUrl = 'https://github.com/blakelassman/brassline/releases/download/launcher/channel.json'

function Write-Status([string]$Message, [int]$Percent = -1) {
    Write-Output ([pscustomobject]@{ Kind = 'progress'; Message = $Message; Percent = $Percent })
}
function Test-Hash([string]$Path, [string]$Expected) {
    return (Test-Path -LiteralPath $Path -PathType Leaf) -and
        ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $Expected)
}
function Write-AtomicJson([string]$Path, $Value) {
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temp, $Path, ($Path + '.bak')) }
        else { [IO.File]::Move($temp, $Path) }
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}
function Read-Json([string]$Path) { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
function Assert-RelativePath([string]$Path) {
    if (!$Path -or $Path.Length -gt 180 -or $Path -match '[^a-zA-Z0-9_.\-/]' -or $Path.StartsWith('/')) {
        throw "Unsafe update path: $Path"
    }
    foreach ($part in $Path.Split('/')) {
        if (!$part -or $part -in @('.', '..') -or $part.EndsWith('.') -or
            $part -match '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])($|\.)') { throw "Unsafe update path: $Path" }
    }
}
function Assert-Manifest($Manifest) {
    if ($Manifest.schema -ne 1 -or $Manifest.commit -notmatch '^[a-f0-9]{40}$' -or
        $Manifest.version -notmatch '^[a-zA-Z0-9.+_-]{1,64}$') { throw 'Unsupported update manifest.' }
    $seen = @{}
    $total = [long]0
    if (@($Manifest.files).Count -gt 5000) { throw 'Update contains too many files.' }
    foreach ($file in $Manifest.files) {
        Assert-RelativePath $file.path
        if ($file.path -notmatch '^(scripts/|assets/|launcher/(Core|Launcher)\.ps1$|project\.godot$|main\.tscn$|server\.cfg$|GODOT_LICENSES\.txt$|HOSTING\.txt$)' -or
            $file.path -match '\.(py|exe|dll|bat|cmd|import)$' -or $seen.ContainsKey($file.path)) { throw 'Invalid or duplicate game file.' }
        $seen[$file.path] = $true
        if ($file.sha256 -notmatch '^[a-f0-9]{64}$' -or $file.size -lt 0 -or $file.size -gt 268435456) { throw 'Invalid file checksum or size.' }
        $expectedUrl = "https://raw.githubusercontent.com/blakelassman/brassline/$($Manifest.commit)/$($file.path)"
        if ($file.url -cne $expectedUrl) { throw 'Update file is not pinned to the release commit.' }
        $total += $file.size
    }
    foreach ($required in @('project.godot', 'main.tscn', 'scripts/main.gd', 'launcher/Core.ps1', 'launcher/Launcher.ps1')) {
        if (!$seen.ContainsKey($required)) { throw "Update is missing $required" }
    }
    if ($total -gt 2147483648) { throw 'Update is too large.' }
    if ($Manifest.engine.archive_url -notmatch '^https://github\.com/godotengine/godot-builds/releases/download/[0-9.]+-stable/Godot_v[0-9.]+-stable_win64\.exe\.zip$' -or
        $Manifest.engine.archive_sha256 -notmatch '^[a-f0-9]{64}$' -or @($Manifest.engine.files).Count -ne 2) { throw 'Invalid engine release.' }
    $engineNames = @{}
    foreach ($file in $Manifest.engine.files) {
        if ($file.path -notmatch '^Godot_v[0-9.]+-stable_win64(_console)?\.exe$' -or
            $file.sha256 -notmatch '^[a-f0-9]{64}$' -or $engineNames.ContainsKey($file.path)) { throw 'Invalid engine file.' }
        $engineNames[$file.path] = $true
    }
    $base = [IO.Path]::GetFileNameWithoutExtension($Manifest.engine.archive_url)
    if (!$engineNames.ContainsKey($base) -or !$engineNames.ContainsKey($base.Replace('.exe', '_console.exe'))) { throw 'Engine file names do not match the archive.' }
}
function Receive-File([string]$Url, [string]$Destination) {
    # This function is replaced by a deterministic local transport in the tests.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $client = New-Object Net.WebClient
    $client.Headers['User-Agent'] = 'Brassline-Launcher/1.0'
    try { $client.DownloadFile($Url, $Destination) } finally { $client.Dispose() }
}
function Get-Channel([string]$Root) {
    [IO.Directory]::CreateDirectory($Root) | Out-Null
    $temp = Join-Path $Root "channel.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        Receive-File $script:ChannelUrl $temp
        if ((Get-Item -LiteralPath $temp).Length -gt 2097152) { throw 'Invalid update manifest size.' }
        $manifest = Read-Json $temp
        Assert-Manifest $manifest
        return $manifest
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}
function Get-Install([string]$Root, [switch]$Previous) {
    $pointer = Join-Path $Root 'active.json'
    if (!(Test-Path -LiteralPath $pointer)) { return $null }
    $state = Read-Json $pointer
    $id = $state.current
    if ($Previous) { $id = $state.previous }
    if (!$id) { return $null }
    if ($id -notmatch '^[a-f0-9]{40}-[a-f0-9]{32}$') { throw 'Invalid installed version pointer. Use Repair.' }
    $path = Join-Path (Join-Path $Root 'versions') $id
    $manifest = Read-Json (Join-Path $path '.brassline-manifest.json')
    Assert-Manifest $manifest
    return [pscustomobject]@{ Id = $id; Path = $path; Manifest = $manifest }
}
function Get-EnginePath([string]$Root, $Manifest) {
    $name = @($Manifest.engine.files | Where-Object { $_.path -notmatch '_console' })[0].path
    return Join-Path (Join-Path $Root 'engine') $name
}
function Test-Installed($Install, [string]$Root) {
    if (!$Install) { return $false }
    foreach ($file in $Install.Manifest.files) {
        # The dedicated server configuration is user owned after first install.
        if ($file.path -eq 'server.cfg') { continue }
        if (!(Test-Hash (Join-Path $Install.Path $file.path) $file.sha256)) { return $false }
    }
    foreach ($file in $Install.Manifest.engine.files) {
        if (!(Test-Hash (Join-Path (Join-Path $Root 'engine') $file.path) $file.sha256)) { return $false }
    }
    return Test-Path -LiteralPath (Join-Path $Install.Path '.godot') -PathType Container
}
function Assert-GameStopped([string]$Root) {
    # Stable engine location also keeps Windows Firewall rules valid between updates.
    if ($env:OS -ne 'Windows_NT') { return }
    $engineRoot = [IO.Path]::GetFullPath((Join-Path $Root 'engine')) + [IO.Path]::DirectorySeparatorChar
    foreach ($proc in @(Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue)) {
        try { $path = $proc.Path } catch { continue }
        if ($path -and $path.StartsWith($engineRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Close BRASSLINE and its dedicated server before updating or rolling back.'
        }
    }
}
function Get-UpdateLock([string]$Root) {
    [IO.Directory]::CreateDirectory($Root) | Out-Null
    try { return [IO.File]::Open((Join-Path $Root 'update.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { throw 'Another BRASSLINE update is running. Close it and try again.' }
}
function Install-Engine([string]$Root, $Manifest, [string]$Seed) {
    $engineDir = Join-Path $Root 'engine'
    [IO.Directory]::CreateDirectory($engineDir) | Out-Null
    $missing = @($Manifest.engine.files | Where-Object { !(Test-Hash (Join-Path $engineDir $_.path) $_.sha256) })
    if ($missing.Count -eq 0) { return }
    foreach ($file in $missing) {
        $source = Join-Path (Join-Path $Seed 'engine') $file.path
        if (Test-Hash $source $file.sha256) { Copy-Item -LiteralPath $source -Destination (Join-Path $engineDir $file.path) -Force }
    }
    $missing = @($Manifest.engine.files | Where-Object { !(Test-Hash (Join-Path $engineDir $_.path) $_.sha256) })
    if ($missing.Count -eq 0) { return }
    Write-Status 'Downloading the engine (needed once)...' 5
    $archive = Join-Path $Root 'engine-download.zip'
    $unpack = Join-Path $Root "engine-stage-$([guid]::NewGuid().ToString('N'))"
    try {
        if (!(Test-Hash $archive $Manifest.engine.archive_sha256)) {
            Receive-File $Manifest.engine.archive_url $archive
            if (!(Test-Hash $archive $Manifest.engine.archive_sha256)) { throw 'Engine download failed its checksum. Retry the update.' }
        }
        [IO.Directory]::CreateDirectory($unpack) | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($archive)
        try {
            foreach ($file in $Manifest.engine.files) {
                $entry = $zip.GetEntry($file.path)
                if (!$entry) { throw "Engine archive is missing $($file.path)" }
                $dest = Join-Path $unpack $file.path
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest)
                if (!(Test-Hash $dest $file.sha256)) { throw 'Engine executable failed its checksum.' }
            }
        } finally { $zip.Dispose() }
        foreach ($file in $Manifest.engine.files) {
            Copy-Item -LiteralPath (Join-Path $unpack $file.path) -Destination (Join-Path $engineDir $file.path) -Force
        }
    } finally {
        if (Test-Path -LiteralPath $unpack) { Remove-Item -LiteralPath $unpack -Recurse -Force }
        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    }
}
function Invoke-GameImport([string]$Engine, [string]$Directory) {
    $log = Join-Path $Directory 'import.log'
    $process = Start-Process -FilePath $Engine -ArgumentList @('--headless', '--editor', '--import', '--path', ('"' + $Directory + '"'), '--log-file', ('"' + $log + '"'), '--quit') -PassThru -WindowStyle Hidden
    try {
        if (!$process.WaitForExit(180000)) { throw 'Preparing the game timed out. Retry the update.' }
    } finally {
        # Closing the launcher during import must not leave an invisible engine running.
        if (!$process.HasExited) { $process.Kill(); $process.WaitForExit() }
    }
    if ($process.ExitCode -ne 0 -or !(Test-Path -LiteralPath $log) -or
        (Get-Content -LiteralPath $log -Raw) -match '(SCRIPT ERROR|Parse Error|Failed to load script|ERROR:)') {
        throw "The new build failed its first-run check. Your previous version is still available. Details: $log"
    }
}
function Install-Update([string]$Root, $Manifest, [string]$Seed, [switch]$Repair) {
    Assert-Manifest $Manifest
    $lock = Get-UpdateLock $Root
    $stage = $null
    try {
        Assert-GameStopped $Root
        $old = $null
        try { $old = Get-Install $Root } catch { Write-Status 'Repairing the installed version information...' }
        if (!$Repair -and $old -and $old.Manifest.commit -eq $Manifest.commit -and (Test-Installed $old $Root)) {
            Write-Status 'Already up to date.' 100
            return
        }
        $rollbackInstall = $null
        if ($old -and (Test-Installed $old $Root)) { $rollbackInstall = $old }
        elseif ($old) {
            try {
                $fallback = Get-Install $Root -Previous
                if ($fallback -and (Test-Installed $fallback $Root)) { $rollbackInstall = $fallback }
            } catch { } # Repair can proceed even if the old rollback metadata is damaged.
        }
        Install-Engine $Root $Manifest $Seed
        $versions = Join-Path $Root 'versions'
        $cache = Join-Path $Root 'cache'
        [IO.Directory]::CreateDirectory($versions) | Out-Null
        [IO.Directory]::CreateDirectory($cache) | Out-Null
        $id = "$($Manifest.commit)-$([guid]::NewGuid().ToString('N'))"
        $stage = Join-Path $versions $id
        [IO.Directory]::CreateDirectory($stage) | Out-Null
        $count = 0; $downloaded = 0
        foreach ($file in $Manifest.files) {
            $cached = Join-Path $cache $file.sha256
            if (!(Test-Hash $cached $file.sha256)) {
                $sources = @((Join-Path $Seed $file.path))
                if ($old) { $sources += Join-Path $old.Path $file.path }
                $reused = $false
                foreach ($source in $sources) {
                    if (Test-Hash $source $file.sha256) {
                        Copy-Item -LiteralPath $source -Destination $cached -Force
                        $reused = $true; break
                    }
                }
                if (!$reused) {
                    Write-Status "Downloading $($file.path)..." (10 + [int](70 * $count / $Manifest.files.Count))
                    $partial = "$cached.partial"
                    try {
                        Receive-File $file.url $partial
                        if ((Get-Item -LiteralPath $partial).Length -ne $file.size -or !(Test-Hash $partial $file.sha256)) {
                            throw "Checksum mismatch for $($file.path). Retry the update."
                        }
                        Move-Item -LiteralPath $partial -Destination $cached -Force
                        $downloaded++
                    } finally { if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force } }
                }
            }
            $dest = Join-Path $stage $file.path
            [IO.Directory]::CreateDirectory((Split-Path -Parent $dest)) | Out-Null
            Copy-Item -LiteralPath $cached -Destination $dest
            $count++
        }
        # Keep hosting configuration out of the versioned install, like the game's profile.
        $config = Join-Path $Root 'server.cfg'
        if (!(Test-Path -LiteralPath $config)) {
            $source = Join-Path $Seed 'server.cfg'
            if ($old) { $source = Join-Path $old.Path 'server.cfg' }
            if (!(Test-Path -LiteralPath $source)) { $source = Join-Path $stage 'server.cfg' }
            if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $config }
        }
        if (Test-Path -LiteralPath $config) { Copy-Item -LiteralPath $config -Destination (Join-Path $stage 'server.cfg') -Force }
        Write-Status 'Preparing sounds and shaders for this version...' 85
        try { Invoke-GameImport (Get-EnginePath $Root $Manifest) $stage }
        catch {
            $importLog = Join-Path $stage 'import.log'
            if (Test-Path -LiteralPath $importLog) {
                Copy-Item -LiteralPath $importLog -Destination (Join-Path $Root 'last-import.log') -Force
            }
            throw 'Game preparation failed. The installed version was kept. See last-import.log in Game folder.'
        }
        Write-AtomicJson (Join-Path $stage '.brassline-manifest.json') $Manifest
        $previous = ''
        if ($rollbackInstall) { $previous = $rollbackInstall.Id }
        Write-AtomicJson (Join-Path $Root 'active.json') @{ current = $id; previous = $previous }
        $stage = $null
        # Remove only obsolete managed versions/cache objects after successful activation.
        foreach ($directory in @(Get-ChildItem -LiteralPath $versions -Directory)) {
            if ($directory.Name -match '^[a-f0-9]{40}-[a-f0-9]{32}$' -and $directory.Name -notin @($id, $previous)) {
                Remove-Item -LiteralPath $directory.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        $keep = @{}
        foreach ($file in $Manifest.files) { $keep[$file.sha256] = $true }
        if ($rollbackInstall) { foreach ($file in $rollbackInstall.Manifest.files) { $keep[$file.sha256] = $true } }
        foreach ($entry in @(Get-ChildItem -LiteralPath $cache -File)) {
            if ($entry.Name -match '^[a-f0-9]{64}$' -and !$keep.ContainsKey($entry.Name)) {
                Remove-Item -LiteralPath $entry.FullName -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Status "Ready. Downloaded $downloaded changed files." 100
    } finally {
        if ($stage -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
        $lock.Dispose()
    }
}
function Restore-Previous([string]$Root) {
    $lock = Get-UpdateLock $Root
    try {
        Assert-GameStopped $Root
        $old = Get-Install $Root -Previous
        $current = Get-Install $Root
        if (!$old -or !(Test-Installed $old $Root)) { throw 'No intact previous version is available.' }
        Write-AtomicJson (Join-Path $Root 'active.json') @{ current = $old.Id; previous = $current.Id }
        Write-Status "Restored $($old.Manifest.version). Use Play installed to keep this version." 100
    } finally { $lock.Dispose() }
}
