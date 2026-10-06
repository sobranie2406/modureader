import 'package:anx_reader/widgets/settings/qq_community.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in ['zh', 'en']) {
    for (final size in [const Size(320, 640), const Size(640, 320)]) {
      testWidgets(
          'QQ group number and clipboard without QR code: $locale $size',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? copied;
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
            body: SingleChildScrollView(child: QqCommunity()),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text(QqCommunity.groupNumber), findsOneWidget);
        await tester
            .tap(find.text(locale == 'zh' ? '复制群号' : 'Copy group number'));
        await tester.pumpAndSettle();
        expect(copied, QqCommunity.groupNumber);
        expect(find.byIcon(Icons.qr_code_2), findsNothing);
        expect(find.byType(Image), findsNothing);
        expect(find.byType(InteractiveViewer), findsNothing);
        expect(tester.takeException(), isNull);
        expect(find.byType(Dialog), findsNothing);
      });
    }
  }
}
