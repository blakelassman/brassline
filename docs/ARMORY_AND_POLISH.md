# Armory and polish: 0.13.0

## Class sidegrades

| Class | Level / total XP | Primary | Body / head | Magazine | Shot interval | Reload |
| --- | --- | --- | --- | --- | --- | --- |
| Vanguard | 1 / 0 | Rifle | 25 / 100 | 24 | 0.16 s | 1.45 s |
| Raider | 3 / 600 | Kestrel SMG | 20 / 60 | 32 | 0.085 s | 1.70 s |
| Sentinel | 6 / 1875 | Bastion LMG | 23 / 75 | 48 | 0.12 s | 2.65 s |
| Marksman | 10 / 4275 | Lancer DMR | 55 / 100 | 12 | 0.42 s | 1.80 s |

The DMR is semi-automatic. SMG recoil is smaller, LMG movement spread is wider,
and the base rifle keeps its one-shot headshot and established spray pattern.
These are initial playtest balances, not a claim of tournament-tested balance.
Classes do not change health, speed, grenade damage or secondary availability.
All four use the primary slot (key 1); pistol, sword and Longshot remain on 2/3/4.

Primary silhouettes have distinct compact, drum-magazine and optic/barrel
variants. Existing rifle finishes apply to all primaries. Names, kill-feed
silhouettes, class damage, reloads and magazine sizes follow the chosen class.
Class visuals are also reconstructed in killcams and shown on remote players.
Bots continue using their standard rifle loadout.

## Progression and selection

LOADOUTS displays class requirements, weapon tradeoffs, current XP, level progress
and the next unlock. Saved XP determines permanent unlocks using the existing
level curve. Rank titles mark levels 1, 3, 6, 10, 25, 50, 100, 500 and 1000.
Reaching a class-unlock level adds a notification beneath the level-up popup.

Offline combat and online selections take effect on the next life/round.
Selections cannot refill the current life. The server validates choices against
its accepted player XP and revalidates them on spawn. Existing local-profile XP
trust remains unchanged; this is not a new centrally verified ranked system.
Joining a live Destroy round inherits the filling bot's current life and supplies,
with the chosen class applied on the next fresh round.

Training allows every class to be tried without permanently granting a locked
class. Unlocked selections and XP persist in the existing profile. No purchases,
new services or paid dependencies are introduced.

## Presentation and responsiveness

- Replace black fades with small animated ROUND/GAME WON/LOST/DRAW banners.
- Keep the existing 1.2-second result window and 3.65/6.75-second replay lengths.
- Warm replay scenery during the result window before changing the camera.
- Run local weapon animation and FOV transitions on rendered frames.
- Ease weapon ADS, moving/idle bob, strafe lean and landing displacement.
- Substep recoil springs so long frames do not fling the weapon out of view.
- Buffer a fire tap for up to 100 ms while weapon recovery finishes. Actual shots
  still use server-authoritative cooldowns, ammunition and damage.
- Add a saved motion slider for bob, lean and landing motion, down to zero.
- Ease visual crosshair spread, fade hit confirmations, show health loss trails,
  and highlight low ammunition with the player's actual reload binding.

Mouse rotation stays immediate. Movement collision, grenade boosts, weapon
accuracy rules, team balance, first-to-six Destroy and TDM limits remain intact.
The game is ready for another friends playtest, not claimed to be a finished
commercial release. Human feedback on pacing, class balance and weaker hardware
is still needed.

## Developer verification

```sh
GODOT --headless --path . -- --armory-test
python tests/run_multiplayer.py --godot GODOT --armory --latency
```

The armory suite tests level boundaries, actual class damage, ammunition/reload,
semi-auto behavior, input buffering, recoil stability, ADS easing, reduced motion,
profile persistence, server selection checks, respawn activation and team-relative
results. The ENet suite verifies remote handshake, class replication, unlock
rejection, queued selection and authoritative ammo after respawn.
Windows CI runs this suite against the staged launcher payload.

Protocol 14 requires all players and the host to update together.
