import 'dart:convert';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:modu_reader/service/sync/ai_settings_sync.dart';
import 'package:modu_reader/widgets/ai/skill_template_draft_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const screens = [
    'library',
    'reader',
    'selection.custom-preset-dictionary',
    'selection.ai',
    'lookup.knowledge',
    'lookup.classical',
    'lookup.book'
  ];

  test(
      'screens inherit prior defaults once logically and persist independently',
      () async {
    SharedPreferences.setMockInitialValues({'aiSkillTemplateDraft': true});
    await Prefs().initPrefs();
    for (final screen in screens) {
      expect(Prefs().aiDraftFor(screen), true);
    }
    Prefs().setAiDraftFor('reader', false);
    Prefs().setAiDraftFor('lookup.knowledge', false);
    await Prefs().initPrefs();
    for (final screen in screens) {
      expect(Prefs().aiDraftFor(screen),
          !['reader', 'lookup.knowledge'].contains(screen));
    }
    expect(Prefs().aiDraftFor('lookup.classical', legacyDefault: false), false);
    Prefs().setAiDraftFor('lookup.classical', true);
    expect(Prefs().aiDraftFor('lookup.classical', legacyDefault: false), true);
    expect(Prefs().prefs.getBool('aiSkillTemplateDraft'), true);
  });

  test('AI menu font sizes are local and independent across screens', () async {
    SharedPreferences.setMockInitialValues({'aiChatFontSize': 14.0});
    await Prefs().initPrefs();
    Prefs().setAiChatFontSizeFor('lookup.knowledge', 18);
    Prefs().setAiChatFontSizeFor('lookup.classical', 12);
    await Prefs().initPrefs();
    expect(Prefs().aiChatFontSizeFor('lookup.knowledge'), 18);
    expect(Prefs().aiChatFontSizeFor('lookup.classical'), 12);
    expect(Prefs().aiChatFontSizeFor('lookup.book'), 14);
    for (final snapshot in [
      await Prefs().buildPrefsBackupMap(),
      collectAiSettingsForSync(Prefs().prefs)
    ]) {
      expect(snapshot.containsKey('aiChatAppearanceByScreen'), false);
    }
  });

  test(
      'backup, settings import and cloud sync never transfer screen preferences',
      () async {
    SharedPreferences.setMockInitialValues({'aiSkillTemplateDraft': true});
    await Prefs().initPrefs();
    Prefs().setAiDraftFor('reader', false);
    for (final snapshot in [
      await Prefs().buildPrefsBackupMap(),
      await GlobalSettingsTransfer.decode(
          await GlobalSettingsTransfer.export(Prefs())),
      collectAiSettingsForSync(Prefs().prefs)
    ]) {
      expect(snapshot.containsKey('aiSkillTemplateDraft'), false);
      expect(snapshot.containsKey('aiDraftByScreen'), false);
    }
    await Prefs().applyPrefsBackupMap({
      'aiSkillTemplateDraft': {'type': 'bool', 'value': false},
      'aiDraftByScreen': {
        'type': 'string',
        'value': jsonEncode({'reader': true})
      },
    });
    await applyAiSettingsFromSync(Prefs().prefs, {});
    for (final legacy in [
      {'type': 'bool', 'value': false},
      {'type': 'reset', 'value': null},
    ]) {
      await GlobalSettingsTransfer.apply(Prefs(), {
        prefsBackupVersionKey: 1,
        'aiSkillTemplateDraft': legacy,
      });
    }
    expect(Prefs().aiDraftFor('reader'), false);
    expect(Prefs().aiDraftFor('library'), true);
    expect(
        () => applyAiSettingsFromSync(Prefs().prefs, {'aiDraftByScreen': '{}'}),
        throwsFormatException);
  });

  testWidgets(
      'two visible switches do not change each other and remember reopening',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    Widget page() => const MaterialApp(
            home: Scaffold(
                body: Column(children: [
          SkillTemplateDraftTile(screen: 'library', compact: true),
          SkillTemplateDraftTile(screen: 'reader', compact: true),
        ])));
    await tester.pumpWidget(page());
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(tester.widgetList<Switch>(find.byType(Switch)).map((s) => s.value),
        [true, false]);
    await tester.pumpWidget(const SizedBox());
    await Prefs().initPrefs();
    await tester.pumpWidget(page());
    expect(tester.widgetList<Switch>(find.byType(Switch)).map((s) => s.value),
        [true, false]);
  });
}
