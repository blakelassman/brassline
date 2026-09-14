# Audio update

All 37 active sound cues now use a rebuilt library of 52 prebuilt Ogg clips.
Gunfire uses actual CC0 recordings: four AK-style rifle shots, two pistol shots,
and two bolt-action rifle shots. Footsteps use four different takes per surface.
Mechanical foley and impacts use edited/layered CC0 recordings; headshots combine
a short dry crack, a dense impact and a brief crunchy tail. The continuous air/fan
background and remaining designed effects are original. Full source credits and
per-file provenance ship under `assets/audio`.

## What changes in play

- Distant shots are louder, retain more high-frequency detail and stay audible
  beyond the old 48-metre cutoff. Gunfire uses a 180-metre fade range with an
  18-metre reference distance, and a 7 dB remote gain adjustment. Directional
  panning and distance falloff remain. Explosions are positional on the host too.
- Host, client and bot gunshots use the same remote mix. The client still hears
  its own shot immediately and ignores the replicated copy.
- Weapons, movement/foley and hit/reward feedback have reserved voice groups.
  Footsteps no longer steal gunshot tails or headshot confirmations. The mixer
  reserves voices immediately for multiple shots in the same physics tick.
- A faint continuous filtered-air/fan drone fills silence. Map ambience remains
  quieter underneath it. Both loop without a repeated fade-to-silence effect.
- Settings now separate master, gunfire/explosions, footsteps/equipment,
  hit confirmations/rewards and background air/drone. Background defaults to
  35%; zero fully mutes it. Existing master volume and progression are retained.
- A modest weapon-bus compressor controls crowded firefights; a master limiter
  caps output peaks at -1 dBFS. Existing gameplay RNG and weapon rules are unchanged.

The mixer has fixed pools of 28 local and 52 positional voices; it does not
allocate new audio nodes for every shot. Variant selection has its own RNG and
avoids consecutive repeats. Clips are loaded once and shared between voices.
There are no real-time sound synthesis or external audio-service dependencies.

## Verification

`python tests/check_audio_assets.py` decodes all 52 clips with FFmpeg and checks
peak limits, DC offset, leading silence and ambience loop seams. Gunfire attacks
start within 1 ms, headshot impacts within 4 ms. No shipped clip reaches 0 dBFS.

`Godot --headless --path . -- --audio-test` exercises the actual mixer, category
isolation, same-tick allocation, remote-shot RPC behavior, profile migration,
per-bus mute/save and pause/resume. Settings and combat regression suites cover
existing preferences and weapon/reload behavior. Windows release CI runs the
mixer test before publishing the new launcher channel.

Audio character still benefits from listening on the player's actual headset;
these checks verify decoding, timing, routing and levels, not a universal sound
preference. No live friend-network listening session was available during build.

## Rebuild the clips

Download the two CC0 archives linked in `assets/audio/CREDITS.txt` and extract
into a working directory with `Prepared SFX Library/` and `impact/Audio/`.
Run `python tools/build_audio.py THAT_DIRECTORY` with numpy, scipy and FFmpeg.
The committed Oggs and catalog are the runtime deliverables. The old placeholder
WAV generators have been retired; rebuilding no longer depends on their order.
