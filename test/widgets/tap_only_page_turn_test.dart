import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/tap_only_page_turn_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('tap-only is opt-in and remembered after preference reload', () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    expect(Prefs().tapOnlyPageTurn, false);
    Prefs().tapOnlyPageTurn = true;
    await Prefs().initPrefs();
    expect(Prefs().tapOnlyPageTurn, true);
    Prefs().tapOnlyPageTurn = false;
    await Prefs().initPrefs();
    expect(Prefs().tapOnlyPageTurn, false);
  });
  for (final platform in AnxPlatformEnum.values) {
    testWidgets('tap-only switch platform gate and toggle: $platform',
        (tester) async {
      bool? selected;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TapOnlyPageTurnTile(
                  value: false,
                  platform: platform,
                  onChanged: (value) => selected = value))));
      final mobile = [
        AnxPlatformEnum.android,
        AnxPlatformEnum.ios,
        AnxPlatformEnum.ohos
      ].contains(platform);
      expect(
          find.byType(SwitchListTile), mobile ? findsOneWidget : findsNothing);
      if (mobile) {
        await tester.tap(find.text('Tap-only page turning'));
        expect(selected, true);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
