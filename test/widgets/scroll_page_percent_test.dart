import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/scroll_page_percent_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('defaults to 80 and remembers all integer percentages after reload',
      () async {
    expect(Prefs().scrollPagePercent, 80);
    for (var value = 80; value <= 100; value++) {
      Prefs().scrollPagePercent = value;
      await Prefs().initPrefs();
      expect(Prefs().scrollPagePercent, value);
    }
    Prefs().scrollPagePercent = 999;
    expect(Prefs().scrollPagePercent, 100);
    Prefs().scrollPagePercent = -1;
    expect(Prefs().scrollPagePercent, 80);
    await Prefs().prefs.setString('scrollPagePercent', 'bad');
    expect(Prefs().scrollPagePercent, 80);
  });

  test(
      'global export/import preserves percentage and rejects out-of-range data',
      () async {
    Prefs().scrollPagePercent = 97;
    final exported = await GlobalSettingsTransfer.export(Prefs());
    final values = await GlobalSettingsTransfer.decode(exported);
    Prefs().scrollPagePercent = 80;
    await GlobalSettingsTransfer.apply(Prefs(), values);
    expect(Prefs().scrollPagePercent, 97);
    for (final invalid in [79, 101]) {
      await expectLater(
          GlobalSettingsTransfer.apply(Prefs(), {
            ...values,
            'scrollPagePercent': {'type': 'int', 'value': invalid},
          }),
          throwsFormatException);
      expect(Prefs().scrollPagePercent, 97);
    }
  });

  testWidgets(
      'slider offers 1-percent steps and applies on release at narrow widths',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final changes = <int>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ScrollPagePercentTile(onChanged: changes.add))));
    var slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 80);
    expect(slider.max, 100);
    expect(slider.divisions, 20);
    slider.onChanged!(91);
    await tester.pump();
    expect(find.text('91%'), findsOneWidget);
    expect(Prefs().scrollPagePercent, 80);
    expect(changes, isEmpty);
    slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeEnd!(91);
    expect(Prefs().scrollPagePercent, 91);
    expect(changes, [91]);
    slider.onChanged!(100);
    slider.onChangeEnd!(100);
    await tester.pump();
    expect(find.textContaining('0% overlap'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
