BRASSLINE LAUNCHER - ONE-TIME SETUP (64-bit Windows 10/11)

1. Extract this entire ZIP to a folder you want to keep.
2. Double-click BRASSLINE_LAUNCHER.bat.
3. Click INSTALL & PLAY. The first install downloads the game and its engine.
4. Optional: click Desktop shortcut. After that, use BRASSLINE on your desktop.

Next time: open the launcher and click UPDATE & PLAY. Only changed game files
are downloaded. No more replacing ZIPs or copying files for each game update.
The launcher updates its own interface and updater along with the game.

Already have BRASSLINE? Extract the launcher beside your existing engine folder
and project.godot. It checks and copies usable files to its own install folder,
saving downloads. It does not alter that original copy or your Git checkout.
Use the launcher for future play so you do not accidentally launch the old copy.

Play installed works without internet. Repair verifies and restores game files.
Previous version switches back to the last working build. Use Play installed
then, since Update & Play always installs the latest published build.
Close the game and any dedicated server before an update or rollback.
All online players, including the host, should update together.

Saves: your existing level, challenges, inventory and controls stay at
%APPDATA%\Godot\app_userdata\Brassline Offline Arenas\profile_v1.json
They are not deleted or replaced by updates, repair or rollback.
There is no new account, subscription, Git or Python installation needed.

Game files, logs and editable server.cfg are under:
%LOCALAPPDATA%\BrasslineLauncher
Click Game folder to open it. Edit server.cfg there for the dedicated server.
Host & Play in the game's menu still works normally.

Your existing UDP 27020 router rule stays the same. Windows Firewall may ask
once for the engine in its new location: allow it on the network you host on.
Future game updates reuse that engine path, so they do not change that rule.
This launcher does not change any router or firewall settings automatically.

If an update fails, Play installed keeps the last completed version available.
Retry to reuse already verified downloads. Close and reopen the launcher if
a download stalls. If asked for help, include launcher.log and brassline.log
from Game folder. Very slow first-run preparation can take several minutes.

Updates are served from the public blakelassman/brassline GitHub repository.
Every release is pinned to one commit, and downloads are verified with SHA-256.
The launcher is unsigned; never turn off Windows security to run a download.
Only obtain BRASSLINE from the repository owner's shared GitHub release link.
