import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/widgets/reading_page/tts_fab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Handler extends Fake implements TtsHandler {
  _Handler(TtsStateEnum state) : ttsStateNotifier = ValueNotifier(state);
  @override
  final ValueNotifier<TtsStateEnum> ttsStateNotifier;
  int previous = 0, next = 0;
  @override
  Future<void> playPrevious() async {
    previous++;
  }

  @override
  Future<void> playNext() async {
    next++;
  }

  @override
  Future<void> stop() async {
    ttsStateNotifier.value = TtsStateEnum.stopped;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  for (final state in [TtsStateEnum.playing, TtsStateEnum.paused]) {
    testWidgets(
        'expanded controls stay available for repeated navigation: $state',
        (tester) async {
      final handler = _Handler(state);
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: TtsFab(handler: handler))));
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byIcon(EvaIcons.chevron_right));
        handler.ttsStateNotifier.value = TtsStateEnum.paused;
        await tester.pumpAndSettle();
        handler.ttsStateNotifier.value = state;
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(EvaIcons.chevron_left));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.close), findsOneWidget);
      }
      expect(handler.next, 3);
      expect(handler.previous, 3);
      await tester.tap(find.byIcon(EvaIcons.stop_circle_outline));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
