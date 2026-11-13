import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/page/book_player/epub_player.dart';
import 'package:modu_reader/widgets/reading_page/reader_popup.dart';
import 'package:modu_reader/widgets/reading_page/reader_settings_scroll_view.dart';
import 'package:modu_reader/widgets/reading_page/tts_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({'ttsService': 'xiaomi'});
    await Prefs().initPrefs();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.audio_session'), (_) async => null);
  });

  for (final spec in [
    (const Size(390, 844), 1.0, 80),
    (const Size(390, 844), 1.0, 40),
    (const Size(844, 390), 1.0, 80),
    (const Size(844, 390), 1.0, 40),
    (const Size(1200, 800), 1.0, 80),
    (const Size(1200, 800), 1.0, 40),
    (const Size(390, 844), 1.5, 80),
    (const Size(390, 844), 1.5, 40),
  ]) {
    testWidgets('narration controls stay above the toolbar at $spec',
        (tester) async {
      Prefs().readerPopupMaxHeightPercent = spec.$3;
      tester.view.physicalSize = spec.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const footer = ValueKey('narration-test-toolbar');
      await tester.pumpWidget(MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(spec.$2)),
              child: child!),
          home: Scaffold(
              body: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                      width: 600,
                      child: ReaderQuickStylePanel(
                          content: TtsWidget(
                              epubPlayerKey: GlobalKey<EpubPlayerState>()),
                          toolbar:
                              const SizedBox(key: footer, height: 48)))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final scroll = tester.widget<SingleChildScrollView>(find.descendant(
          of: find.byType(ReaderSettingsScrollView),
          matching: find.byWidgetPredicate((w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.vertical)));
      scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final engine = find.text('Xiaomi MiMo');
      expect(engine, findsOneWidget);
      expect(tester.getRect(engine).bottom,
          lessThanOrEqualTo(tester.getRect(find.byKey(footer)).top));
      expect(engine.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
