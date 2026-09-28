# Modu Windows system TTS adapter

This Windows-only implementation uses the method-channel protocol and exported
registration function of `flutter_tts` at pinned revision
`ad4a10bb4977031a1e60fd8027fb62b932d635ce`. The dependency itself is not modified.
`windows/cmake/modu_system_tts.cmake` replaces only that target's source, retaining
its public header, C++/WinRT generation and linking setup. Mobile/macOS code is unchanged.

The 1.1.6+10050 Windows dump reported fail-fast `0xc0000409/7` with a WinRT
`0x80070002` exception and speech-plugin frames. Upstream activates speech/media
objects at registration, before Dart error handling is possible.

- Registration creates no speech synthesizer or media player.
- Await options, cached volume/pitch/rate, stop and shutdown do not activate TTS.
- Speech/voice selection initializes the synthesizer transactionally and can retry.
- WinRT initialization, voice enumeration and pre-playback synthesis failures
  switch to local SAPI (`ISpVoice`). The fallback stays selected for the session,
  retains volume/rate/pitch and tries to preserve the selected voice's language.
  No book text is sent to an online provider. If both backends fail, report a
  recoverable error rather than terminating the application.
- Once WinRT playback has started, a failure does not automatically replay the
  paragraph through SAPI (which would repeat already heard text).
- SAPI completion is polled on the platform thread and matched by stream number;
  cancelled streams cannot advance a later utterance. Pause is preserved when
  WinRT synthesis fails in the background. Stop/shutdown purge queued audio and
  remove the timer. SAPI XML pitch markup always escapes book text.
- Native errors return `windows_tts_unavailable`, never escape the method boundary.
- Asynchronous synthesis/media errors also resolve pending replies and notify Dart.
- A message-only window delivers callbacks on the Flutter platform thread.
- Weak callback ownership and generation checks ignore events after stop/restart.
- Shutdown revokes events, cancels synthesis, and drops replies without calling a
  potentially stopped Flutter messenger.

Validation on Windows must cover x64 and ARM64 compilation, launch with missing
or broken Windows voices, normal speech and voice enumeration, pause/resume,
stop during synthesis, immediate restart, and closing with synthesis in flight.
Do not remove the user's voice resources to simulate failure on their normal PC;
use an isolated Windows test environment.

Local regression commands:

```
python3 test/windows_tts_startup_test.py
python3 test/windows_tts_policy_test.py
flutter test --no-pub test/service/tts test/windows_shutdown_source_test.dart
```

The Python startup tests are source/build guards. The policy tests compile and
execute the production C++ retry/escaping/option helpers on the host; neither
substitutes for Windows native compilation and real playback tests. On Windows,
also verify fallback with WinRT initialization failure, a failed synthesis before
playback, pause during that failure, stop followed immediately by another passage,
voice selection and both backends unavailable.

SAPI references: [event interest](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms717856(v=vs.85)),
[pitch XML](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ee431815(v=vs.85)).
