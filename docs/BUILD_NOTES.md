Current update: [0.9 challenges, recoil and Locker](UPDATE_0_9.md).

# Current build: 0.8.0

Read [UPDATE_0_8.md](UPDATE_0_8.md) for current behavior and verification.
The notes below are historical records of earlier prototypes.

---

# BRASSLINE 0.7.1 - client responsiveness and lag compensation

Everyone must update. Wire protocol 8 rejects the previous protocol 7. The
Windows save directory and UDP port remain unchanged.

## Problems found and corrected

The old server used the most recently received direction and acknowledged its
sequence immediately. It did not consume each input frame exactly once. The
client then replayed a different movement history from the host. Reconciliation
also called CharacterBody3D.move_and_slide() from incoming RPC processing instead
of explicitly scheduling it at a physics tick. That function depends on the engine
physics delta. Together these produced unnecessary backward movement under delay.

Inputs now carry fixed-tick sequence numbers, jump, crouch, yaw, pitch and the
movement aim state. Each UDP send repeats up to 12 pending frames. The host
validates, deduplicates and simulates frames before acknowledging them. A server
clock budget limits movement processing; client-supplied delta/position is never
accepted. Reconciliation runs at the start of local physics, with recorded aim
state and silent replay. Cosmetic camera correction decays separately from the
collision capsule. Duplicate life/spawn messages do not erase current prediction.

Local gun rays immediately draw tracers and world impacts without granting hits.
Recoil, ammo, weapon selection, scope and reload begin locally. Server acknowledgments
reconcile inventory without playing the shooter's tracer twice. Grenades appear
on the throw frame and reuse that visual when their authoritative ID arrives.
They predict collision/bounce motion, but damage, boosts and explosions remain
server-confirmed. Replayed grenade state does not replay bounce sounds.

Remote actors use a smoothly advancing render clock, an adaptive 50-120 ms buffer
and up to 80 ms of extrapolation. The previous two-sample branch could remain
clamped to the newest position instead of entering extrapolation. The HUD reports
round-trip ping, client FPS, server simulation Hz and prolonged update gaps.

## Aiming directly at a moving opponent

Hitscan requests carry the server-time timestamp used to render the remote world.
The host clamps that timestamp to measured RTT plus a small interpolation/jitter
allowance, with an absolute 500 ms maximum. It records up to 48 recent hitbox poses
per slot, then analytically intersects rays with interpolated historical head
spheres and body boxes. Live actors are never moved or rewound in the physics world.

Walls are tested at the same ray distance and stop bullets; friendlies remain
safe and block shots. Sniper penetration excludes already hit actors. History
includes actor identity and life ID, so old shots cannot kill a new occupant or
freshly respawned life. The host still validates weapon, fire cadence, ammo and
scores. A player can receive a delayed hit after reaching cover if the shooter
saw them exposed, within the bounded window. This is the usual tradeoff of rewind.

## Validation

See TEST_RESULTS.txt for actual pass records and network metrics. Tests use real
separate ENet processes, with a UDP proxy that adds independent per-direction
latency/jitter and random loss. Added tests cover prediction at 30 FPS, movement
ACK ordering, malformed/stale input, simulation rate limits, aim/crouch/air movement,
local effects, ammunition and reload acknowledgement, grenade deduplication,
duplicate spawns, interpolation/extrapolation, and historical hit detection.

The old build's 200 ms round-trip / 5% loss straight-run test had a 12.5 cm
backward step and four corrections above 20 cm. The revised movement test had
no backward steps or corrections above 20 cm; both jump apexes agreed. A 300 ms
round-trip / 10% loss test with a 30 FPS client also passed.

A separate moving-target test aimed at the displayed opponent without manual
lead. The server confirmed the kill, and verified that the current-position ray
would have missed without lag compensation. Historical head/body classification,
wall blocking, friendly fire, old-life rejection, time bounds and memory bounds
also have dedicated assertions.

Commands (Python optional; only for developers):

    python tests/run_multiplayer.py --godot /path/to/godot --prediction --latency --delay-ms 150 --jitter-ms 40 --loss .10 --client-fps 30
    python tests/run_multiplayer.py --godot /path/to/godot --lag-compensation --latency --delay-ms 150 --jitter-ms 40 --loss .10
    python tests/run_multiplayer.py --godot /path/to/godot --latency
    python tests/run_multiplayer.py --godot /path/to/godot --capacity
    python tests/package_windows.py Brassline_Prototype_0_7_1_Windows.zip

