import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/narrate.dart';
import 'package:anx_reader/service/config_transfer/config_transfer_codec.dart';
import 'package:anx_reader/service/config_transfer/tts_config_transfer.dart';
import 'package:anx_reader/widgets/settings/config_transfer_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'ttsService': 'openai',
      'onlineTtsConfig_openai': '{"key":"old-test-key"}',
      'unrelated': 'unchanged',
    });
    await Prefs().initPrefs();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: Locale('en'),
      home: Scaffold(body: NarrateSettings()),
    )));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'service edits remain drafts until saved and export uses saved data',
      (tester) async {
    await open(tester);
    final keyField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'API Key');
    await tester.enterText(keyField, 'new-test-key');
    await tester.pumpAndSettle();
    expect(Prefs().getOnlineTtsConfig('openai')['key'], 'old-test-key');
    var tile =
        tester.widget<ConfigTransferTile>(find.byType(ConfigTransferTile));
    expect(tile.enabled, isFalse);
    expect(
        tile.getData()['providers']['openai']['config']['key'], 'old-test-key');
    await tap(tester, 'Save settings');
    expect(Prefs().getOnlineTtsConfig('openai')['key'], 'new-test-key');
    tile = tester.widget<ConfigTransferTile>(find.byType(ConfigTransferTile));
    expect(tile.enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clear requires confirmation and resets only TTS',
      (tester) async {
    await open(tester);
    await tap(tester, 'Clear settings');
    await tap(tester, 'Cancel');
    expect(Prefs().getOnlineTtsConfig('openai')['key'], 'old-test-key');
    await tap(tester, 'Clear settings');
    await tap(tester, 'Clear');
    expect(TtsConfigTransfer.snapshot(Prefs()), TtsConfigTransfer.defaults());
    expect(Prefs().prefs.getString('unrelated'), 'unchanged');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'import Modu link refreshes form without fetching voices or playing',
      (tester) async {
    await open(tester);
    await tap(tester, 'Import speech settings');
    expect(find.text('Read from QR image'), findsOneWidget);
    final data = TtsConfigTransfer.defaults();
    data['service'] = 'openai';
    data['providers']['openai']['config'] = {'key': 'imported-test-key'};
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        ConfigTransferCodec.encode(kind: 'tts', data: data));
    await tap(tester, 'Import configuration');
    expect(Prefs().getOnlineTtsConfig('openai')['key'], 'imported-test-key');
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        find.byWidgetPredicate(
            (w) => w is TextField && w.controller?.text == 'imported-test-key'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
