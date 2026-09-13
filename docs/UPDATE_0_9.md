# BRASSLINE 0.9.0: challenges and the Locker

## Achievements and repeatable medals

The Challenges menu contains **86 permanent milestones across 24 tracks**. Progress
is shared across aim training, endless bots and online play, except wins, which
require an online team victory. Existing progress starts counting from this update;
old kills cannot be reconstructed from XP.

Tracks cover total kills, headshots, airborne kills, airborne headshots, boosted
kills, two- and three-player sniper collaterals, killstreaks, multi-kill chains,
each weapon, quickscopes, no-scopes, long shots, low-health kills, parries, perfect
boosts, one-shot kills, revenge, wins and consecutive headshot kills.

Killstreak milestones are **5, 10, 15, 20, 25, 30 and 50** without dying or starting
a new match. Multi-kill gaps cannot exceed **1.35 seconds**, allowing a clean sniper
chain. Collaterals count once per shot, not once per victim. Quickscope kills require
0.12–0.45 seconds of scope time; long shots require at least 30 meters; boosted kills
require being airborne within five seconds of a grenade boost.

A gold top-center notification and original short quest chime announce completed
milestones and repeatable medals. Notifications queue separately from player lives
and match clocks, so respawning cannot erase them. Menus pause their playback.
All milestone notifications are retained; at most six repeat medals wait behind
one another to prevent an endless backlog. These are mastery milestones; the
existing kill/chain XP system is retained without additional achievement XP.

Online milestones use reliable host-confirmed kill metadata and specialty events.
Local predicted shots cannot award achievements. Persistent progress remains a
local profile, not a tamper-proof cloud account or competitive ranking service.

## Rifle practice

The rifle now uses an original, fixed **24-round S-shaped recoil sequence**, inspired
by learnable older survival-shooter recoil. It is not a copy of Rust's exact table.
It climbs and reverses horizontally twice. Every shot uses the same increments;
ADS does not change the pattern. Counter the camera movement with your mouse.

A **650 ms pause**, weapon switch, grenade equip, reload or respawn resets the
sequence. A stationary grounded rifle has no random spread, so exact compensation
can keep all 24 shots centered. Existing moving/airborne spread still applies.

## Locker and free District Collection cases

The Locker offers **55 styles**: five standard loadout items and **50 case finishes**
covering operator outfits, rifle, heavy pistol, sword and sniper. Operator outfits
combine three existing armor silhouettes with new finishes; team-colored armor
panels remain visible. Weapon finishes include stripes, circuit patterns, camouflage,
metallic colors and an animated Aurora finish. They never change damage, movement,
accuracy or hitboxes.

The inventory has equipment and rarity filters, duplicate counts, an optional
unowned collection view, rotating 3D previews and Equip buttons. Equipped cosmetics
appear on remote human models and survive death, map changes and future launches.
Material instances are shared; cosmetic armor geometry is batched per animated
joint, and the menu preview stops rendering while hidden.

Every opening is free and unlimited. There are no keys, purchases, trading,
marketplace, cash value or connection to real-money skins.

| Rarity | Exact chance per opening |
| --- | ---: |
| Field | 70% |
| Signal | 22% |
| Elite | 6% |
| Mythic | 1.75% |
| Special | **0.25% / 1 in 400** |

An integer roll across 10,000 outcomes selects the rarity, then a uniform draw
selects an item within that rarity. The 1-in-400 chance applies to the Special tier,
not to one specific finish, and does not guarantee a drop on the 400th opening.
All rolls are independent. Duplicates increase an item's count.

The actual drop is saved before the 3.2-second reel animation begins. Skip Reveal
finishes the same opening; closing the game cannot discard its saved reward. Failed
saves roll the opening back. Decorative reel entries use the same rarity weights.
The revealed card, inventory entry and preview all use the same selected item.

## Multiplayer and updating

Protocol **10** requires hosts and friends to update together. Keep your existing
`engine` folder beside `project.godot`, then use `START_BRASSLINE.bat`. UDP **27020**,
the Windows save location, existing XP, settings and keybinds are unchanged.

Join allocation now balances the humans who have actually finished loading. If
loading completes out of order, pending reservations swap before spawning, avoiding
a temporary 2-vs-0 human match. Remote reload presentation follows the same numbered
input timeline as movement, accounting for both transport delay and server queues.

## Verification

**368 checks passed** across the following suites:

| Suite | Passed |
| --- | ---: |
| New collection / challenges / actual rifle firing | 66 |
| Core gameplay | 62 |
| Settings and profile recovery | 15 |
| Existing XP / progression | 48 |
| Offline bot combat | 33 |
| Real host / client / rejection flows | 65 |
| Prediction under delay and loss | 30 |
| Moving-target lag compensation | 20 |
| Ten-player capacity and team balancing | 29 |

Prediction and moving-target tests used **150 ms one-way delay, 40 ms jitter,
10% packet loss and a 30 FPS client**. The prediction test also verifies a shot
immediately after reload is acknowledged without refunding or double-spending ammo.

The new collection suite verifies
milestones, streak resets, persistent counters, notification continuity, every case
roll boundary, duplicate handling, save/load, failed-save rollback, real weapon
spray repetition and exact inverse compensation, actual cosmetic materials and the
case-to-inventory/equip flow. Real separate host/client tests cover confirmed online
achievements, wins, cosmetic replication, map rotation and persistence on disconnect.

Rendered OpenGL captures cover the Locker, operator and weapon previews, case
reveal, Challenges and in-game medal placement. Runtime checks use Godot 4.7.2 on
Linux; Windows hardware FPS, audio playback and mouse feel still need local playtesting.