Actual Windows frame rate and the user's internet route still require friend
playtesting. Network travel time cannot be eliminated, and another player's
unreceived input cannot be predicted exactly. Confirmed hit sounds, damage, XP
and grenade boosts still await the host. Very high ping, outages, collisions with
moving actors or an overloaded host can still produce corrections. There is no
ranked anti-cheat or cloud account system in this private-server prototype.

Technical references:
- https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html
- https://www.gabrielgambetta.com/client-side-prediction-server-reconciliation.html
- https://www.gabrielgambetta.com/lag-compensation.html

---

Previous release notes below are historical; 0.7.1 replaces the old prediction
and the statement that the prototype has no historical hitbox rewind.

# BRASSLINE 0.7 — self-hosted internet multiplayer

Released build scope: Windows x86-64, Godot 4.7.2 Standard, free portable project.

## Behavior

Three modes: original aim training, endless offline 5v5 bots, and online TDM.
Online teams have five slots each. Human joins alternate toward the team with
fewer humans; bots occupy every unused slot. Departures trigger bot replacement
and, if needed, human team rebalancing with XP and K/D retained. Full capacity is
ten humans, with an explicit error for an eleventh. A dedicated server initially
has ten bots; a host-and-play server initially has one human and nine bots.

Online matches end immediately at 250 team kills or after 600 seconds. The higher
score wins at time expiry, or the round draws. No overtime. The 15-second voting
phase accepts one changeable vote per connected human. Ties rotate among the tied
maps; no votes rotates to the next map. Round scores reset while connections and
XP persist. No shields or respawn countdowns were added.

All authoritative movement, inventory, damage and scoring run on the host.
Client inputs and action commands are bounded and associated with the authenticated
peer and current life ID. Clients cannot provide hit results or positions.
Movement is predicted locally, reconciled using acknowledged input history, and
other actors render with interpolation. State snapshots run at 20 Hz, use DEFLATE,
and are split into 1050-byte chunks when needed, avoiding oversized UDP payloads.
RPC object decoding is disabled and client-to-client relay is disabled.

Local profiles save XP, stable local ID, player name, bindings, sensitivity,
volume, graphics quality, frame cap and fullscreen. Writes use a temporary file
and backup; malformed primary data can recover from the backup. The dedicated
server uses a separate profile. The level cap remains 1000 (25,199,775 XP).

## Verification

- 62/62 weapon, grenade, movement and rendering-isolation checks.
- 33/33 offline combat, bot routing and instant-respawn checks.
- 48/48 progression, XP animation, sniper scope and recoil checks.
- 62/62 expansion checks across all four maps.
- 15/15 persistence, rebinding, crouch clearance and graphics checks.
- 53/53 checks using real separate host/client processes: handshake, opposing
  teams, replicated movement/crouch/grenades, confirmed headshot kills and XP,
  instant human respawn, 250th-kill finish, time expiry, vote changes, map loading,
  disconnect/bot replacement, password rejection, reconnect and host restart.
- 29/29 full-capacity checks across a host, nine clients and an extra rejected
  client: 5v5 humans, zero bots, full-server rejection, multiple departures,
  rebalancing, stable roster and surviving clients staying connected.
- Separate writer/reader game processes reload exactly 98,765 test XP and .0037
  sensitivity. Dedicated mode starts on its configured UDP port with ten bots.
- The network flow also passes through a real UDP proxy with 40 ms delay each
  direction, +/-10 ms jitter and 2% configured random packet loss. Example run:
  474 datagrams, 7 dropped, maximum observed datagram 908 bytes. This is a small
  controlled integration test, not a measurement of the user's internet service.
- Rendered startup, online/settings/controls screens, voting and arena views
  inspected using the OpenGL Compatibility renderer.

Total automated assertions above: 302, plus process-restart, dedicated-start and
visual checks. Test fixtures accelerate the match boundaries by setting scores
to 249 before a real kill and advancing the deadline; they exercise the normal
round-ending code rather than waiting ten wall-clock minutes per test.

## Performance changes

