# Camera and presentation: 0.13.1

## What changed

The old local camera remained attached to the 60 Hz collision body even after weapon animations moved to render frames. A separate presentation camera now interpolates the body's previous/current physics positions. Rotation copies the logical aiming camera each render frame without filtering. Crouch eye height uses a short exponential transition. Respawns reset both samples; large teleports snap instead of sweeping. Network reconciliation moves the two samples together and applies its correction offset only to the presentation camera. Firing, grenades, parries, collision and server validation still use the logical camera/body.

Translation interpolation presents up to one physics tick behind simulation (16.7 ms at 60 Hz). It does not remove network latency or add a mouse smoothing filter. Remote avatars keep their existing interpolation/extrapolation path.

Round/game results now have a 0.3-second settling beat, followed by a readable viewer-relative announcement with captured team scores and a soft local backing. The total result window is 2.4 seconds. The hitmarker/HUD remain during the settling beat; the result cue plays once as the banner arrives. The halftime label now appears after round five. No full-screen black fade. The mandatory replay still lasts 6.75 seconds; ordinary replays still last 3.65 seconds. The host reserves 9.75 seconds for result + final + delivery margin. With no kill history, it sends a result-only message and reserves 2.7 seconds instead. Bomb/timeout endings can no longer silently skip the outcome. Map voting and the existing Destroy intermission follow these windows.

Replay scenery is cached while loading a mode and retained across rounds. A map change replaces the cache. Replay ghosts/history remain separate and reset as before. This moves static replay construction off the first-kill path; it does not eliminate every possible rendering hitch.

HUD changes include a compact score strip, neutral text/accent colors, and edge-only damage feedback. Standard armor uses matte surfaces, smaller shoulder details, a revised helmet and team identification panels; the weapon finish is less glossy. The walking pose has less exaggerated limb and torso motion. Existing cosmetics remain available. Medium quality now uses FXAA and one short-range shadow pass; Low disables both, and High keeps MSAA with longer-range split shadows. This is a visual upgrade to Medium, not a measured FPS increase on players' hardware.

## Verification

- Presentation suite: interpolation samples, immediate aiming, logical ray isolation, crouch easing, respawn/teleport reset, scenery reuse, quality presets, actual no-kill objective completion, server barrier and draw/reset handling.
- Optional `--motion-audit` samples a live 240 FPS-capped headless render loop. Locally measured 160 distinct rendered positions against 67 physics positions across the same interval.
- Existing armory, movement/parry/stair, settings, killcam and Destroy suites.
- Real host/client replay test through delayed/jittered/lossy UDP, including no-kill results after map rotation.
- Real host/client prediction test through delayed/jittered/lossy UDP.
- Rendered round-result and combat screenshots inspected with the Compatibility renderer. This container uses software rendering; physical mouse feel and target-PC frame times still need playtesting.
- Windows launcher CI includes the presentation suite against the packaged runtime.

```sh
GODOT --headless --path . -- --presentation-test
GODOT --headless --path . -- --presentation-test --motion-audit
python tests/run_multiplayer.py --godot GODOT --prediction --latency
python tests/run_multiplayer.py --godot GODOT --killcams --latency
```

Protocol 15: update host and friends together. Profile version and save location stay unchanged.

0.14.0 follow-up: Compatibility does not support FXAA. Balanced now uses 2x MSAA; see GAMEPLAY_FEEL.md. The post-replay Destroy intermission is now three seconds.
