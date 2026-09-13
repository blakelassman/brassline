# BRASSLINE 0.8.0 — districts and combat

This update addresses the eight requested changes while retaining the three modes,
instant unshielded respawns, team balancing, 250-kill / ten-minute TDM, map votes,
persistent progression, local prediction and server-confirmed damage.

## Player-facing changes

| Request | Result |
| --- | --- |
| Scope sensitivity | Mouse look scales by `tan(current FOV / 2) / tan(86° / 2)`. Scaling follows the animated FOV. Unscaled screen mouse deltas keep sensitivity consistent across resolutions. |
| Fullscreen / resolution | Borderless fullscreen; 720p, 900p, 1080p, 1440p and 4K presets; custom window dimensions. Display changes require Apply Display and are saved. Window mode is never reapplied by match loading or other settings. |
| HUD clutter | Removed permanent branding, control lists, speed/readiness, boost records, menu hint, redundant score cards and level card. Health, ammo, equipment, crosshair, XP and the existing gold personal kill feed remain. Tab contains network stats and progression. |
| Minimap | North-up arena map, player heading, all living teammates, height markers and two-second enemy firing pings. Enemy dots stay at their last shot position; silent enemies are absent. The server selects contacts for each team. Old-life pings and map transitions are cleared. |
| Counter-strafing | Opposite-input braking reduced from 220 to 145 m/s². Brief residual momentum, rapid direction changes and existing air-strafe / bunny-hop behavior remain. |
| Four rebuilt maps | Foundry workshops and furnace pavilion; harbor offices and loading gantries; Sunspire market arcades and fountain square; Relay communications buildings and raised service bridge. Each has two usable two-story buildings, broad doorways, upper bot routes and solid 6.4 m roofs accessible by grenade jump. |
| Models / visuals | Tapered armor shells, helmet and equipment details, original weapon silhouettes, stocks, guards, rails, optics and blade detail. Shared mesh caching, static weapon batching and lazy remote weapon construction control draw and loading cost. All visible stairs use continuous ramp collision. |
| Sword | 100 damage per hit. Left click attacks; right click starts a 280 ms frontal parry, with 750 ms between parries. Successful parries interrupt the attack and add recovery. Friendly fire remains disabled. Original synthesized steel impact sound. |

Fullscreen uses the desktop video mode and fits the selected render dimensions
inside its 16:9 play area. Window sizes larger than the desktop fit proportionally
inside the usable desktop. Non-16:9 windows are letterboxed. No monitor video-mode
switch or exclusive fullscreen transition is needed.

## Multiplayer and performance

Wire protocol **9** requires everyone to update together. UDP **27020** and the
Windows save path are unchanged. Server damage, score and life checks remain authoritative.

Stress testing the expanded content exposed gaps beyond the old 12-command input
history. Input datagrams now carry up to 32 redundant commands, compressed and
trimmed below MTU. Decoding has explicit compressed/uncompressed size bounds and
still disallows object deserialization. The server earns simulation credit using
its own clock, permits at most eight simulation steps per tick and caps accumulated
credit at 32 ticks. This allows recovery after delayed batches without accepting
client-supplied positions or time steps. Sequence-gap and movement metrics remain
in the test output. Remote weapon timers advance with the accepted input timeline.
Shot timestamps are bounded when received and preserved through the server queue;
history retains at most 72 poses per actor to cover that internal wait. The client
rewind allowance remains capped at 500 ms on receipt.

The additional weapon/armor meshes share cached geometry. Static world weapons
are batched; remote actors construct only weapons they actually equip. First-person
magazines, bolts, support hands and muzzle flashes remain separate for animation.

## Verification

All **417 checks passed**: settings 15, progression 48, core game 62, combat 33,
map expansion 67, polish 49, rendered display 10, multiplayer 57, prediction 27,
lag compensation 20 and ten-player capacity 29. Prediction and moving-target
hit tests use 150 ms one-way delay, 40 ms jitter, 10% packet loss and a 30 FPS
client. The repository includes:

- `--polish-test`: actual FOV-scaled mouse input, counter-strafe momentum, live sword
  damage/parry, radar filtering and expiration, persisted display settings, all
  eight stair ascents, standing upper-floor clearance and solid rooftop collision.
- `--display-test`: rendered window resize, custom aspect ratio, fullscreen and
  preservation of the selected window mode through four actual match starts.
- Existing combat, progression, map, profile and multiplayer suites, including
  real separate host/client processes, player replacement, map votes, reconnection,
  full ten-human capacity, prediction and compensated moving-target hit detection.

Older combat-rule tests now use an isolated firing lane, or explicit coordinates
in the new arenas, instead of depending on removed production walls.

Runtime verification uses Godot 4.7.2 on Linux, including real physics and rendered
OpenGL captures. Windows-specific focus behavior, real hardware frame rates, mouse
feel and audio playback still require a Windows playtest. These are procedural
prototype assets, not a finished commercial art pass.

## Source checkout

Keep the `engine` folder from the existing portable download beside `project.godot`.
Git excludes engine binaries and local saves. Run `START_BRASSLINE.bat` as before.
A source checkout can also be opened with Godot 4.7.2 Standard. Friends need the same
source version. The portable package script excludes Git metadata and caches.

All added art and audio are original and generated locally. No paid assets,
services or servers are required.

Implementation references: [Godot Window scaling](https://docs.godotengine.org/en/stable/classes/class_window.html)
and [Godot DisplayServer's Window API recommendation](https://docs.godotengine.org/en/stable/classes/class_displayserver.html#class-displayserver-method-window-set-size).
