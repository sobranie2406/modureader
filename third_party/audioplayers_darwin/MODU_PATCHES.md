# Modu macOS TTS playback patch

Vendored from audioplayers_darwin 6.2.0 (MIT), retaining its LICENSE.
Source: https://pub.dev/packages/audioplayers_darwin/versions/6.2.0
Upstream: https://github.com/bluefireteam/audioplayers

Only the macOS implementation is changed. The existing `setPitch` channel
selects a local-file AVAudioEngine / AVAudioUnitTimePitch player for OpenAI
(including compatible services) and MiMo TTS. Rate and pitch stay independent;
setting either while paused does not resume playback. The normal AVPlayer path
and the iOS implementation are unchanged. The engine is released with the player.

TTS downloads/cache remain in Dart. No new service, audio dependency or model is
bundled. Errors retain the existing audio event channel. Source timestamps,
seeking, pause/resume, completion and stop semantics are preserved.

Validation on macOS:
- `flutter test integration_test/tts_local_controls_test.dart -d macos`
- Compile `macos/Classes/PitchAudioPlayer.swift` together with
  `test/native/tts_pitch_macos.swift` using `swiftc`, then run it outside a sandbox
  that blocks Apple's AudioComponent services. Measures rendered pitch and
  duration at 0.1–4x rate and 0.5–2x pitch.

Recheck audio routing, lock-screen controls and sentence transitions when
upgrading this fork. iOS, Windows, Linux and HarmonyOS still use the existing
provider pitch controls; supported OpenAI models now receive the numeric pitch
multiplier rather than the same vague instruction for every slider value.
