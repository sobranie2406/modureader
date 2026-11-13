import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:modu_reader/widgets/reading_page/more_settings/scroll_auto_align_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('alignment defaults on and preserves the choice after reload', () async {
    expect(Prefs().scrollAutoAlign, isTrue);
    for (final enabled in [false, true]) {
      Prefs().scrollAutoAlign = enabled;
      await Prefs().initPrefs();
      expect(Prefs().scrollAutoAlign, enabled);
    }
  });

  test('global settings transfer preserves disabled alignment', () async {
    Prefs().scrollAutoAlign = false;
    final values = await GlobalSettingsTransfer.decode(
        await GlobalSettingsTransfer.export(Prefs()));
    Prefs().scrollAutoAlign = true;
    await GlobalSettingsTransfer.apply(Prefs(), values);
    expect(Prefs().scrollAutoAlign, isFalse);
    await expectLater(
        GlobalSettingsTransfer.apply(Prefs(), {
          ...values,
          'scrollAutoAlign': {'type': 'bool', 'value': 'false'},
        }),
        throwsFormatException);
    expect(Prefs().scrollAutoAlign, isFalse);
  });

  testWidgets('switch applies immediately and fits a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final changes = <bool>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ScrollAutoAlignTile(onChanged: changes.add))));
    final toggle = find.byKey(const ValueKey('scroll-auto-align'));
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(Prefs().scrollAutoAlign, isFalse);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(Prefs().scrollAutoAlign, isTrue);
    expect(changes, [false, true]);
    expect(tester.takeException(), isNull);
  });
}
