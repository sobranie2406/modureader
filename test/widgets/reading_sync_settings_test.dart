import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/sync/reading_sync_scheduler.dart';
import 'package:anx_reader/widgets/settings/reading_sync_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'webdavStatus': true, 'autoSync': true});
    await Prefs().initPrefs();
  });
  test(
      'defaults off, validates all eight intervals, persists independently of secrets',
      () async {
    expect(Prefs().readingTimedSync, false);
    expect(Prefs().readingSyncMinutes, 5);
    for (final m in readingSyncIntervals) {
      Prefs().readingSyncMinutes = m;
      expect(Prefs().readingSyncMinutes, m);
    }
    expect(() => Prefs().readingSyncMinutes = 4, throwsArgumentError);
    Prefs().readingTimedSync = true;
    expect((await SharedPreferences.getInstance()).getBool('readingTimedSync'),
        true);
    expect(Prefs().syncAiSettingsToWebdav, false);
  });
  test('invalid imported interval falls back to five minutes', () async {
    SharedPreferences.setMockInitialValues({'readingSyncMinutes': 0});
    await Prefs().initPrefs();
    expect(Prefs().readingSyncMinutes, 5);
  });
  testWidgets('toggle and interval picker update immediately and persist',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: ReadingSyncSettings()))));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(Prefs().readingTimedSync, true);
    await tester.tap(find.text('Reading sync interval'));
    await tester.pumpAndSettle();
    for (final text in [
      '1 minute',
      '2 minutes',
      '3 minutes',
      '5 minutes',
      '10 minutes',
      '15 minutes',
      '30 minutes',
      '1 hour'
    ]) {
      expect(find.text(text), findsWidgets);
    }
    await tester.ensureVisible(find.text('1 hour'));
    await tester.tap(find.text('1 hour'));
    await tester.pumpAndSettle();
    expect(Prefs().readingSyncMinutes, 60);
    expect(find.text('1 hour'), findsOneWidget);
  });
  testWidgets(
      'master switch off disables the timer settings without enabling credentials',
      (tester) async {
    Prefs().autoSync = false;
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ReadingSyncSettings())));
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, null);
    expect(
        find.text('Enable WebDAV and automatic sync first.'), findsOneWidget);
    expect(Prefs().syncAiSettingsToWebdav, false);
  });
}
