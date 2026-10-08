import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/widgets/settings/tts_buffer_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await L10n.delegate.load(const Locale('en'));
    await L10n.delegate.load(const Locale('zh'));
  });
  tearDown(OnlineTts.clearCachedAudio);

  Widget app(String locale, bool online) => MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
            body: SingleChildScrollView(
                child: TtsBufferSettingsSection(online: online))),
      );

  for (final locale in ['zh', 'en']) {
    testWidgets(
        'narrow $locale settings save values and system TTS is disabled',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(locale, true));
      await tester.pumpAndSettle();
      final choice = find.byKey(const ValueKey('tts-buffer-ahead'));
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      await tester.tap(find.text('8').last);
      await tester.pumpAndSettle();
      expect(Prefs().ttsBufferSettings.ahead, 8);
      final clear = find.byKey(const ValueKey('tts-clear-cache'));
      await tester.ensureVisible(clear);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(app(locale, false));
      await tester.pumpAndSettle();
      for (final dropdown in tester
          .widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>))) {
        expect(dropdown.onChanged, isNull);
      }
      expect(Prefs().ttsBufferSettings.ahead, 8);
      expect(tester.takeException(), isNull);
    });
  }
}