Static world meshes are merged by material while collision shapes remain intact.
Bot geometry is merged within each animated joint. Static spawn-clearance results
are cached while live spawn scoring still considers current players and sightlines.
Low quality reduces particles, impact marks and falling-body effects; balanced
turns off dynamic sun shadows/MSAA; high restores shadows and 2x MSAA.

In a fixed Dry Dock view, draw calls dropped from 343 with batching disabled to
171 enabled (about 50% fewer). These figures include the same camera and preset.
The render environment uses Mesa llvmpipe software rendering; its frame times
are not representative of a Windows gaming GPU, so no numerical FPS promise is
made. Host upload speed, CPU and clients' GPU/connection quality still matter.

## Practical limits

This is an internet-capable private multiplayer prototype. Router forwarding,
Windows Firewall and actual reachability from the user's friends have not been
tested here. Follow HOSTING.txt and test one friend first. It uses public IP/port
hosting, not public matchmaking or an automatically hosted service.

There is no historical hitbox rewind in this release. High-ping players may need
to lead moving targets. The host is trusted; local XP is editable private-game
progress, not a ranked anti-cheat account system. A crash or forced shutdown may
retain only the last confirmed/saved XP. Normal leave/quit flushes confirmed
progress and earned chain bonuses. A connection loss during an unsettled chain
can lose an unconfirmed bonus. Windows executables are hash/PE verified; gameplay
was executed in the native Linux Godot build rather than on the user's Windows PC.

## Reproducing tests

From the project folder, run the bundled engine with --headless --path . -- and
one of --self-test, --combat-test, --progression-test, --expansion-test,
--settings-test. For network process tests, Python is optional developer tooling:

    python tests/run_multiplayer.py --godot /path/to/godot --latency
    python tests/run_multiplayer.py --godot /path/to/godot --capacity

The Windows engine path defaults to the bundled console executable. Test profiles
and process-coordination files are isolated from the normal saved player profile.
The portable package builder verifies the exact engine hashes and full PE sections:

    python tests/package_windows.py Brassline_Prototype_0_7_Windows.zip

---

Previous release notes (historical; 0.7 supersedes session-only progression and
any statements that the project does not support multiplayer):

# Build 0.6: four arenas and a presentation expansion

Adds Dry Dock, Sunspire and Relay beside the preserved Foundry Yard. Menu map
selection supports both aim training and endless 5v5. Each map has original
architecture, surface families, lighting, ambience, training placements and four
clear spawn corners. Physics clearance rebuilds the ground graph on map change.
Real player movement can walk up each new ramp and join its upper platform.

Improves first-person handling with recoil springs, sway, landing/equip motion,
reload hand and magazine travel, bolt/slide action, muzzle flashes and casings.
Weapon geometry has bevels and additional glove/receiver/sight details. Rigs add
walking limbs, hit reactions and brief cosmetic falls without delaying respawns.
Assault, flanker and marksman bots differ in movement, burst rhythm, aim and gear.
All remain 100 HP rifle opponents; all retain normal team damage rules.

Adds locally synthesized foley, footsteps by surface, impacts, grenade bounces,
smoke hiss, map ambience and menu/kill feedback. Existing gun sounds have fuller
layers. Textures are procedural, with normal relief and cached materials. Bounded
particles, bullet marks and body remnants add impact feedback without collisions.

The local starting snapshot was 0.3. The accepted 0.4/0.5 behavior was rebuilt from
the retained implementation context before the expansion: Tab K/D/levels/XP,
level 1000 cap, scoped sniper fire, icon feed, floating points, exclusive tier
bonuses and respawn-safe reward sequencing. Current rules are in README.md.

Verification: 205 automated checks across gameplay, combat, progression and all
maps; rendered reviews of maps, bot variants, menu, reload, scope, award/bonus
presentation and scoreboard. Portable Windows engine hashes and ZIP CRC/contents
are checked by the packaging script. Runtime verification uses Linux Godot,
including software-rendered visual review. Windows performance and final audio
balance still require the owner's playtest. No payments or online services.

---

# Build 0.3: endless offline 5v5

The final requested offline feature pass adds a separate 5v5 bot mode while
preserving aim training. Four friendly bots plus the human face five enemy
bots on the original map. Four corner spawn zones consider enemy pressure,
occupancy and friendly support. There is no match end or score/time limit.

