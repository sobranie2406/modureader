import 'dart:async';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tts_rate_recovery_test.dart' show NativePlayer;
import 'tts_reader_sequence_test.dart' show until;

class PassagePlayer extends NativePlayer {
  int plays = 0;
  int resumes = 0;
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async => resumes++;
  @override
  Future<void> play(Source source,
          {double? volume,
          double? balance,
          AudioContext? ctx,
          Duration? position,
          PlayerMode? mode}) async =>
      plays++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('first passage has request priority and playback keeps exact group CFIs',
      () async {
    const passages = [
      TtsSentence(text: '首段第一句。第二句。', cfi: 'group-1'),
      TtsSentence(text: '次段第一句。第二句。', cfi: 'group-2'),
      TtsSentence(text: '最后一段。', cfi: 'group-3'),
    ];
    final first = Completer<Uint8List>();
    final later = Completer<Uint8List>();
    final requests = <String>[];
    final played = <String?>[];
    var cursor = 0;
    final tts = OnlineTts.forTesting(
      collect: (count) async => passages.skip(cursor).take(count).toList(),
      synthesize: (text) {
        requests.add(text);
        return text == passages.first.text ? first.future : later.future;
      },
      play: (segment) async => played.add(segment.sentence.cfi),
    );
    addTearDown(tts.stop);
    await tts.init(
        () async => passages[cursor].text,
        () async => ++cursor < passages.length ? passages[cursor].text : '',
        () async => '');
    final speaking = tts.speak();
    await until(() => requests.isNotEmpty);
    expect(requests, [passages.first.text]);
    first.complete(Uint8List.fromList([1]));
    await until(() => played.isNotEmpty && requests.length == 3 && cursor == 1);
    expect(played, ['group-1']);
    expect(cursor, 1);
    later.complete(Uint8List.fromList([2]));
    await speaking;
    expect(played, ['group-1', 'group-2', 'group-3']);
    expect(requests, passages.map((p) => p.text).toList());
  });

  for (final lateError in [false, true]) {
    test(
        'next cancels waiting for a slow passage; late error=$lateError is inert',
        () async {
      final stale = Completer<Uint8List>();
      final spoken = <String>[];
      final requests = <String>[];
      final passages = ['旧段。慢请求。', '新段。继续朗读。'];
      var cursor = 0;
      final tts = OnlineTts.forTesting(
        collect: (_) async => cursor < passages.length
            ? [TtsSentence(text: passages[cursor])]
            : [],
        synthesize: (text) async {
          requests.add(text);
          return text == passages.first
              ? stale.future
              : Uint8List.fromList([2]);
        },
        play: (segment) async => spoken.add(segment.sentence.text),
      );
      addTearDown(tts.stop);
      await tts.init(
          () async => passages[cursor],
          () async => ++cursor < passages.length ? passages[cursor] : '',
          () async => passages[--cursor]);
      final original = tts.speak();
      await until(() => requests.isNotEmpty);
      await tts.next().timeout(const Duration(seconds: 2));
      await original;
      expect(spoken, [passages.last]);
      if (lateError) {
        stale.completeError(StateError('late old request failure'));
      } else {
        stale.complete(Uint8List.fromList([1]));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(spoken, [passages.last]);
      expect(cursor, 2);
      expect(tts.playbackError, isNull);
    });
  }

  test('pause/resume keeps the active passage; paused prev/next select groups',
      () async {
    final players = <PassagePlayer>[];
    final passages = ['第一段。一。二。', '第二段。三。四。', '第三段。五。六。'];
    var cursor = 0;
    final tts = OnlineTts.forTesting(
      createPlayer: () {
        final player = PassagePlayer();
        players.add(player);
        return player;
      },
      collect: (count) async => passages
          .skip(cursor)
          .take(count)
          .map((p) => TtsSentence(text: p))
          .toList(),
      synthesize: (_) async => Uint8List.fromList([1]),
    );
    addTearDown(tts.stop);
    await tts.init(
        () async => passages[cursor],
        () async => ++cursor < passages.length ? passages[cursor] : '',
        () async => passages[--cursor]);
    final speaking = tts.speak();
    await until(() => players.isNotEmpty && players.first.plays == 1);
    await tts.pause();
    await tts.resume();
    expect(players.first.resumes, 1);
    expect(players.first.plays, 1);
    expect(cursor, 0);
    await tts.pause();
    await tts.next();
    await speaking;
    expect(cursor, 1);
    await tts.next();
    expect(cursor, 2);
    await tts.prev();
    expect(cursor, 1);
    expect(tts.ttsStateNotifier.value, TtsStateEnum.paused);
    final resumed = tts.resume();
    await until(() => players.length == 2 && players.last.plays == 1);
    expect(cursor, 1);
    players.last.completed.add(null);
    await until(() => players.last.plays == 2);
    expect(cursor, 2);
    players.last.completed.add(null);
    await resumed;
    expect(cursor, 3);
  });
}
