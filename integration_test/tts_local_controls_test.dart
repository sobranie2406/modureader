import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Run on macOS: flutter test integration_test/tts_local_controls_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native pitch and speed preserve pause, position and completion',
      (tester) async {
    final player = AudioPlayer();
    addTearDown(player.dispose);
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setVolume(0);
    Future<void> pitch(double value) =>
        const MethodChannel('xyz.luan/audioplayers').invokeMethod<void>(
            'setPitch', {'playerId': player.playerId, 'pitch': value});
    await pitch(1);
    // Four seconds of silence: exercise the native path without making sound.
    const sampleRate = 24000;
    const size = sampleRate * 4 * 2;
    final wav = ByteData(44 + size);
    void tag(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        wav.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    wav.setUint32(4, 36 + size, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    wav.setUint32(16, 16, Endian.little);
    wav.setUint16(20, 1, Endian.little);
    wav.setUint16(22, 1, Endian.little);
    wav.setUint32(24, sampleRate, Endian.little);
    wav.setUint32(28, sampleRate * 2, Endian.little);
    wav.setUint16(32, 2, Endian.little);
    wav.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    wav.setUint32(40, size, Endian.little);
    final source = BytesSource(wav.buffer.asUint8List(), mimeType: 'audio/wav');
    var completed = 0;
    final subscription = player.onPlayerComplete.listen((_) => completed++);
    addTearDown(subscription.cancel);
    await player.setPlaybackRate(1);
    await player.play(source);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final before = (await player.getCurrentPosition())!.inMilliseconds;
    expect(before, greaterThan(50));
    await pitch(0.8);
    await player.setPlaybackRate(1.7);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect((await player.getCurrentPosition())!.inMilliseconds,
        greaterThan(before));
    await player.pause();
    final paused = (await player.getCurrentPosition())!.inMilliseconds;
    await pitch(1.3);
    await player.setPlaybackRate(4);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect((await player.getCurrentPosition())!.inMilliseconds,
        closeTo(paused, 30));
    expect(player.state, PlayerState.paused);
    expect(completed, 0);
    await player.resume();
    for (var i = 0; i < 60 && completed == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(completed, 1);
    await player.play(source);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await player.stop();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(completed, 1, reason: 'stop must not complete/skip a TTS passage');
    expect((await player.getCurrentPosition())!.inMilliseconds, 0);
  });
}
