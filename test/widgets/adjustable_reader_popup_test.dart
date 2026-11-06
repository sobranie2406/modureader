import 'package:anx_reader/widgets/context_menu/translation_menu.dart';
import 'package:anx_reader/widgets/dictionary/unified_query.dart';
import 'package:anx_reader/models/unified_query.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_chat_display_mode.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/ai.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:anx_reader/widgets/reading_page/adjustable_reader_popup.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget app(Widget child) => ProviderScope(
        child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        ...GlobalMaterialLocalizations.delegates
      ],
      home: Scaffold(body: child),
    ));
final frame = find.byKey(const ValueKey('adjustable-reader-popup-frame'));
Finder handle(String edge) => find.byKey(ValueKey('reader-popup-$edge'));

Future<void> open(WidgetTester tester,
    {bool allow = true, Widget? body}) async {
  await tester.pumpWidget(app(Builder(
      builder: (context) => TextButton(
            onPressed: () => showReaderPopup(context,
                allowWindowAdjustment: allow,
                enableDrag: false,
                builder: (_) => body ?? const TextField()),
            child: const Text('Open'),
          ))));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

// Move past touch slop before measuring the actual pointer delta.
Future<void> drag(WidgetTester tester, String edge, Offset delta) async {
  final gesture = await tester.startGesture(tester.getCenter(handle(edge)));
  await gesture.moveBy(delta / 4);
  await tester.pump();
  await gesture.moveBy(delta);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  testWidgets(
      'anchored query keeps the reader clear, points to selection and dismisses outside',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final anchor in [
      const Rect.fromLTWH(400, 100, 80, 30),
      const Rect.fromLTWH(400, 760, 80, 30)
    ]) {
      await tester.pumpWidget(app(Builder(
          builder: (context) => TextButton(
              onPressed: () => showReaderPopup(context,
                  selectionRect: anchor,
                  barrierColor: Colors.transparent,
                  initialHeightFraction: .45,
                  builder: (_) => const TextField()),
              child: const Text('Open anchored')))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open anchored'));
      await tester.pumpAndSettle();
      final rect = tester.getRect(frame);
      expect(rect.overlaps(anchor), false);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(1000));
      expect(find.byKey(const ValueKey('reader-popup-selection-arrow')),
          findsOneWidget);
      final route =
          ModalRoute.of(tester.element(find.byType(TextField)))! as PopupRoute;
      expect(route.barrierColor, Colors.transparent);
      await tester.enterText(find.byType(TextField), 'Draft');
      await drag(tester, 'move', const Offset(30, 10));
      expect(find.text('Draft'), findsOneWidget);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(frame, findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('default off, only explicit popup mode enables the feature',
      (tester) async {
    expect(Prefs().adjustableReaderPopups, false);
    Prefs().aiChatDisplayMode = AiChatDisplayMode.popup;
    await open(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(TextField))).pop();
    await tester.pumpAndSettle();
    Prefs().adjustableReaderPopups = true;
    for (final mode in AiChatDisplayMode.values) {
      Prefs().aiChatDisplayMode = mode;
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(AdjustableReaderPopup),
          mode == AiChatDisplayMode.popup ? findsOneWidget : findsNothing);
      Navigator.of(tester.element(find.byType(TextField))).pop();
      await tester.pumpAndSettle();
    }
    Prefs().aiChatDisplayMode = AiChatDisplayMode.popup;
    await open(tester, allow: false);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AdjustableReaderPopup), findsNothing);
  });

  testWidgets(
      'move, all seven resize handles, draft preservation and reset on reopen',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Prefs().aiChatDisplayMode = AiChatDisplayMode.popup;
    Prefs().adjustableReaderPopups = true;
    await open(tester);
    final initial = tester.getRect(frame);
    await tester.enterText(find.byType(TextField), 'Keep this draft');
    await drag(tester, 'move', const Offset(-60, -60));
    expect(tester.getRect(frame).size, initial.size);
    expect(tester.getRect(frame).topLeft, isNot(initial.topLeft));
    for (final change in <String, Offset>{
      'left': const Offset(30, 0),
      'right': const Offset(-30, 0),
      'bottom': const Offset(0, -30),
      'top-left': const Offset(30, 30),
      'top-right': const Offset(-30, 30),
      'bottom-left': const Offset(30, -30),
      'bottom-right': const Offset(-30, -30),
    }.entries) {
      final before = tester.getRect(frame);
      await drag(tester, change.key, change.value);
      expect(tester.getRect(frame).size, isNot(before.size),
          reason: change.key);
      expect(find.text('Keep this draft'), findsOneWidget);
    }
    await tester.tap(handle('close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getRect(frame), initial);
    expect(find.text('Keep this draft'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('safe bounds, keyboard, rotation and content scrolling',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    Prefs().aiChatDisplayMode = AiChatDisplayMode.popup;
    Prefs().adjustableReaderPopups = true;
    await open(tester,
        body: ListView(
            children: List.generate(
                60, (i) => SizedBox(height: 48, child: Text('Row $i')))));
    final initial = tester.getRect(frame);
    await tester.drag(find.text('Row 2'), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(tester.getRect(frame), initial);
    await drag(tester, 'move', const Offset(1000, -1000));
    var rect = tester.getRect(frame);
    expect(rect.left, greaterThanOrEqualTo(8));
    expect(rect.top, greaterThanOrEqualTo(8));
    expect(rect.right, lessThanOrEqualTo(382));
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    rect = tester.getRect(frame);
    expect(rect.bottom, lessThanOrEqualTo(516));
    tester.view.viewInsets = const FakeViewPadding();
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    rect = tester.getRect(frame);
    expect(rect.bottom, lessThanOrEqualTo(382));
    await drag(tester, 'bottom-right', const Offset(-2000, -2000));
    expect(tester.getSize(frame).width, greaterThanOrEqualTo(320));
    expect(tester.getSize(frame).height, greaterThanOrEqualTo(240));
    expect(tester.takeException(), isNull);
  });

  testWidgets('switch visible only when popup is selected, starts off',
      (tester) async {
    final switchFinder = find.byKey(const ValueKey('adjustable-reader-popups'));
    for (final mode in AiChatDisplayMode.values) {
      Prefs().aiChatDisplayMode = mode;
      await tester.pumpWidget(app(AISettings(key: ValueKey(mode))));
      await tester.pumpAndSettle();
      expect(switchFinder,
          mode == AiChatDisplayMode.popup ? findsOneWidget : findsNothing);
      if (mode == AiChatDisplayMode.popup) {
        final toggle =
            find.descendant(of: switchFinder, matching: find.byType(Switch));
        expect(tester.widget<Switch>(toggle).value, false);
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(Prefs().adjustableReaderPopups, true);
      }
    }
    expect(tester.takeException(), isNull);
  });

  for (final tool in ['translation', 'query']) {
    testWidgets('$tool remains usable in a resized window', (tester) async {
      Prefs().aiChatDisplayMode = AiChatDisplayMode.popup;
      Prefs().adjustableReaderPopups = true;
      await open(tester,
          body: tool == 'translation'
              ? TranslationMenu(
                  content: 'Selected text',
                  resultBuilder: (_, __) => const Text('Translation result'))
              : UnifiedQuery(
                  text: 'Selected text',
                  initialSection: QuerySection.translation,
                  panelBuilder: (_, text) => Text(text)));
      await drag(tester, 'top-left', const Offset(2000, 2000));
      expect(tester.getSize(frame), const Size(320, 320));
      expect(tester.takeException(), isNull);
      expect(handle('close').hitTestable(), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 420);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(handle('close'));
      await tester.pumpAndSettle();
    });
  }

  test('only switch is portable; geometry has no stored preferences', () async {
    Prefs().adjustableReaderPopups = true;
    final data = await GlobalSettingsTransfer.decode(
        await GlobalSettingsTransfer.export(Prefs(), scope: 'ai'));
    expect(data['adjustableReaderPopups'], {'type': 'bool', 'value': true});
    Prefs().adjustableReaderPopups = false;
    await GlobalSettingsTransfer.apply(Prefs(), data);
    expect(Prefs().adjustableReaderPopups, true);
    expect(
        Prefs().prefs.getKeys().where((key) => key.startsWith('readerPopup')),
        isEmpty);
  });
}
