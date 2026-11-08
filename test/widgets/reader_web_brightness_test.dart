import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/app_brightness.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/widgets/reading_page/reader_content_brightness.dart';
import 'package:anx_reader/widgets/reading_page/reader_web_brightness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  for (final platform in AnxPlatformEnum.values) {
    testWidgets('$platform has only one brightness owner', (tester) async {
      final brightness =
          AppBrightness(nativeWindow: false, nativeDimming: false);
      brightness.setLevel(.4);
      final scripts = <String>[];
      final web = ReaderWebBrightness((script) async => scripts.add(script),
          platform: platform);
      await tester.pumpWidget(MaterialApp(
          home: ReaderContentBrightness(
        controller: brightness,
        backgroundColor: Colors.white,
        child: Builder(builder: (context) {
          web.bind(context);
          return const SizedBox();
        }),
      )));
      brightness.setLevel(.2);
      await tester.pump();
      brightness.setFollowSystem(true);
      await tester.pump();
      if (platform == AnxPlatformEnum.ohos) {
        expect(scripts, hasLength(3));
        expect(scripts.first, contains("'0.4'"));
        expect(scripts.last, contains("'1.0'"));
      } else {
        expect(scripts, isEmpty,
            reason: 'Native composition already dims this view');
      }
      web.dispose();
      final count = scripts.length;
      brightness.setLevel(.3);
      expect(scripts, hasLength(count));
      await tester.pumpWidget(const SizedBox());
      brightness.dispose();
    });
  }
  testWidgets('OHOS outside reading content stays unchanged', (tester) async {
    final scripts = <String>[];
    final web = ReaderWebBrightness((script) async => scripts.add(script),
        platform: AnxPlatformEnum.ohos);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      web.bind(context);
      return const SizedBox();
    })));
    await web.apply();
    expect(scripts, isEmpty);
    web.dispose();
  });
}
