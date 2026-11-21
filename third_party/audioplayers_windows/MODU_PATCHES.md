# Modu Windows playback patch

Vendored from audioplayers_windows 4.2.0 (MIT), retaining its LICENSE.
Package: https://pub.dev/packages/audioplayers_windows/versions/4.2.0
Upstream repository: https://github.com/bluefireteam/audioplayers

## Double-free of the global event handler at shutdown

`AudioplayersWindowsPlugin` kept the global event handler in a static
`std::unique_ptr` and then also passed the same object to
`EventChannel::SetStreamHandler`. The embedder's
`event_channel.h` states plainly that the channel "does not own the handler":
it converts the `unique_ptr` into a `shared_ptr` captured by the messenger
registration. Two owners therefore deleted one object while the engine shut
down:

- the messenger registration released it, then
- static destruction of `globalEvents` released it again.

Observed on 2026-11-21 12:08:28 (local): Windows Event Log recorded
`APPCRASH` in `audioplayers_windows_plugin.dll`, exception `0xc0000005`,
fault offset `0x40069`. Symbolising that offset against the build's PDB gives
`std::default_delete<EventStreamHandler<flutter::EncodableValue>>::operator()`
at `<memory>:3338` — i.e. the `delete` in the second destructor. The crash
happened one second **after** the app had already written `session_closed` to
its crash journal, so it was a pure teardown fault, not a playback fault.

The patch keeps a non-owning raw pointer for the plugin's own event reporting
and lets the messenger registration be the only owner:

    auto globalEventHandler = std::make_unique<EventStreamHandler<>>();
    globalEvents = globalEventHandler.get();          // observer only
    _globalEventChannel->SetStreamHandler(
        std::unique_ptr<StreamHandler<EncodableValue>>{
            globalEventHandler.release()});           // single owner

`globalEvents` is dereferenced only while the engine is alive, so the observer
cannot outlive its object in practice; it is nulled by nothing, so do not add a
`delete`/owning pointer back.

Verify on upgrade: start the app, play narration or an audiobook, then close the
window — the process must exit without an `Application Error` event for
`modu.exe`.
