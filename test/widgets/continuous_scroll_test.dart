import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:modu_reader/widgets/reading_page/more_settings/continuous_scroll_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('defaults to continuous, persists and roundtrips reading settings',
      () async {
    expect(Prefs().continuousScroll, isTrue);
    Prefs().continuousScroll = false;
    await Prefs().initPrefs();
    expect(Prefs().continuousScroll, isFalse);
    final values = await GlobalSettingsTransfer.decode(
        await GlobalSettingsTransfer.export(Prefs(), scope: 'reading'));
    Prefs().continuousScroll = true;
    await GlobalSettingsTransfer.apply(Prefs(), values);
    expect(Prefs().continuousScroll, isFalse);
  });

  testWidgets('switch saves and applies immediately, without a save button',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final changes = <bool>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ContinuousScrollTile(onChanged: changes.add))));
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(Prefs().continuousScroll, isFalse);
    expect(changes, [false]);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(Prefs().continuousScroll, isTrue);
    expect(changes, [false, true]);
    expect(tester.takeException(), isNull);
  });
}