The owner's final correction is adopted: NO spawn shield and NO respawn
countdown. Dead actors respawn at the end of the frame, immediately vulnerable.
The human receives full health, ammunition and both grenades. Esc pauses;
resume keeps the current fight; selecting a mode starts a fresh session.

Rifle bots patrol ground routes, strafe, acquire visible enemies with moderate
reaction time, fire three-round bursts and reload. Walls block bullets and
smoke blocks sight. Friendly fire is disabled. Bots can kill the human and
each other. Combat HUD shows health, human K/D, team kills and named kill feed.

LONGSHOT capacity is six. Added original bolt-open/close sounds and a small
handling animation during rechambering. The scope lowers during this cycle.

Verification: original 62 gameplay checks, plus 33 combat checks, including
live bot rifle damage against the human, immediate unprotected respawns,
mode transitions and a continuous simulated skirmish. Menu, combat HUD,
respawn view and sniper cycle visually inspected. Windows package engines
are verified inside the ZIP. Tests run on Godot 4.7.2 Linux; Windows feel,
performance and audio mix require the owner's playtest.

No new purchases, paid assets or hosted infrastructure. Bots are moderate
rifle practice opponents; advanced jumping, climbing and tactics are not in
this offline pass. Current controls and rules are in START_HERE and README.

---

# Build 0.2: movement and precision pass

Implemented from Blake's first Windows playtest, September 12, 2026.
No new tools, assets, subscriptions or hosting were purchased.

- Separate transparent viewmodel rendering keeps hands and weapons visible
  against cover; bullet rays still stop at cover.
- Five meter lethal enemy blast radius, retaining self/team immunity and
  visibility checks. G/Q equip, left-click throws and right-click short tosses.
- Tighter release stopping and faster opposite-input braking; projection-based
  air strafing and timed landing hops preserve momentum. Wheel down jumps.
- Movement-dependent gun spread, with the accepted airborne pistol exception.
- Rifle head damage is now 100. New LONGSHOT sniper has a 120 ms scope-in,
  lethal body/head hits, a five-round magazine, bolt motion and collaterals.
- Four main kill-feed entries with two fading overflow entries, headshot and
  collateral tags, and a rapid-kill streak counter.
- Original layered headshot crunch, sniper shot, reload handling cues,
  magazine/hand/bolt reload motion, and runtime concrete/metal textures.

Validation: 62 gameplay checks passed in Godot 4.7.2 Linux, including live
input, ray/cover/penetration, reload, movement, grenade and audio-load tests.
Rendered arena, menu, wall contact, scope, reload, held grenade, feed and
sniper views inspected with the compatibility renderer. Package validation
checks executable completeness and pinned hashes inside the finished ZIP.
Windows performance, actual audio mix and subjective feel require playtesting.

START_HERE.txt has current controls. README.md has current balance values.
Archive_Game_Plan_Revision02.docx preserves the earlier design; build 0.2
supersedes its combat/control values. Online play remains a later milestone.

---

# Build 0.1

Packaging repair, September 12, 2026: the initially shipped main Windows
executable was truncated to 154,599,424 bytes. Restored the complete
180,858,888-byte executable from the original official release archive.
The packaging script now verifies both engine SHA-256 hashes and PE section
bounds before packaging, then verifies the executable bytes inside the final
ZIP. These checks validate file integrity; Windows execution remains untested
in this Linux workspace. Gameplay source is unchanged by this repair.

The first scope adopts the owner's zero-new-spending rule and makes the
blast jump available before any online duel. Rifle and pistol shooting are
primary. The sword is a close-range fallback.

This build contains original procedural geometry and synthesized sound.
The official unmodified Godot 4.7.2 Windows x86-64 binaries are included to
minimize player setup. Their source download is
https://godotengine.org/download/windows/ and the release is pinned here.
No network is required to play; none is implemented in the game.

Verification uses Godot 4.7.2 on Linux, including actual scene physics and
an OpenGL software rendering capture. Windows execution, real audio output,
mouse feel, and the user's hardware performance still need a local playtest.

Keep source changes in this folder and preserve the raw sound files.
Do not require the owner to learn the editor for routine revisions. Supply
an updated portable package and concise instructions.

Do not add paid infrastructure, subscriptions, assets, or tools. Local and
LAN networking trials can follow the movement playtest. If later internet
hosting needs money, present a concrete cost and wait for the owner's decision.
