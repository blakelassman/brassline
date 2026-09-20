# Killcams (0.11.0)

## Player behavior

- Death replays show up to three seconds leading to the kill, from the attacker's first-person view, then hold briefly on the hit.
- Press the Jump binding to skip (Space / scroll down by default). Holding Jump through death does not skip automatically. The prompt uses your configured binding.
- In offline combat and online TDM, skipping or finishing respawns you immediately, without a shield. You stay dead while watching. The server has a five-second fallback if a client never finishes.
- In Destroy and Diffuse, skipping/finishing returns to teammate spectating. You remain eliminated until the next round.
- Settings → Death killcams disables ordinary death replays only.
- Online TDM matches and individual Destroy rounds end with the last recorded kill from that match/round. Everyone watches the same first-person final replay; it cannot be skipped or disabled. The last 0.65 seconds before the hit play at 0.25 speed, followed by a brief hit hold.
- Finals have a 6.5-second server transition window. Map voting gets its full 15 seconds afterward; Destroy retains its six-second result interval afterward. No recorded kill means no fabricated final replay. A bomb/timeout result uses the last actual kill if one exists.

## Implementation

The host (or offline game) records a bounded 20 Hz history: actor positions, aim, life IDs, eye height, FOV, health, weapon, crouch/reload state, cosmetics, actual shot rays, smoke positions and grenades. Clips use up to three seconds of the killer's current life. The terminal pose is captured before any deferred bot respawn, preserving the victim and collateral death poses.

Playback reconstructs this history with interpolation in a separate World3D and render-only ghosts. It is a reconstruction, not video: first-person recoil/reloads and grenade/smoke effects are approximations. Remote victims use the lethal shot's validated lag-compensation offset for spatial playback. This does not change hit validation or guarantee pixel-identical client footage.

The recorded scope FOV and weapon finishes are used. A separate weapon viewport prevents world clipping. Live world/viewmodel rendering pauses while watching; server physics, clocks and other players continue normally. Slow motion affects only the replay clock, never Engine.time_scale. Replay hit/shot audio respects mixer volumes; playback does not award kills or XP.

Compressed clips travel on a reliable ENet channel, capped at 128 KiB compressed / 512 KiB decoded. The source ring is capped at 76 frames / 512 shot events. Clip IDs, map generation and viewer life reject duplicate/stale delivery. Server checks validate skip requests against the current dead life, and finals block combat/early votes until their server deadline. Scenery is cached for the current map; ghosts and history are cleared on round/session transitions.

Network protocol is **12**. Update the server and all players together. Existing profiles remain compatible; the new death-killcam setting defaults on.

## Verification

```sh
GODOT --headless --path . -- --killcam-test
python tests/run_multiplayer.py --godot GODOT --killcams
python tests/run_multiplayer.py --godot GODOT --killcams --latency
```

The rules suite exercises independent worlds, held-jump/skip behavior, respawn vulnerability, life boundaries, compression, scoped camera poses, collateral falls, lag-compensated poses, slow-motion isolation and Destroy transition barriers. The real ENet host/client suite verifies clip delivery, skip/respawn, stale skip rejection, mandatory finals, blocked early voting and map cleanup. The latency variant adds 40 ms each way, jitter and packet loss.

Windows CI imports the exact launcher payload and runs the killcam rules suite before publication. Visual fixtures: `--capture-killcam` and `--capture-final-scope` (with BRASSLINE_CAPTURE_PATH set).
