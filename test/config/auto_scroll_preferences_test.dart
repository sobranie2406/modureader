import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/sync/ai_settings_sync.dart';
import 'package:modu_reader/widgets/reading_page/style_widget.dart';
import 'package:modu_reader/widgets/reading_page/more_settings/auto_scroll_tile.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test(
      'opt-in defaults off, speed persists locally and rejects non-finite input',
      () async {
    expect(Prefs().autoScrollEnabled, isFalse);
    expect(Prefs().autoScrollSpeed, 1);
    Prefs().autoScrollEnabled = true;
    Prefs().autoScrollSpeed = 1.37;
    await Prefs().initPrefs();
    expect(Prefs().autoScrollEnabled, isTrue);
    expect(Prefs().autoScrollSpeed, 1.4);
    Prefs().autoScrollSpeed = double.nan;
    expect(Prefs().autoScrollSpeed, 1.4);
  });

  test(
      'automatic scrolling never enters backup or settings sync and cannot be restored',
      () async {
    Prefs().autoScrollEnabled = true;
    Prefs().autoScrollSpeed = 1.5;
    final backup = await Prefs().buildPrefsBackupMap();
    final synced = collectAiSettingsForSync(Prefs().prefs);
    for (final key in ['autoScrollEnabled', 'autoScrollSpeed']) {
      expect(backup.containsKey(key), isFalse);
      expect(synced.containsKey(key), isFalse);
    }
    await Prefs().applyPrefsBackupMap({
      'autoScrollEnabled': {'type': 'bool', 'value': false},
      'autoScrollSpeed': {'type': 'double', 'value': 4.0},
    });
    expect(Prefs().autoScrollEnabled, isTrue);
    expect(Prefs().autoScrollSpeed, 1.5);
  });

  testWidgets(
      'switch exists only for scroll flow and disabling does not alter the flow',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: AutoScrollTile())));
    expect(find.byType(SwitchListTile), findsNothing);
    Prefs().pageTurnStyle = PageTurn.scroll;
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(Prefs().autoScrollEnabled, isTrue);
    await tester.tap(find.byType(Switch));
    expect(Prefs().pageTurnStyle, PageTurn.scroll);
    Prefs().pageTurnStyle = PageTurn.slide;
    await tester.pump();
    expect(find.byType(SwitchListTile), findsNothing);
  });
}
