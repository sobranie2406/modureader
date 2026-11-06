import 'package:anx_reader/service/app_brightness.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/widgets/reading_page/document_reader_surface.dart';
import 'package:flutter/material.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'dark reflow dims text only, leaving header and tools outside the layer',
      (tester) async {
    AppBrightness.instance.setLevel(0);
    addTearDown(() => AppBrightness.instance.setFollowSystem(true));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: const Scaffold(
          body: DocumentReaderSurface(
        header: Text('Reader header'),
        body: Center(child: Text('Book text')),
        navigation: SizedBox(),
        tools: Text('Tools remain bright'),
        style: SizedBox(),
      )),
    ));
    await tester.pumpAndSettle();
    final dimmer = find.byKey(const ValueKey('app-flutter-brightness-dimmer'));
    expect(tester.widget<ColoredBox>(dimmer).color.a, closeTo(.95, .001));
    expect(
        tester.getRect(dimmer).top,
        greaterThanOrEqualTo(
            tester.getRect(find.text('Reader header')).bottom));
    final before = tester.getRect(dimmer);
    await tester.tap(find.byKey(const ValueKey('document-tools-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Tools remain bright'), findsOneWidget);
    expect(find.descendant(of: find.byType(BottomSheet), matching: dimmer),
        findsNothing);
    expect(tester.getRect(dimmer), before);
    expect(tester.takeException(), isNull);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  testWidgets(
      'night palette applies in one frame and never exposes underlying text',
      (tester) async {
    Prefs().saveReadThemeToPrefs(ReadTheme(
        backgroundColor: '00FBFBF3',
        textColor: 'FF343434',
        backgroundImagePath: ''));
    await tester.pumpWidget(const MaterialApp(
        home: Stack(children: [
      Text('Underlying original page'),
      DocumentReaderSurface(
          header: Text('Header'),
          body: Text('Recognized text'),
          navigation: SizedBox(),
          tools: Text('Tools'),
          style: Text('Style')),
    ])));
    Material background() => tester.widget<Material>(
        find.byKey(const ValueKey('document-reader-background')));
    expect(background().color!.a, 1);
    Prefs().readingNightMode = true;
    await tester.pump();
    expect(background().color, const Color(0xFF1C1C1E));
    expect(background().animationDuration, Duration.zero);
    expect(
        DefaultTextStyle.of(tester.element(find.text('Recognized text')))
            .style
            .color,
        const Color(0xFFD8D8D8));
    expect(find.byKey(const ValueKey('document-tools-menu')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('document-tools-menu')));
    await tester.pump();
    expect(find.byType(BottomSheet), findsOneWidget);
    Prefs().readingNightMode = false;
    await tester.pump();
    expect(background().color, const Color(0xFFFBFBF3));
  });
  for (final dark in [false, true]) {
    testWidgets(
        'E-Ink OCR surface stays light regardless of app brightness: dark=$dark',
        (tester) async {
      Prefs().eInkMode = true;
      await tester.pumpWidget(MaterialApp(
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: const DocumentReaderSurface(
              header: Text('Header'),
              body: Text('Recognized text'),
              navigation: SizedBox(),
              tools: SizedBox(),
              style: SizedBox())));
      final background = tester.widget<Material>(
          find.byKey(const ValueKey('document-reader-background')));
      expect(background.color, Colors.white);
      expect(
          DefaultTextStyle.of(tester.element(find.text('Recognized text')))
              .style
              .color,
          Colors.black);
      Prefs().readingNightMode = true;
      await tester.pump();
      expect(
          tester
              .widget<Material>(
                  find.byKey(const ValueKey('document-reader-background')))
              .color,
          Colors.white);
      expect(tester.takeException(), isNull);
    });
  }
  for (final size in [
    const Size(320, 740),
    const Size(844, 390),
    const Size(1440, 900)
  ]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('menus overlay stable text and fit 80% at $size / $scale',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var closed = 0;
        await tester.pumpWidget(MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                body: DocumentReaderSurface(
              onBack: () => closed++,
              header: const Text('Header'),
              body: const SizedBox.expand(key: ValueKey('stable-body')),
              navigation: const SizedBox(height: 48, child: Text('1 / 10')),
              tools: const Text('Short tools'),
              style: SingleChildScrollView(
                  child: Column(
                      children: List.generate(60, (i) => Text('Setting $i')))),
              brightness: const Text('Brightness'),
              narration: const Text('Narration'),
              actions: [
                IconButton(onPressed: () {}, icon: const Icon(Icons.toc)),
                IconButton(onPressed: () {}, icon: const Icon(Icons.edit))
              ],
            ))));
        final body = tester.getRect(find.byKey(const ValueKey('stable-body')));
        final toolbar = find.byKey(const ValueKey('document-reader-toolbar'));
        final icons = find.descendant(of: toolbar, matching: find.byType(Icon));
        final expectedIcons = [
          Icons.toc,
          Icons.edit,
          Icons.color_lens,
          Icons.brightness_6_outlined,
          EvaIcons.headphones,
          Icons.document_scanner_outlined,
        ];
        expect(tester.widgetList<Icon>(icons).map((icon) => icon.icon),
            expectedIcons);
        final centers = List.generate(6, (i) => tester.getCenter(icons.at(i)));
        final toolbarRect = tester.getRect(toolbar);
        expect(toolbarRect.width, lessThanOrEqualTo(600));
        for (var i = 0; i < centers.length; i++) {
          expect(centers[i].dy, centers.first.dy);
          expect(
              centers[i].dx,
              closeTo(
                  toolbarRect.left + toolbarRect.width * (i + .5) / 6, .01));
        }
        await tester.tap(find.byKey(const ValueKey('document-tools-menu')));
        await tester.pumpAndSettle();
        final shortHeight = tester.getSize(find.byType(BottomSheet)).height;
        expect(shortHeight, lessThan(size.height * .5));
        expect(tester.getRect(find.byKey(const ValueKey('stable-body'))), body);
        expect(find.text('Header').hitTestable(), findsNothing);
        await tester.tap(find.byKey(const ValueKey('document-style-menu')));
        await tester.pumpAndSettle();
        expect(tester.widgetList<Icon>(icons).map((icon) => icon.icon),
            expectedIcons,
            reason: 'Opening settings retains ebook button icons');
        expect(tester.getSize(find.byType(BottomSheet)).height + 96,
            lessThanOrEqualTo(size.height * .8 + .01));
        expect(tester.getRect(find.byKey(const ValueKey('stable-body'))), body);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(closed, 0);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(closed, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
