import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/translate/translation_usage.dart';
import 'package:modu_reader/widgets/settings/translation_usage_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('usage card labels estimates and clamps over-quota progress',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final usage = TranslationUsage(Prefs().prefs);
    final account = TranslationUsage.account('baidu', {'baidu_appid': 'app'});
    await usage.record(account, 120);
    await usage.setQuota(account, 100);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: TranslationUsageCard(
                    engine: 'baidu', config: {'baidu_appid': 'app'})))));
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byKey(const ValueKey('translation-usage-progress')))
            .value,
        1);
    expect(find.textContaining('120.0%'), findsOneWidget);
    expect(find.textContaining('estimate'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
