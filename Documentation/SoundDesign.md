# Cosmo sound and haptics

September 2026 · shared by macOS and iOS

The sound of finishing something should be immediate, recognizable, and small.
The interface now uses nine precisely rendered gestures from one rounded electronic
voice. Natural foley, instrumental notes per entity, randomized variants, decorative
arrival sounds, and the three-layer task-completion sequence have been retired.

## The palette

| Cue | Duration | Peak | Used for |
| --- | ---: | ---: | --- |
| Complete | 272 ms | −15 dBFS | Task and habit completion |
| Milestone | 440 ms | −16 dBFS | Daily goal, all tasks done, inbox clear |
| Focus | 328 ms | −19 dBFS | Finishing a focus session |
| Confirm | 156 ms | −19 dBFS | A successful creation or capture |
| Open | 132 ms | −23 dBFS | Composer, pickup, focus start/resume |
| Close | 120 ms | −24 dBFS | Dismissal, focus pause |
| Place | 100 ms | −22 dBFS | Filing, dropping, rescheduling |
| Remove | 150 ms | −23 dBFS | Deleting |
| Undo | 188 ms | −22 dBFS | Restoring an action |

These are source-file peaks. The default interface volume is 70%, below the
device's own volume. Every asset is 48 kHz, mono, 16-bit LPCM CAF. Mono keeps the
identity stable on an iPhone speaker and avoids stereo tricks in headphones.
Half-cosine envelopes, a high-pass DC filter, and tapered tails prevent edge clicks.
There is no runtime pitch or gain variation and no reverb bed. Completion's two
transients are rendered into one file, 56 ms apart, so their timing cannot drift.

## Interaction rules

- **Essentials** is the default: completing work, finishing focus, and milestones.
- **All actions** adds quiet functional cues. Navigation remains primarily tactile.
- **Off** stops current playback and invalidates pending requests. Haptics have an
  independent toggle. Existing `minimal`, `full`, `off`, and legacy disabled values migrate.
- Preview buttons are explicit. Moving the volume slider or changing a profile
  does not unexpectedly play a sound.
- A task's sound fires when its checkmark appears. iPhone adds one restrained rigid
  impact at that beat. The Mac uses one native trackpad response. Reduce Motion
  retains the same sound identity with the shorter existing visual timing.
- Opening a composer is an opening cue; confirmation belongs to a successful save.
- Undoing completion is silent. The all-tasks-done milestone is limited to once per
  local calendar day. Simultaneous goal surfaces are coalesced by the playback policy.

## Playback and platform behavior

`Core/SoundEngine.swift` and the iOS `Design/SoundEngine.swift` are identical.
Prepared `AVAudioPlayer` instances are confined to a serial audio queue. File reads,
decode, and audio-session setup never block the main actor. A synchronized generation
gate rejects requests invalidated while preparation was in progress. Requests older
than 180 ms are dropped; they never arrive as a disconnected sound after an action.
The mixer admits at most three short voices, never restarts a currently playing cue,
rate-limits repeated actions, and protects reward tails from lower-priority sounds.
There is no continuously running silent audio engine or idle polling task.

iOS uses the ambient session category, respects silent mode and other audio, stops on
deactivation/interruption, and rebuilds players after route changes or media-service
resets. Unmuted swipe media suppresses interface cues. Focus notifications install the
same milestone asset under a versioned filename using atomic replacement, including on
upgrades. Notification alerts remain under the system's notification sound settings;
the interface sound profile does not change notification permissions.

macOS stops interface sounds when inactive or voice capture starts. The common native
video component observes playback, volume, and mute changes to balance suppression.
Trackpad haptics use `NSHapticFeedbackManager`; `CHHapticEngine` hardware support is not
a test for a Mac trackpad. All app-authored haptics now pass through the preference gate.

## Maintenance and verification

Generate the bank with `python3 scripts/generate_interface_sounds.py --out Resources/Sounds`.
Add `--proof <directory>` for individual WAV previews, a listening sequence, and a manifest.
The iOS copy of the generator is `Tools/generate_sounds.py`. Always ship the same nine
files in both apps. The shared settings component must remain identical too.

Run `python3 scripts/verify_interface_sounds.py --ios /path/to/CosmoOS-iOS` for asset
format, duration, headroom, DC, endpoint, parity, and Swift 6 policy/cancellation checks.
Build both apps with Xcode. Test Off during playback, media suppression, repeated task
completion, background/foreground, and settings at accessibility text sizes.

Simulator review cannot validate a physical Taptic Engine, a Mac trackpad's force,
Bluetooth latency, or the perceived balance of built-in speakers. Final listening on
both devices remains a hardware check, with silent mode and background music enabled.

Design references: [Apple: Playing audio](https://developer.apple.com/design/human-interface-guidelines/playing-audio),
[Apple: Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics).

### iOS interruption recovery

The audio session is explicitly reactivated before preparing playback. Returning
to the app, requesting a Settings preview, reconnecting an output, and resetting
media services clear a stale interruption; none replays an old cue. iOS does not
guarantee that an interruption-began notification has a corresponding end. Off,
media suppression, and volume still gate all recovery paths.

Run the device lifecycle regression on an already booted simulator:

```sh
python3 scripts/verify_ios_sound_lifecycle.py --device SIMULATOR_UUID
```

The regression uses the production engine, reproduces the missing-ended case,
and checks that recovery preserves Off and media suppression.
