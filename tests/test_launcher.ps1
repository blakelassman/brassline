# Deterministic integration tests. Real temp installs; transport/import are injected.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'launcher/Core.ps1')
$script:passed = 0
function Assert($Condition, [string]$Message) {
    if (!$Condition) { throw "FAIL: $Message" }
    $script:passed++; Write-Host "PASS: $Message"
}
function Must-Fail([scriptblock]$Action, [string]$Message) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Assert $failed $Message
}
function Hash-Text([string]$Text) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}
function Clone($Value) { return $Value | ConvertTo-Json -Depth 12 | ConvertFrom-Json }
$script:content = @{}
$script:downloads = New-Object 'System.Collections.Generic.List[string]'
$script:failUrl = ''; $script:corruptUrl = ''; $script:importFails = $false
function Receive-File([string]$Url, [string]$Destination) {
    $script:downloads.Add($Url)
    if ($Url -eq $script:failUrl) { throw 'Simulated connection loss' }
    if (!$script:content.ContainsKey($Url)) { throw "Unexpected download: $Url" }
    $data = $script:content[$Url]
    if ($Url -eq $script:corruptUrl) { $data = 'corrupt' }
    [IO.File]::WriteAllText($Destination, $data, (New-Object Text.UTF8Encoding($false)))
}
function Invoke-GameImport([string]$Engine, [string]$Directory) {
    if ($script:importFails) { throw 'Simulated Godot parse failure' }
    [IO.Directory]::CreateDirectory((Join-Path $Directory '.godot')) | Out-Null
}
function Make-Manifest([char]$Revision, [hashtable]$Payload) {
    $commit = [string]$Revision * 40
    $files = @()
    foreach ($name in @($Payload.Keys | Sort-Object)) {
        $data = $Payload[$name]
        $url = "https://raw.githubusercontent.com/blakelassman/brassline/$commit/$name"
        $script:content[$url] = $data
        $files += [pscustomobject]@{ path = $name; size = [Text.Encoding]::UTF8.GetByteCount($data); sha256 = Hash-Text $data; url = $url }
    }
    return [pscustomobject]@{ schema = 1; commit = $commit; version = "0.9.0+$Revision"; files = $files; engine = [pscustomobject]@{
        archive_url = 'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip'
        archive_sha256 = ('1' * 64)
        files = @([pscustomobject]@{ path = 'Godot_v4.7.2-stable_win64.exe'; sha256 = Hash-Text 'engine' },
                  [pscustomobject]@{ path = 'Godot_v4.7.2-stable_win64_console.exe'; sha256 = Hash-Text 'console' })
    } }
}
$temp = Join-Path ([IO.Path]::GetTempPath()) "brassline launcher test $([guid]::NewGuid().ToString('N'))"
$root = Join-Path $temp 'install with spaces'
$seed = Join-Path $temp 'old game'
try {
    foreach ($file in @(Get-ChildItem (Join-Path $repo 'launcher') -Filter '*.ps1')) {
        $tokens = $null; $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        Assert ($errors.Count -eq 0) "PowerShell parses $($file.Name): $errors"
    }
    [IO.Directory]::CreateDirectory((Join-Path $seed 'engine')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $seed 'engine/Godot_v4.7.2-stable_win64.exe'), 'engine')
    [IO.File]::WriteAllText((Join-Path $seed 'engine/Godot_v4.7.2-stable_win64_console.exe'), 'console')
    $profile = Join-Path $temp 'profile_v1.json'
    [IO.File]::WriteAllText($profile, '{"level":37,"inventory":["gold"]}')
    $payload = @{
        'project.godot' = 'project'; 'main.tscn' = 'scene'; 'scripts/main.gd' = 'script v1';
        'assets/hit.wav' = 'audio'; 'assets/retired.wav' = 'old audio';
        'launcher/Core.ps1' = 'core'; 'launcher/Launcher.ps1' = 'ui'; 'server.cfg' = 'default'
    }
    $a = Make-Manifest 'a' $payload
    Assert-Manifest $a
    Assert $true 'Valid commit-pinned manifest accepted'
    Install-Update $root $a $seed | Out-Null
    $first = Get-Install $root
    Assert (Test-Installed $first $root) 'First install is verified and imported'
    Assert ($script:downloads.Count -eq $a.files.Count) 'First install reuses the existing engine'
    Assert ((Read-Json (Join-Path $root 'active.json')).previous -eq '') 'First install has no rollback target'
    $script:downloads.Clear()
    Install-Update $root $a $seed | Out-Null
    Assert ($script:downloads.Count -eq 0) 'Up-to-date install downloads nothing'
    Assert ((Get-Install $root).Id -eq $first.Id) 'Up-to-date install does not reimport or replace files'
    [IO.File]::WriteAllText((Join-Path $root 'server.cfg'), 'private port and password')
    $payload['scripts/main.gd'] = 'script v2'
    $payload.Remove('assets/retired.wav')
    $b = Make-Manifest 'b' $payload
    Install-Update $root $b $seed | Out-Null
    $second = Get-Install $root
    Assert ($script:downloads.Count -eq 1) 'Update downloads only the one changed file'
    Assert (!(Test-Path (Join-Path $second.Path 'assets/retired.wav'))) 'Deleted release files are absent from the new version'
    Assert (Test-Path (Join-Path $first.Path 'assets/retired.wav')) 'Previous version remains intact'
    Assert ((Get-Content (Join-Path $second.Path 'server.cfg') -Raw) -eq 'private port and password') 'Custom server settings survive updates'
    Assert ((Get-Install $root -Previous).Id -eq $first.Id) 'Previous version recorded for rollback'
    Restore-Previous $root | Out-Null
    Assert ((Get-Install $root).Id -eq $first.Id) 'Rollback atomically switches to previous version'
    Restore-Previous $root | Out-Null
    Assert ((Get-Install $root).Id -eq $second.Id) 'Rollback can be undone'
    $payload['scripts/main.gd'] = 'script v3'
    $payload['assets/new.wav'] = 'new sound'
    $c = Make-Manifest 'c' $payload
    $changedUrl = @($c.files | Where-Object { $_.path -eq 'scripts/main.gd' })[0].url
    $script:failUrl = $changedUrl
    Must-Fail { Install-Update $root $c $seed } 'Interrupted update is rejected'
    Assert ((Get-Install $root).Id -eq $second.Id) 'Interrupted download leaves current version active'
    Assert (Test-Installed (Get-Install $root) $root) 'Installed game remains playable after connection loss'
    Assert (@(Get-ChildItem (Join-Path $root 'versions') -Directory).Count -eq 2) 'Incomplete stage is cleaned up'
    $script:failUrl = ''; $script:corruptUrl = $changedUrl
    Must-Fail { Install-Update $root $c $seed } 'Corrupt download is rejected'
    Assert ((Get-Install $root).Id -eq $second.Id) 'Checksum failure does not activate a release'
    $script:corruptUrl = ''; $script:importFails = $true
    Must-Fail { Install-Update $root $c $seed } 'Godot import failure is rejected'
    Assert ((Get-Install $root).Id -eq $second.Id) 'Bad game build keeps previous working install'
    $script:importFails = $false; $script:downloads.Clear()
    Install-Update $root $c $seed | Out-Null
    Assert ($script:downloads.Count -eq 0) 'Retry reuses files verified before the failure'
    $third = Get-Install $root
    Assert ($third.Manifest.commit -eq $c.commit) 'Retry successfully activates the new version'
    Assert (!(Test-Path $first.Path)) 'Obsolete third-oldest version is cleaned up'
    Assert (Test-Path $second.Path) 'Cleanup retains rollback version'
    # Damage active content and its cache: Repair must fetch just this file again.
    [IO.File]::WriteAllText((Join-Path $third.Path 'scripts/main.gd'), 'damage')
    $blob = @($c.files | Where-Object { $_.path -eq 'scripts/main.gd' })[0]
    [IO.File]::WriteAllText((Join-Path (Join-Path $root 'cache') $blob.sha256), 'damage')
    Assert (!(Test-Installed $third $root)) 'Launch verification detects corrupt files'
    $script:downloads.Clear()
    Install-Update $root $c $seed | Out-Null
    Assert ($script:downloads.Count -eq 1) 'Repair redownloads only damaged content'
    Assert (Test-Installed (Get-Install $root) $root) 'Repaired install is playable'
    $lock = Get-UpdateLock $root
    try { Must-Fail { Install-Update $root $c $seed } 'Concurrent updates are blocked' }
    finally { $lock.Dispose() }
    foreach ($path in @('../outside.gd', 'scripts/../../escape.gd', '/absolute.gd', 'scripts/a:evil', 'scripts/CON.gd', 'scripts/a./x', 'scripts//x', 'scripts\evil.gd')) {
        Must-Fail { Assert-RelativePath $path } "Unsafe path rejected: $path"
    }
    $bad = Clone $c; $bad.files[0].url = 'https://example.com/a'
    Must-Fail { Assert-Manifest $bad } 'Unexpected download host rejected'
    $bad = Clone $c; $bad.files[0].url = $bad.files[0].url.Replace($bad.commit, 'main')
    Must-Fail { Assert-Manifest $bad } 'Moving branch URL rejected'
    $bad = Clone $c; $bad.files += $bad.files[0]
    Must-Fail { Assert-Manifest $bad } 'Duplicate manifest path rejected'
    $bad = Clone $c; $bad.files = @($bad.files | Where-Object { $_.path -ne 'project.godot' })
    Must-Fail { Assert-Manifest $bad } 'Incomplete runtime manifest rejected'
    $bad = Clone $c; $bad.schema = 99
    Must-Fail { Assert-Manifest $bad } 'Unknown manifest schema rejected'
    $bad = Clone $c; $bad.engine.files[0].path = '../engine.exe'
    Must-Fail { Assert-Manifest $bad } 'Unsafe engine archive entry rejected'
    $bad = Clone $c; $bad.files[0].size = 9999999999
    Must-Fail { Assert-Manifest $bad } 'Oversized runtime file rejected'
    $script:content[$script:ChannelUrl] = $c | ConvertTo-Json -Depth 12
    Assert ((Get-Channel $root).commit -eq $c.commit) 'Published channel is parsed and validated'
    $script:content[$script:ChannelUrl] = '{broken'
    Must-Fail { Get-Channel $root } 'Malformed channel leaves installed state alone'
    Assert (Test-Installed (Get-Install $root) $root) 'Offline play does not require the release service'
    Assert ((Get-Content $profile -Raw) -eq '{"level":37,"inventory":["gold"]}') 'Unrelated player save is untouched'
    Assert ((Get-Content (Join-Path $root 'server.cfg') -Raw) -eq 'private port and password') 'Hosting configuration remains outside release cleanup'
    Write-Host "`n$script:passed launcher checks passed."
} finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force } }
