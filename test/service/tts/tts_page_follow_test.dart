import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/tts/base_tts.dart';
import 'package:modu_reader/service/tts/online_tts.dart';
import 'package:modu_reader/service/tts/models/tts_sentence.dart';
import 'tts_rate_recovery_test.dart' show NativePlayer;
import 'tts_reader_sequence_test.dart' show until;

class ProgressPlayer extends NativePlayer {
  final positions = StreamController<Duration>.broadcast(sync: true);
  final durations = StreamController<Duration>.broadcast(sync: true);
  final started = Completer<void>();
  @override
  Stream<Duration> get onPositionChanged => positions.stream;
  @override
  Stream<Duration> get onDurationChanged => durations.stream;
  @override
  Future<void> play(Source source,
      {double? volume,
      double? balance,
      AudioContext? ctx,
      Duration? position,
      PlayerMode? mode}) async {
    started.complete();
  }

  @override
  Future<void> dispose() async {
    await positions.close();
    await durations.close();
    await super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('audio duration controls page following, not cached text or wall time',
      () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final player = ProgressPlayer();
    const sentence =
        TtsSentence(text: '一行在前页，其余内容在后页。', cfi: 'epubcfi(/6/2!/4/2)');
    final fractions = <double>[];
    final tts = OnlineTts.forTesting(
        createPlayer: () => player,
        collect: (_) async => [sentence],
        synthesize: (_) async => Uint8List.fromList([1]),
        followProgress: (value, fraction) async {
          expect(value, sentence);
          fractions.add(fraction);
        });
    await tts.init(() async => sentence.text, () async => '', () async => '');
    final playing = tts.speak();
    await player.started.future;
    player.positions.add(const Duration(seconds: 1));
    expect(fractions, isEmpty); // Unknown duration cannot justify a page jump.
    player.durations.add(const Duration(seconds: 10));
    player.positions.add(const Duration(seconds: 2));
    await until(() => fractions.length == 1);
    expect(fractions.single, .2);
    tts.updateTtsState(TtsStateEnum.paused);
    player.positions.add(const Duration(seconds: 6));
    expect(fractions, [.2]);
    tts.updateTtsState(TtsStateEnum.playing);
    player.positions.add(const Duration(seconds: 7));
    await until(() => fractions.length == 2);
    expect(fractions.last, .7);
    player.completed.add(null);
    await playing;
    player.positions.add(const Duration(seconds: 9));
    expect(fractions, [.2, .7]);
    await tts.stop();
  });
}
