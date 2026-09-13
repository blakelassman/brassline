# BRASSLINE 0.9.0

A free Windows Godot FPS prototype with movement-focused combat, offline practice,
and self-hosted internet multiplayer. Extract the complete ZIP and run
`START_BRASSLINE.bat`. See `START_HERE.txt` for controls and `HOSTING.txt` for hosting.

## New in 0.9.0

- **86 permanent challenges** across 24 tracks: jump shots, airborne headshots,
  boosted kills, double/triple collaterals, 10/30/50-kill streaks, quickscopes,
  no-scopes, weapon mastery, parries, payback and team wins. Top-center medal
  notifications use an original quest chime and survive respawns.
- **Learnable rifle recoil:** a fixed 24-round S-shaped spray with stronger
  horizontal reversals. Pull down and counter its left/right movement. A 650 ms
  pause resets it; stationary spread remains zero, movement spread remains active.
- **Locker:** 55 operator/weapon styles, rotating previews, saved inventories,
  equipment/rarity filters and online cosmetic replication. Team-colored armor
  stays visible. No cosmetic changes damage, accuracy, speed or hitboxes.
- **District Collection cases:** free and unlimited, with a scrolling reveal,
  skip option, duplicate counts and one-click equip. Drops save before animation.
  Rarity odds: Field 70%, Signal 22%, Elite 6%, Mythic 1.75%, Special **0.25%
  (1 in 400 per opening)**. No purchases, keys, trading or cash value.

Everyone must update together (network protocol **10**). Existing XP, display and
keybind settings carry over. Challenges and inventory persist on the same Windows
user profile. See `docs/UPDATE_0_9.md` for behavior and verification details.

## Previous: 0.8.0

- Scope sensitivity follows the current FOV, including the zoom transition.
- Borderless fullscreen, resolution presets through 4K, custom window sizes and
  a consistent 16:9 play area. Loading a match no longer reapplies window mode.
- Minimal HUD; ping/FPS moved to Tab. Teammates stay on the minimap; gunfire
  reveals an enemy's last shot position for two seconds, with elevation markers.
- Slight counter-strafe momentum; sword attacks deal 100 damage. Right-click
  parries frontal sword attacks for 280 ms, with 750 ms between guards.
- All four arenas rebuilt as distinct districts with two-story interiors,
  continuous ramp collision under visible stairs, upper bot routes and solid
  grenade-accessible roofs. Original armor, weapon geometry and parry sound.

UDP 27020 remains unchanged. The previous update is documented in `docs/UPDATE_0_8.md`.

## Play

- **Aim training:** passive targets, movement and boost-jump practice.
- **Endless 5v5 bots:** one human with four allies against five enemies.
- **Online TDM:** ten slots, balanced human teams, bots filling empty slots.
  First team to 250 kills wins; ten-minute maximum; 15-second map votes.

Four arenas: Foundry Yard, Dry Dock, Sunspire and Relay. Rifle, heavy pistol,
sword and six-round quickscope sniper. Blast and smoke grenades. Headshot sounds,
weapon animations, persistent levels, XP stacks and bonuses, scoreboard and kill feed.
Respawns remain instant with no shields. Ctrl/C crouch; all controls are rebindable.

## Free and portable

Portable packages include Godot 4.7.2 Standard for 64-bit Windows. The source
repository excludes engine binaries: keep the `engine` folder from your existing
BRASSLINE download beside `project.godot`, or open `project.godot` with Godot
4.7.2 Standard. No paid editor installation,
paid assets, account, database or rented server is needed. Networking uses ENet
UDP, default port 27020. Friends outside your home use your public IP and port;
your router must forward the UDP port to your host PC.

`START_DEDICATED_SERVER.bat` optionally runs the same project headlessly using
`server.cfg`. You can instead use **Host & Play** in the menu.

Levels, settings, challenge progress and inventory use an atomic local profile with a backup:
`%APPDATA%/Godot/app_userdata/Brassline Offline Arenas/profile_v1.json`.
The old application directory name is deliberately retained for save stability.
The dedicated server has a separate `server_profile_v1.json`.

## Implementation and verification

- Immediate local movement and weapon/grenade presentation, with numbered input
  replay only during physics ticks and redundant UDP input delivery.
- Host-owned damage/score; bounded historical hitbox checks compensate for the
  moving-target position displayed to the shooter, with a 500 ms rewind limit when a shot is received; validated timestamps survive
  the bounded server command queue.
- Per-player time budgets constrain input simulation; old-life shots are rejected.
- Twenty state updates per second, compressed and split below the UDP MTU;
  adaptive remote interpolation, confirmed hit/kill feedback and map transitions.
- Persistent local XP up to level 1000; no paid or cloud progression service.
- Static geometry and articulated bot mesh batching; cached spawn clearance;
  low/balanced/high graphics presets, sound, sensitivity, fullscreen and FPS cap.
- Three practice/combat bot styles retained from 0.6.

Read `docs/BUILD_NOTES.md` for test results and prototype limitations. Automated
Godot tests and optional Python process runners are included in `tests`.
Python is only needed to run the developer test orchestrators, not to play.
The portable ZIP builder verifies both Windows executable hashes and PE sections.

All game art is built procedurally in code; sounds are original synthesized WAVs.
See `GODOT_LICENSES.txt` for the included engine's licenses.
