import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/user_prompt.dart';
import 'package:anx_reader/page/settings_page/ai_reading_skills.dart';
import 'package:anx_reader/widgets/ai/reading_skill_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> mount(WidgetTester tester,
      {Size size = const Size(500, 1000), double scale = 1}) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    Prefs().userPrompts = [
      for (final id in ['a', 'b'])
        UserPrompt(
            id: id,
            name: '自定义$id',
            content: '我的提示词$id',
            order: 0,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026))
    ];
    Prefs().readAnySkillOrder = [
      'builtin:smart_summary',
      'custom:a',
      'custom:b'
    ];
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        ...GlobalMaterialLocalizations.delegates
      ],
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: const Scaffold(body: AiReadingSkillsSettings()),
    )));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'dragging custom above built-in persists mixed order and runtime chips',
      (tester) async {
    await mount(tester);
    final handle = find.byKey(const ValueKey('reading-skill-drag-custom:b'));
    final first =
        find.byKey(const ValueKey('reading-skill-drag-builtin:smart_summary'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, -24));
    await tester.pump();
    await gesture.moveTo(tester.getTopLeft(first) - const Offset(0, 48));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(Prefs().readAnySkillOrder.take(3),
        ['custom:b', 'builtin:smart_summary', 'custom:a']);
    expect(configuredReadingSkillChips(const Locale('zh')).first.label, '自定义b');
    await Prefs().initPrefs();
    expect(Prefs().readAnySkillOrder.first, 'custom:b');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'template draft switch defaults off, persists and observes changes',
      (tester) async {
    await mount(tester);
    final tile = find.byKey(const ValueKey('ai-skill-template-draft-switch'));
    expect(tester.widget<SwitchListTile>(tile).value, false);
    await tester.tap(find.descendant(of: tile, matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(Prefs().aiSkillTemplateDraft, true);
    await Prefs().initPrefs();
    expect(Prefs().aiSkillTemplateDraft, true);
    Prefs().aiSkillTemplateDraft = false;
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'built-in up/down can cross custom skills and reset does not change switches or prompts',
      (tester) async {
    await mount(tester);
    final tile = find.byKey(const ValueKey('reading-skill-smart_summary'));
    await tester
        .tap(find.descendant(of: tile, matching: find.byIcon(Icons.more_vert)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下移'));
    await tester.pumpAndSettle();
    expect(Prefs().readAnySkillOrder.take(3),
        ['custom:a', 'builtin:smart_summary', 'custom:b']);
    await tester
        .tap(find.byKey(const ValueKey('reading-skill-switch-smart_summary')));
    await tester
        .tap(find.byKey(const ValueKey('custom-reading-skill-switch-a')));
    await tester.pumpAndSettle();
    expect(Prefs().isReadAnySkillEnabled('smart_summary'), isFalse);
    expect(Prefs().userPrompts.first.enabled, isFalse);
    await tester.tap(find.byKey(const ValueKey('reset-reading-skill-order')));
    await tester.pumpAndSettle();
    expect(Prefs().readAnySkillOrder, isEmpty);
    expect(Prefs().isReadAnySkillEnabled('smart_summary'), isFalse);
    expect(Prefs().userPrompts.first.content, '我的提示词a');
    expect(Prefs().userPrompts.first.enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'compact window with large text retains usable switches and drag handles',
      (tester) async {
    await mount(tester, size: const Size(320, 640), scale: 1.5);
    final first =
        find.byKey(const ValueKey('reading-skill-switch-smart_summary'));
    await tester.ensureVisible(first);
    await tester.pumpAndSettle();
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(Prefs().isReadAnySkillEnabled('smart_summary'), isFalse);
    expect(tester.takeException(), isNull);
  });
}
