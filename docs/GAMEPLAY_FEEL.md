# Gameplay feel: 0.14.0

This is a concrete responsiveness and animation pass, not a claim of production readiness.

## Motion

The previous rig used `clock * (9.5 + stride * 2)` as the walking phase. Any speed change re-phased the entire animation, with the discontinuity increasing as the match aged. Rigs now integrate distance over time, ease stride weight, and blend reload stance. Rewinds reset the integration state. Live animation clocks advance on render frames.

`actor_presentation.gd` interpolates the visual transform for local bots, training targets, and host-side humans. Collision bodies, aim, damage and network records stay in simulation space. Bot weapons and labels follow the visual pose. Client network avatars retain their existing interpolation rather than receiving a second layer. Respawns clear old poses. As with the local camera, this can present translation up to one 60 Hz tick behind simulation.

Bots turn gradually and wait until facing within their firing cone before shooting. Navigation can skip grid corners only if a full standing-capsule sweep is clear and the waypoint is on the same elevation; ramps retain their elevation waypoints. Wall-stall recovery waits 250 ms before changing strafe direction and replanning, instead of flipping/rebuilding every physics tick. Existing reaction delays, damage and spawn behavior remain.

Teammate visibility queries for remote human models are capped at 10 Hz instead of running on every rendered frame. Occluded tags can consequently take up to 100 ms to disappear. Spectator position and orientation ease on the same teammate, snap when switching teammates, and recheck obstruction after easing.

## Weapon handling and feedback

- Visual equipment changes take a 60 ms holster beat followed by a 140 ms draw. The logical weapon and authoritative equip cooldown still control firing. Rapid cycling resolves to the latest selection.
- Zoom follows a 120 ms smoothstep with continuous FOV when reversed. FOV-dependent sensitivity still uses the actual FOV; aiming inputs are not filtered.
- Reload, bolt, swing, throw and parry animation timers interpolate/extrapolate for presentation only. They never spend ammunition, change cooldowns or create hits.
- A click while equipping a grenade queues the chosen throw/toss for up to 200 ms. It executes once when ready; changing equipment, respawning or opening the menu clears it.
- Reload tilt and weapon scale are reduced to preserve more view of the arena.
- Cosmetic particles and falling bodies update on render frames. Cosmetic shader materials receive a separate fading shader, preserving their finish and leaving shared inventory materials untouched.
- The post-final-replay Destroy intermission is three seconds instead of six. Result timing, replay duration and no-kill outcomes remain as in 0.13.1.

## Rendering

The earlier FXAA setting was unsupported by the Compatibility renderer. Balanced now uses 2x MSAA, High keeps 2x MSAA with longer-range split shadows, and Low disables MSAA/shadows. Replay quality follows the live viewport. These quality settings have hardware-dependent costs; this is not an FPS-gain claim.

The new saved 3D render-scale slider ranges from 50% to 100%. It multiplies the selected fullscreen render resolution (or window rendering size), leaving UI and first-person weapon rendering at their existing resolution. Existing saves default to 100%.

## Verification

`--feel-test` checks match-age-independent animation, continuous speed changes, reload blending, replay rewind, eased/reversible zoom, staged and rapid weapon switching, exactly-once grenade buffering, pause cancellation, shader-safe death fades, collision-preserving actor interpolation, respawn reset, renderer settings and render-scale persistence. It also runs against the staged Windows launcher payload.

Other gates: presentation, armory, combat, stairs/parry/movement, cosmetics, killcams, autonomous Destroy rounds, and real host/client prediction + replay tests under delayed/jittered/lossy UDP. Compatibility-rendered combat/reload captures and shader fading are checked separately from headless tests.

Physical mouse feel, target-machine frame pacing, wide-area internet conditions, longer soak testing, broader hardware coverage and production art/audio remain necessary. This update does not make those claims.

Network protocol remains 15; profile format and save location remain unchanged. Update the host and players through the launcher for consistent behavior.
