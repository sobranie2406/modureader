import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:anx_reader/widgets/reading_page/selection_search_zoom.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('zoom defaults, clamps, persists and tolerates invalid local data',
      () async {
    expect(Prefs().selectionSearchZoomPercent, 100);
    for (final percent in [50, 80, 100, 200]) {
      await Prefs().saveSelectionSearchZoomPercent(percent);
      await Prefs().initPrefs();
      expect(Prefs().selectionSearchZoomPercent, percent);
    }
    await Prefs().saveSelectionSearchZoomPercent(999);
    expect(Prefs().selectionSearchZoomPercent, 200);
    await Prefs().saveSelectionSearchZoomPercent(0);
    expect(Prefs().selectionSearchZoomPercent, 50);
    await Prefs().prefs.setString('selectionSearchZoomPercent', 'bad');
    expect(Prefs().selectionSearchZoomPercent, 100);
  });

  test('zoom travels with global settings; invalid imports cannot modify it',
      () async {
    await Prefs().saveSelectionSearchZoomPercent(80);
    final data = await GlobalSettingsTransfer.decode(
        await GlobalSettingsTransfer.export(Prefs()));
    expect(data['selectionSearchZoomPercent'], {'type': 'int', 'value': 80});
    await Prefs().saveSelectionSearchZoomPercent(100);
    await GlobalSettingsTransfer.apply(Prefs(), data);
    expect(Prefs().selectionSearchZoomPercent, 80);
    for (final invalid in [49, 201]) {
      await expectLater(
          GlobalSettingsTransfer.apply(Prefs(), {
            ...data,
            'selectionSearchZoomPercent': {'type': 'int', 'value': invalid},
          }),
          throwsFormatException);
      expect(Prefs().selectionSearchZoomPercent, 80);
    }
  });

  test('zoom script uses absolute page scale and suppresses text inflation',
      () {
    expect(
        selectionSearchZoomScript(80), contains("'zoom', '0.8', 'important'"));
    expect(
        selectionSearchZoomScript(0), contains("'zoom', '0.5', 'important'"));
    expect(
        selectionSearchZoomScript(999), contains("'zoom', '2.0', 'important'"));
    expect(
        selectionSearchZoomScript(100), contains("'zoom', '1.0', 'important'"));
    expect(
        selectionSearchZoomScript(80), contains("'text-size-adjust', '100%'"));
    expect(
        selectionSearchZoomScript(80), isNot(contains('flutter_inappwebview')));
  });
}
