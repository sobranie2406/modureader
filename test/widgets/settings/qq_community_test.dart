import 'package:modu_reader/widgets/settings/qq_community.dart';
import 'package:modu_reader/widgets/settings/community_links.dart';
import 'package:modu_reader/widgets/settings/settings_section.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  for (final width in [320.0, 640.0, 1200.0]) {
    testWidgets('QQ content aligns with preceding settings at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsSection.content(
                  title: const Text('开源与许可'),
                  padding: EdgeInsets.zero,
                  child: const ListTile(title: Text('开源许可')),
                ),
                const CommunityLinks(),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final left = tester.getTopLeft(find.text('开源许可')).dx;
      expect(tester.getTopLeft(find.text(QqCommunity.groupNumber)).dx,
          closeTo(left, 0.1));
      expect(tester.getTopLeft(find.text('在 QQ 搜索群号申请加入。')).dx,
          closeTo(left, 0.1));
      expect(tester.getTopLeft(find.widgetWithText(TextButton, '复制群号')).dx,
          closeTo(left, 0.1));
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in ['zh', 'en']) {
    for (final size in [const Size(320, 640), const Size(640, 320)]) {
      testWidgets('QQ number, Telegram channel and group: $locale $size',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? copied;
        final opened = <String>[];
        const urlChannel = MethodChannel('plugins.flutter.io/url_launcher');
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(urlChannel, (call) async {
          if (call.method == 'launch') {
            final arguments = call.arguments as Map;
            opened.add(arguments['url'] as String);
            expect(arguments['useWebView'], false);
            expect(arguments['useSafariVC'], false);
          }
          return true;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(urlChannel, null));
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null));
        await tester.pumpWidget(MaterialApp(
          locale: Locale(locale),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const Scaffold(
            body: SingleChildScrollView(child: CommunityLinks()),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text(QqCommunity.groupNumber), findsOneWidget);
        await tester
            .tap(find.text(locale == 'zh' ? '复制群号' : 'Copy group number'));
        await tester.pumpAndSettle();
        expect(copied, QqCommunity.groupNumber);
        // Let the clipboard snackbar clear the landscape viewport.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.text('t.me/Modureader'), findsOneWidget);
        expect(find.text('t.me/ModuReaderDiscussion'), findsOneWidget);
        for (final key in ['telegram-channel', 'telegram-group']) {
          final link = find.byKey(ValueKey(key));
          await tester.ensureVisible(link);
          await tester.pumpAndSettle();
          await tester.tap(link);
          await tester.pumpAndSettle();
        }
        expect(opened,
            [CommunityLinks.telegramChannel, CommunityLinks.telegramGroup]);
        expect(find.byIcon(Icons.qr_code_2), findsNothing);
        expect(find.byType(Image), findsNothing);
        expect(find.byType(InteractiveViewer), findsNothing);
        expect(tester.takeException(), isNull);
        expect(find.byType(Dialog), findsNothing);
      });
    }
  }
}
