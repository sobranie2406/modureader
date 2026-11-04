import 'package:anx_reader/providers/tts_providers.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/tts_role_config.dart';
import 'package:anx_reader/widgets/settings/tts_role_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await L10n.delegate.load(const Locale('zh'));
    await L10n.delegate.load(const Locale('en'));
  });

  Widget app(String locale, {int? bookId}) {
    final container = ProviderContainer(overrides: [
      ttsVoicesProvider.overrideWith((ref) async => const []),
    ]);
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
            body: SingleChildScrollView(
          child: TtsRoleSettingsSection(bookId: bookId),
        )),
      ),
    );
  }

  for (final locale in ['zh', 'en']) {
    testWidgets('$locale: the system engine keeps the switch off',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Prefs().ttsService = 'system';
      await tester.pumpWidget(app(locale));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('tts-role-enabled'));
      await tester.ensureVisible(toggle);
      expect(toggle, findsOneWidget);
      expect(tester.takeException(), isNull);
      // Voices are only offered once an online service can switch voices.
      expect(find.byKey(const ValueKey('tts-role-dialogue')), findsNothing);
    });
  }

  testWidgets('an online service enables the role switch', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Prefs().ttsService = 'edge';
    await Prefs().saveTtsRoleConfig(const TtsRoleConfig(
      enabled: true,
      narrationVoice: 'narrator',
      dialogueVoice: 'dialogue',
    ));
    await tester.pumpWidget(app('zh'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tts-role-narration')), findsOneWidget);
    expect(find.byKey(const ValueKey('tts-role-dialogue')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the switch follows a service change without leaving the page',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Prefs().ttsService = 'system';
    await tester.pumpWidget(app('zh'));
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('tts-role-enabled'));
    await tester.ensureVisible(toggle);
    // Disabled engine: tapping must not enable the feature.
    await tester.tap(toggle, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(Prefs().ttsRoleConfig.enabled, isFalse);

    // Switching to an online engine must re-enable it right away.
    Prefs().ttsService = 'edge';
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(Prefs().ttsRoleConfig.enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a book can restore a global voice after overriding it',
      (tester) async {
    Prefs().ttsService = 'edge';
    await Prefs().saveTtsRoleConfig(const TtsRoleConfig(
        enabled: true,
        narrationVoice: 'global-narration',
        dialogueVoice: 'global-dialogue'));
    await Prefs().saveTtsRoleBookOverride(
        7, const TtsRoleBookOverride(enabled: true, dialogueVoice: 'custom'));
    await tester.pumpWidget(app('zh', bookId: 7));
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('tts-role-book-dialogue'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('跟随全局设置'));
    await tester.pumpAndSettle();
    expect(Prefs().ttsRoleBookOverride(7).dialogueVoice, isNull);
    expect(Prefs().ttsRoleConfigForBook(7).dialogueVoice, 'global-dialogue');
  });

  testWidgets('the per-book block appears only for a concrete book',
      (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Prefs().ttsService = 'edge';
    await Prefs().saveTtsRoleConfig(const TtsRoleConfig(
      enabled: true,
      narrationVoice: 'narrator',
      dialogueVoice: 'dialogue',
    ));

    await tester.pumpWidget(app('zh'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tts-role-book-enabled')), findsNothing);

    await tester.pumpWidget(app('zh', bookId: 7));
    await tester.pumpAndSettle();
    final bookToggle = find.byKey(const ValueKey('tts-role-book-enabled'));
    await tester.ensureVisible(bookToggle);
    expect(bookToggle, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('per-role speeds are editable and persist', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Prefs().ttsService = 'edge';
    await Prefs().saveTtsRoleConfig(const TtsRoleConfig(
      enabled: true,
      narrationVoice: 'narrator',
      dialogueVoice: 'dialogue',
    ));

    await tester.pumpWidget(app('zh'));
    await tester.pumpAndSettle();
    final dialogueRate = find.byKey(const ValueKey('tts-role-dialogue-rate'));
    await tester.ensureVisible(dialogueRate);
    expect(dialogueRate, findsOneWidget);

    await tester.tap(dialogueRate);
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(1.2);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(Prefs().ttsRoleConfig.dialogueRate, closeTo(1.2, .001));
    expect(Prefs().ttsRoleConfig.narrationRate, 1.0);
    expect(find.text('×1.20'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('role speed dialog fits landscape and cancel keeps the rate',
      (tester) async {
    tester.view.physicalSize = const Size(800, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Prefs().ttsService = 'edge';
    await Prefs().saveTtsRoleConfig(
        const TtsRoleConfig(enabled: true, dialogueRate: 1.2));
    await tester.pumpWidget(app('zh'));
    await tester.pumpAndSettle();
    final title = find.text('对话语速');
    await tester.ensureVisible(title);
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.widget<Slider>(find.byType(Slider)).onChanged!(1.5);
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(Prefs().ttsRoleConfig.dialogueRate, 1.2);
    await tester.tap(title);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重置'));
    await tester.pumpAndSettle();
    expect(Prefs().ttsRoleConfig.dialogueRate, 1);
    expect(tester.takeException(), isNull);
  });
}
