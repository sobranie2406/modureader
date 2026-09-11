import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart' show navigatorKey;
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/utils/webView/gererate_url.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('native reader fixture can build URL with default font settings',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigatorKey,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const Scaffold(body: Text('Fixture'))));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Server().start();
      try {
        expect(generateUrl('http://127.0.0.1/fixture', ''),
            contains('/foliate-js/index.html'));
      } finally {
        await Server().stop();
      }
    });
  });
}
