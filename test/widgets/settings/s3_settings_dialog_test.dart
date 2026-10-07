import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/widgets/settings/s3_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  for (final language in ['en', 'zh']) {
    testWidgets(
        'S3 configuration saves in a narrow $language window without touching WebDAV',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await Prefs().prefs.setString('webdavInfo', 'existing-webdav-untouched');
      Map<String, dynamic>? result;
      await tester.pumpWidget(MaterialApp(
        locale: Locale(language),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await showDialog<Map<String, dynamic>>(
                          context: context,
                          builder: (_) => const S3SettingsDialog(initial: {
                                'endpoint': 'https://s3.example.test',
                                'bucket': 'books',
                                'accessKeyId': 'test-id',
                                'secretAccessKey': 'test-secret',
                              }));
                    },
                    child: const Text('open')))),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('AWS Signature V2 (COS / legacy)'), findsNothing);
      final secret = find.byKey(const ValueKey('s3-secretAccessKey'));
      await tester.ensureVisible(secret);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextFormField>(find.descendant(
                  of: secret, matching: find.byType(TextFormField)))
              .controller!
              .text,
          'test-secret');
      expect(
          tester
              .widget<TextField>(
                  find.descendant(of: secret, matching: find.byType(TextField)))
              .obscureText,
          true);
      final reveal =
          find.descendant(of: secret, matching: find.byType(IconButton));
      await tester.tap(reveal);
      await tester.pump();
      expect(
          tester
              .widget<TextField>(
                  find.descendant(of: secret, matching: find.byType(TextField)))
              .obscureText,
          false);
      await tester.tap(reveal);
      await tester.pump();
      final advanced = find.byKey(const ValueKey('s3-advanced'));
      await tester.ensureVisible(advanced);
      await tester
          .tap(find.text(language == 'zh' ? '高级设置' : 'Advanced settings'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('s3-signature-v4')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(language == 'zh' ? '保存' : 'Save'));
      await tester.pumpAndSettle();
      expect(result?['bucket'], 'books');
      expect(result?['remoteRoot'], 'modu');
      expect(result?['signature'], 'v4');
      expect(result?['allowInsecure'], false);
      expect(
          Prefs().prefs.getString('webdavInfo'), 'existing-webdav-untouched');
      expect(Prefs().syncProtocol, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
