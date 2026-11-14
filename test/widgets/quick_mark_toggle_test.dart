import 'package:modu_reader/utils/platform_utils.dart';
import 'package:modu_reader/widgets/reading_page/quick_mark_toggle.dart';
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
  testWidgets(
      'floating quick mark toolbar toggles the menu independently of exit',
      (tester) async {
    var menu = false, exits = 0;
    await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
                body: QuickMarkToggle(
                    enabled: true,
                    showExit: true,
                    platform: AnxPlatformEnum.android,
                    showMenu: menu,
                    onToggleMenu: () => setState(() => menu = !menu),
                    onPressed: () => exits++)))));
    expect(find.byTooltip('Menu after marking: off'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quick-mark-menu-toggle')));
    await tester.pump();
    expect(menu, isTrue);
    expect(find.byTooltip('Menu after marking: on'), findsOneWidget);
    expect(exits, 0);
    await tester.tap(find.text('Quick mark · Exit'));
    expect(exits, 1);
  });
  testWidgets('120px pane keeps both compact actions tappable and labelled',
      (tester) async {
    var menu = false, exits = 0;
    await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
                body: Align(
                    alignment: Alignment.topRight,
                    child: SizedBox(
                        width: 120,
                        child: QuickMarkToggle(
                            enabled: true,
                            showExit: true,
                            platform: AnxPlatformEnum.android,
                            showMenu: menu,
                            onToggleMenu: () => setState(() => menu = !menu),
                            onPressed: () => exits++)))))));
    final exit = find.byKey(const ValueKey('quick-mark-exit'));
    final toggle = find.byKey(const ValueKey('quick-mark-menu-toggle'));
    expect(find.byType(TextButton), findsNothing);
    expect(tester.getSize(exit), const Size(44, 44));
    expect(tester.getSize(toggle), const Size(44, 44));
    expect(tester.getSemantics(exit).getSemanticsData().tooltip,
        'Turn off quick mark');
    expect(find.byTooltip('Turn off quick mark'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    expect(menu, isTrue);
    expect(find.byTooltip('Menu after marking: on'), findsOneWidget);
    expect(exits, 0);
    await tester.tap(exit);
    expect(exits, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('large text uses compact exit without clipping', (tester) async {
    var exits = 0, menus = 0;
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(3)),
            child: child!),
        home: Scaffold(
            body: Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                    width: 300,
                    child: QuickMarkToggle(
                        enabled: true,
                        showExit: true,
                        platform: AnxPlatformEnum.ios,
                        onToggleMenu: () => menus++,
                        onPressed: () => exits++))))));
    expect(find.byType(TextButton), findsNothing);
    await tester.tap(find.byKey(const ValueKey('quick-mark-menu-toggle')));
    await tester.tap(find.byKey(const ValueKey('quick-mark-exit')));
    expect(menus, 1);
    expect(exits, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('compact exit without menu callback contains only close',
      (tester) async {
    var exits = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                    width: 120,
                    child: QuickMarkToggle(
                        enabled: true,
                        showExit: true,
                        platform: AnxPlatformEnum.ohos,
                        onPressed: () => exits++))))));
    expect(find.byKey(const ValueKey('quick-mark-menu-toggle')), findsNothing);
    expect(find.byType(IconButton), findsOneWidget);
    expect(tester.getSize(find.byType(IconButton)), const Size(44, 44));
    await tester.tap(find.byTooltip('Turn off quick mark'));
    expect(exits, 1);
    expect(tester.takeException(), isNull);
  });
}
