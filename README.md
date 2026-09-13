# BRASSLINE 0.7.1

A free Windows Godot FPS prototype with movement-focused combat, offline practice,
and self-hosted internet multiplayer. Extract the complete ZIP and run
`START_BRASSLINE.bat`. See `START_HERE.txt` for controls and `HOSTING.txt` for hosting.

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

Godot 4.7.2 Standard for 64-bit Windows is included. No editor installation,
paid assets, account, database or rented server is needed. Networking uses ENet
UDP, default port 27020. Friends outside your home use your public IP and port;
your router must forward the UDP port to your host PC.

`START_DEDICATED_SERVER.bat` optionally runs the same project headlessly using
`server.cfg`. You can instead use **Host & Play** in the menu.

Levels and settings use an atomic local profile with a backup:
`%APPDATA%/Godot/app_userdata/Brassline Offline Arenas/profile_v1.json`.
The old application directory name is deliberately retained for save stability.
The dedicated server has a separate `server_profile_v1.json`.

## Implementation and verification

- Immediate local movement and weapon/grenade presentation, with numbered input
  replay only during physics ticks and redundant UDP input delivery.
- Host-owned damage/score; bounded historical hitbox checks compensate for the
  moving-target position displayed to the shooter, with a 500 ms maximum rewind.
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
