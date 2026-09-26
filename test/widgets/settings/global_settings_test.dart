import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/global_settings.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'central credential toggle defaults off; opt-in needs no password',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: Locale('en'),
      home: Scaffold(body: GlobalSettingsPage()),
    )));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, true);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('plaintext'), findsOneWidget);
    expect(find.text('Export QR / modu link'), findsOneWidget);
    expect(find.text('Restore from modu link'), findsOneWidget);
    expect(find.text('Restore from QR image'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await Prefs().prefs.setDouble('ttsRate', 1.2);
    await Prefs()
        .prefs
        .setString('onlineTtsConfig_openai', '{"key":"fake-key"}');
    final link = GlobalSettingsTransfer.link(
        await GlobalSettingsTransfer.export(Prefs(),
            scope: 'tts', includeSecrets: true));
    await Prefs().prefs.setDouble('ttsRate', 0.7);
    await tester.tap(find.text('Restore from modu link'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), link);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Restore Speech settings?'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(Prefs().ttsRate, 1.2);
    expect(Prefs().getOnlineTtsConfig('openai')['key'], 'fake-key');
    expect(find.textContaining('Speech settings restored.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
