# Modu Android playback patch

Vendored from audioplayers_android 5.2.0 (MIT), retaining its LICENSE.
Package: https://pub.dev/packages/audioplayers_android/versions/5.2.0
Upstream repository: https://github.com/bluefireteam/audioplayers

`MediaPlayerWrapper.start()` explicitly calls `MediaPlayer.start()` after
applying the playback rate. The upstream implementation only sets playback
parameters. On the Honor Android 15 test device, audio continued while Android
reported the player as paused, leaving the media-button session unassigned.

Android's Java `start()` also performs `baseStart()` and `stayAwake(true)`;
the native playback-parameter setter does not replace that bookkeeping:
https://android.googlesource.com/platform/frameworks/base/+/master/media/java/android/media/MediaPlayer.java

This patch is intentionally limited to the Android backend. Verify real-device
audio playback state, lock-screen chapter transitions and global media keys
when upgrading or removing the override.

The native player also applies the existing `stayAwake` setting during lazy
creation. Previously only updateContext() applied it, so setting the context
before the first source (the normal Dart path) never configured a wake lock.
