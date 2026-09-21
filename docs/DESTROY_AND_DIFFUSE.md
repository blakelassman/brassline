# Destroy and Diffuse — BRASSLINE 0.10.0

Choose **Online → Game mode → Destroy and Diffuse**, then Host & Play or Join
Server. Joining still uses a public IP/hostname, UDP port and optional password.
Both ends select the same mode; a mismatch gives a specific error. This update
does not add a global matchmaking directory. TDM remains a separate selection.

Everyone updates through the launcher. Network protocol is now **14**; old
clients cannot join. Your profile, XP, inventory and existing UDP rule carry over.
Dedicated hosts set `mode="destroy"` in their existing `server.cfg`; omitted mode
continues to mean TDM. The launcher preserves your server configuration.

## Match rules

- Ten slots, five per team. Humans replace bots, joining the team with fewer
  humans. Bots fill every remaining slot and can kill, carry, plant and defuse.
- **Best of eleven: first team to six round wins.** Roles switch after round five.
  Blue begins attacking; red attacks from round three. Team scores stay with
  their team. A deciding fifth round uses the post-halftime roles.
- **120 seconds per round.** A completed plant starts a separate **60-second**
  bomb countdown. An unplanted timeout awards the round to defenders.
- One bomb and two ground-level sites, **A and B**. The carrier rotates through
  attacking slots each round. Every player receives the normal combat loadout.
- Hold **E** while stationary at a site for a **4-second plant**. Defenders hold
  **E** within 1.9 metres of the planted bomb for an **8-second defuse**. No kits.
  You must be grounded, close enough, and have an unobstructed interaction path.
  Movement, release, death or losing access interrupts progress. Progress resets;
  teammates cannot inherit another player's partial action. Reloading or holding
  a grenade prevents interaction. Guns cannot fire while interacting.
- **X** drops the bomb. Living attackers automatically pick up a nearby dropped
  bomb. A short pickup lock lets the carrier actually hand it off. Death drops
  it onto nearby navigable ground so it cannot become trapped on a roof or off
  the map. Teammates see the carrier/drop on their minimap; defenders do not
  receive the unplanted bomb location in objective packets.
- No respawns during a round. Eliminate defenders to win as attackers. Eliminate
  all attackers before planting to win as defenders. After a plant, surviving
  defenders must still defuse, even if every attacker is dead.
- Detonation wins for attackers and kills survivors within 24 metres. A defuse
  completing exactly at the bomb deadline is too late. A plant completing at
  the round deadline is also too late.
- Six seconds between rounds for the result/halftime notice. All players then
  return with fresh equipment. No spawn shield. K/D and XP continue across rounds;
  the team score counts **round wins**, not individual kills.
- At three wins, the normal 15-second map vote chooses the next objective map.
  Ties rotate to the next tied map; no votes rotate automatically. The match
  restarts with round scores and K/D cleared while earned XP is retained.

## Joining, leaving and spectating

A joining player inherits their bot's current life, position, health, ammunition
and remaining grenade supply. An already-dead bot means spectating until the
next round. Disconnecting similarly hands the slot back to a bot without granting
another life or refilling supplies. A carried bomb stays in that same team slot;
an interrupted plant/defuse loses its progress.

**V** cycles living teammates while dead. If none survive, a fixed team-spawn
camera waits for the round result. There is no enemy-following or free-flight
spectator. E, X and V can all be rebound under Controls.

Joining humans alternate teams, as in TDM. If departures make human counts uneven,
existing players rebalance at the next round boundary instead of gaining a life
or switching teams during an active bomb play.

## Objective districts and bot tactics

The four map votes load objective variants: **Reactor**, **Customs**, **Vault** and
**Uplink**. Each has two sites, independent outer approaches, a central cut-through,
a defender rotation alley, protected spawns, two-story interiors, ramp collision
under visible stairs, and grenade-accessible roofs. District cover changes long
lane angles. Training and TDM retain their existing layouts.

Bots split defense across A/B, escort the attacking carrier, recover a dropped
bomb, plant, hold site angles and retake. One defender commits to defusing instead
of repeatedly handing responsibility to another bot while navigating around cover.
Bots retain their existing visibility, smoke, reaction and accuracy limits.

## Verification

Run with Godot 4.7.2:

```
godot --headless --path . -- --destroy-test --autonomous
python tests/run_multiplayer.py --godot /path/to/godot --destroy
python tests/run_multiplayer.py --godot /path/to/godot
```

The engine suite exercises timers, interruption, elimination, halftime, victory,
deadline precedence, lethal explosion, life/inventory conservation, ground recovery,
navigation from all spawn positions to both sites on all four maps, and autonomous
bot navigation/plant/defuse. Separate real ENet processes test remote defusing,
release cancellation, dead-slot joining, teammate spectating, mode rejection and
map voting/loading. The ordinary multiplayer suite checks TDM regressions.
Windows launcher CI also runs the rules and autonomous bot suite against the
exact packaged runtime before release. Competitive balance still needs human
playtesting: these are functional rules and layouts, not a finished ranked system.
