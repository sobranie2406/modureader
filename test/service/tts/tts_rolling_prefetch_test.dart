import 'dart:async';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tts_reader_sequence_test.dart' show until;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('refills ahead while second paragraph plays, without repeating text',
      () async {
    final passages =
        List.generate(9, (i) => TtsSentence(text: '段落$i', cfi: '$i'));
    final gates = List.generate(passages.length, (_) => Completer<void>());
    final requested = <String>[];
    final played = <String>[];
    var cursor = 0;
    final tts = OnlineTts.forTesting(
      collect: (count) async => passages.skip(cursor).take(count).toList(),
      synthesize: (text) async {
        requested.add(text);
        return Uint8List.fromList([1]);
      },
      play: (segment) async {
        played.add(segment.sentence.text);
        await gates[int.parse(segment.sentence.cfi!)].future;
      },
    );
    addTearDown(() async {
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
      await tts.stop();
    });
    await tts.init(
        () async => passages[cursor].text,
        () async => ++cursor < passages.length ? passages[cursor].text : '',
        () async => '');
    final speaking = tts.speak();
    await until(() => played.length == 1 && requested.length == 4);
    gates[0].complete();
    await until(() => played.length == 2 && requested.length == 5);
    expect(cursor, 1);
    expect(requested.last, '段落4');
    for (var i = 1; i < passages.length; i++) {
      await until(() => played.length == i + 1);
      gates[i].complete();
    }
    await speaking;
    expect(played, passages.map((p) => p.text));
    expect(requested, passages.map((p) => p.text));
  });
}
