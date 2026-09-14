param([string]$Seed = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'BrasslineLauncher'
$bundled = Join-Path $PSScriptRoot 'Launcher.ps1'
$ui = $bundled
# The tiny bootstrap stays put; the UI and updater are versioned with the game.
# If an installed script is damaged, the bundled updater can still repair it.
try {
    $pointer = Join-Path $root 'active.json'
    if (Test-Path -LiteralPath $pointer) {
        $state = Get-Content -LiteralPath $pointer -Raw | ConvertFrom-Json
        if ($state.current -notmatch '^[a-f0-9]{40}-[a-f0-9]{32}$') { throw 'Invalid install pointer.' }
        $dir = Join-Path (Join-Path $root 'versions') $state.current
        $manifest = Get-Content -LiteralPath (Join-Path $dir '.brassline-manifest.json') -Raw | ConvertFrom-Json
        foreach ($name in @('Launcher.ps1', 'Core.ps1')) {
            $entries = @($manifest.files | Where-Object { $_.path -ceq "launcher/$name" })
            if ($entries.Count -ne 1 -or $entries[0].sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Missing launcher checksum.' }
            $path = Join-Path (Join-Path $dir 'launcher') $name
            if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entries[0].sha256) { throw 'Launcher requires repair.' }
        }
        $ui = Join-Path (Join-Path $dir 'launcher') 'Launcher.ps1'
    }
} catch { $ui = $bundled }
try { & $ui -Root $root -Seed $Seed }
catch {
    Add-Type -AssemblyName System.Windows.Forms
    [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'BRASSLINE launcher') | Out-Null
}
