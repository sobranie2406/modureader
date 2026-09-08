import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/widgets/reading_page/quick_mark_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in AnxPlatformEnum.values) {
    testWidgets('quick mark platform gate: $platform', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: QuickMarkToggle(
                  enabled: false,
                  platform: platform,
                  onPressed: () => taps++))));
      final mobile = [
        AnxPlatformEnum.android,
        AnxPlatformEnum.ios,
        AnxPlatformEnum.ohos
      ].contains(platform);
      expect(find.byType(IconButton), mobile ? findsOneWidget : findsNothing);
      if (mobile) {
        await tester.tap(find.byType(IconButton));
        expect(taps, 1);
      }
    });
  }
  testWidgets('active mobile mode always offers a visible exit',
      (tester) async {
    var exits = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: QuickMarkToggle(
                enabled: true,
                platform: AnxPlatformEnum.ios,
                showExit: true,
                onPressed: () => exits++))));
    await tester.tap(find.text('Quick mark · Exit'));
    expect(exits, 1);
  });
}
