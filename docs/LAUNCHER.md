# Windows launcher

## For Blake and friends

Merge this launcher PR, then wait for the **Windows launcher** Action on `main`
to finish. It automatically creates the public **BRASSLINE Launcher** release.
Share this permanent link with friends:

[Download BRASSLINE Launcher](https://github.com/blakelassman/brassline/releases/download/launcher/Brassline_Launcher_Windows.zip)

Each friend extracts the launcher ZIP once and opens `BRASSLINE_LAUNCHER.bat`.
Click **Install & Play**, then optionally **Desktop shortcut**. Next time they
open the launcher, **Update & Play** installs the latest published game and runs
it. **Play installed** launches without any network requests. There is no
recurring ZIP replacement. The download link is created by the first successful
main-branch workflow; it does not exist before that workflow publishes.

To reuse an existing copy, extract the launcher beside its `engine` folder and
`project.godot`. Matching files are copied to the launcher's separate install.
The old game and any Git checkout are left untouched. Use the launcher afterward.

The first fresh installation downloads the engine and runtime. Later updates
reuse the engine and all files whose contents are unchanged. This is **file-level
incremental updating**: a changed file downloads in full; unchanged files do not.
An engine-version change downloads the new engine once.

## Updates, saves and hosting

- **Update & Play** checks the published channel, updates if needed, then launches.
- **Play installed** runs the existing build offline after checking its integrity.
- **Repair** checks all managed files and restores missing/damaged content.
- **Previous version** switches to the preceding installed version. Click
  **Play installed** afterward to stay on that version.
- **Game folder** opens `%LOCALAPPDATA%\BrasslineLauncher`, containing logs,
  the stable engine directory, and the editable dedicated-server `server.cfg`.
- **Dedicated server** uses that configuration. **Host & Play** remains in-game.
- Update checks/downloads run outside the UI thread. Close the launcher to stop
  an operation; reopening/retrying reuses verified downloads.

The game and dedicated server must be closed before updates or rollback.
All online participants should run the same published version.
Saves remain at `%APPDATA%\Godot\app_userdata\Brassline Offline Arenas`.
The launcher does not modify the profile or change game/network rules.
Rollback changes the game files, not your saved progress; a much older game
may not understand features in a newer profile.

The engine moves to a stable launcher-managed path on the first installation.
Windows Firewall may need one new allowance for that path when hosting; the
launcher never changes firewall/router settings. Keep the existing UDP port
forwarding rule. Subsequent game updates use the same executable path.

The desktop shortcut keeps its bootstrap/fallback scripts in the install folder,
so the original ZIP extraction folder can be removed after making the shortcut.
Do not delete `%LOCALAPPDATA%\BrasslineLauncher` while using that shortcut.

## How a new release gets to players

1. Merge reviewed changes to `main` as usual.
2. GitHub Actions runs updater integration tests in **Windows PowerShell 5.1**,
   verifies the pinned Windows engine download, imports the real game payload,
   creates the launcher window in a UI smoke test, and packages the artifacts.
3. Only after those checks succeed, it uploads the launcher ZIP and checksums to
   the `launcher` GitHub release and uploads `channel.json` last.
4. Players' launchers read that channel. No extra server, database or account is
   needed. A failed build does not publish a new channel.

The repository is public, so this uses public GitHub Actions/Release hosting.
Updates are published builds, rather than downloads of a moving branch mid-edit.
PR workflows produce a downloadable artifact but cannot publish a release.
For a manual retry, run **Windows launcher** from the repository's Actions tab.

## Integrity and recovery

`channel.json` has a full commit SHA, version label, file sizes/SHA-256 hashes,
and URLs pinned to that commit. Only runtime files and the versioned launcher
scripts are included. The engine archive and both engine EXEs have pinned hashes.
Channel and payloads come over HTTPS from the repository owner's GitHub release;
this is not a code-signing system, and the owner account remains the trust root.

The updater rejects absolute/traversal paths, Windows reserved names, duplicate
paths, unknown schemas, unexpected hosts and oversized file descriptions. It
uses a content cache and a new version directory, validates downloads, runs
Godot's headless import, and atomically replaces the active pointer only after
success. The old install stays active on transfer/checksum/import failures.
No active game files are overwritten during download. A lock prevents concurrent
updates; running launcher-managed Godot processes block update/rollback.

Current and previous versions are retained; older managed versions and unused
cache entries are removed after successful activation. The engine path remains
stable. The fixed bootstrap picks up the new UI/updater from the active version
on the next launch, verifies their installed hashes, and falls back to its
bundled scripts if those are damaged. Profiles and root `server.cfg` are outside
version cleanup. No administrator rights or global execution-policy changes.

## Developer verification

Run `powershell -NoProfile -File tests/test_launcher.ps1` on Windows, or `pwsh`
on Linux for the portable core tests. The deterministic tests use real temporary
installs with injected downloads/imports, covering changed-file accounting,
retries, integrity errors, rollback, cleanup, locking, path validation and config
preservation. CI separately exercises the real engine/import and WinForms UI.

Commit the source before running `python tests/package_launcher.py dist`:
packaging reads Git blobs from the specified commit, so a half-edited working
copy cannot leak into a published channel. `--commit FULL_SHA` selects a commit.
When changing the engine, update `launcher/engine.json` and the portable builder's
pinning together. Keep the save application name stable.
