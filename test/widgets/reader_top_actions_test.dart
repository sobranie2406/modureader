import 'dart:io';
import 'dart:ui' as ui;
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/widgets/reading_page/reader_top_actions.dart';
import 'package:anx_reader/widgets/reading_page/classical_translation_icon.dart';
import 'package:anx_reader/widgets/settings/classical_translation_settings.dart';
import 'package:anx_reader/service/translate/classical_translation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  testWidgets(
      'classical icon reuses Material 文 instead of system text and inherits color',
      (tester) async {
    for (final color in [Colors.black87, Colors.white70]) {
      await tester.pumpWidget(MaterialApp(
          home: IconTheme(
              data: IconThemeData(color: color),
              child: const ClassicalTranslationIcon())));
      expect(find.byType(Text), findsNothing);
      expect(find.byIcon(Icons.translate_outlined), findsOneWidget);
      expect(tester.widget<Icon>(find.byIcon(Icons.translate_outlined)).color,
          color);
      final clip = tester.widget<ClipPath>(find.byType(ClipPath));
      final path = clip.clipper!.getClip(const Size.square(24));
      expect(path.contains(const Offset(5, 5)), isTrue);
      expect(path.contains(const Offset(12, 16)), isTrue);
      expect(path.contains(const Offset(18, 18)), isFalse);
    }
  });
  test(
      'configuration normalizes unknown and duplicate actions and keeps hidden order',
      () {
    final config = ReaderTopActionsConfig.parse(
        '{"order":["search","search","unknown"],"hidden":["ai"]}');
    expect(config.order.length, ReaderTopAction.values.length);
    expect(config.order.first, ReaderTopAction.search);
    expect(config.visible(ReaderTopAction.values),
        isNot(contains(ReaderTopAction.ai)));
    expect(ReaderTopActionsConfig.parse(config.encode()).hidden, config.hidden);
    expect(
        ReaderTopActionsConfig.parse('broken').order, ReaderTopAction.values);
  });
  testWidgets(
      '40 percent budget preserves order, overflow actions and hidden settings',
      (tester) async {
    final calls = <ReaderTopAction>[];
    final config = ReaderTopActionsConfig.parse('{}');
    config.hidden.add(ReaderTopAction.ai);
    config.order.remove(ReaderTopAction.search);
    config.order.insert(0, ReaderTopAction.search);
    Prefs().readerToolbar = config.encode();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ReaderTopActions(
      readerWidth: 600,
      buttons: {
        for (final a in ReaderTopAction.values)
          a: IconButton(
              key: ValueKey('top-${a.name}'),
              icon: a.icon,
              onPressed: () => calls.add(a))
      },
      actions: {for (final a in ReaderTopAction.values) a: () => calls.add(a)},
    ))));
    expect(find.byType(IconButton), findsNWidgets(5));
    expect(find.byKey(const ValueKey('top-ai')), findsNothing);
    expect(find.byKey(const ValueKey('top-search')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reader-top-more')));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<ReaderTopAction>), findsNWidgets(3));
    await tester.tap(find.text('Bookmark'));
    await tester.pumpAndSettle();
    expect(calls, [ReaderTopAction.bookmark]);
    expect(tester.takeException(), isNull);
  });
  testWidgets('toolbar adapts to reader pane resizing with full touch targets',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [320.0, 390.0, 600.0, 959.0, 960.0, 1200.0, 360.0]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
            width: width,
            child: LayoutBuilder(
              builder: (_, constraints) => AppBar(
                leading: const BackButton(),
                title:
                    const Text('Book title', overflow: TextOverflow.ellipsis),
                actions: [
                  ReaderTopActions(
                    readerWidth: constraints.maxWidth,
                    buttons: {
                      for (final a in ReaderTopAction.values)
                        a: IconButton(
                            key: ValueKey('top-${a.name}'),
                            onPressed: () {},
                            icon: a.icon)
                    },
                    actions: {for (final a in ReaderTopAction.values) a: () {}},
                  )
                ],
              ),
            )),
      ))));
      await tester.pumpAndSettle();
      final count = switch (width) {
        320 => 1,
        360 || 390 => 2,
        600 => 4,
        959 => 6,
        _ => 8,
      };
      expect(tester.getSize(find.byType(ReaderTopActions)).width,
          lessThanOrEqualTo(width * .4));
      expect(find.byType(BackButton), findsOneWidget);
      for (var i = 0; i < ReaderTopAction.values.length; i++) {
        final button =
            find.byKey(ValueKey('top-${ReaderTopAction.values[i].name}'));
        expect(button, i < count ? findsOneWidget : findsNothing);
        if (i < count) expect(tester.getSize(button), const Size(48, 48));
      }
      final more = find.byKey(const ValueKey('reader-top-more'));
      if (count < ReaderTopAction.values.length) {
        expect(tester.getSize(more), const Size(48, 48));
      } else {
        expect(more, findsNothing);
      }
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('More disappears as actions are hidden, including an empty bar',
      (tester) async {
    final actions = ReaderTopAction.values.take(3).toList();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: ReaderTopActions(
            readerWidth: 240,
            buttons: {
              for (final action in actions)
                action: IconButton(onPressed: () {}, icon: action.icon),
            },
            actions: {for (final action in actions) action: () {}},
          ),
        ),
      ),
    ));
    final more = find.byKey(const ValueKey('reader-top-more'));
    expect(more, findsOneWidget);

    Prefs().readerToolbar =
        ReaderTopActionsConfig(order: actions, hidden: {actions.last}).encode();
    await tester.pump();
    expect(more, findsNothing);
    expect(find.byType(IconButton), findsNWidgets(2));
    expect(tester.getSize(find.byType(ReaderTopActions)).width, 96);

    Prefs().readerToolbar =
        ReaderTopActionsConfig(order: actions, hidden: actions.toSet())
            .encode();
    await tester.pump();
    expect(more, findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(tester.getSize(find.byType(ReaderTopActions)).width, 0);

    Prefs().readerToolbar = '{}';
    await tester.pump();
    expect(more, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'engine and direction persist; secrets obscured without sending requests',
      (tester) async {
    Prefs().classicalTranslationEngine = ClassicalTranslationEngine.baidu;
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body:
                SingleChildScrollView(child: ClassicalTranslationSettings()))));
    await tester.enterText(
        find.byKey(const ValueKey('baidu_key')), 'private-key');
    expect(Prefs().classicalTranslationConfig['baidu_key'], isNull);
    await tester.enterText(find.byKey(const ValueKey('baidu_appid')), '123');
    await tester.ensureVisible(
        find.byKey(const ValueKey('save-classical-credentials')));
    await tester.tap(find.byKey(const ValueKey('save-classical-credentials')));
    await tester.pumpAndSettle();
    expect(Prefs().classicalTranslationConfig['baidu_key'], 'private-key');
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('baidu_key')))
            .obscureText,
        isTrue);
    await tester.ensureVisible(
        find.byKey(const ValueKey('classical-direction-toModern')));
    await tester
        .tap(find.byKey(const ValueKey('classical-direction-toModern')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modern → Classical Chinese').last);
    await tester.pumpAndSettle();
    expect(Prefs().classicalTranslationDirection,
        ClassicalTranslationDirection.toClassical);
    expect(tester.takeException(), isNull);
  });

  testWidgets('toolbar settings persist reordering and visibility',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: ReaderTopActionsSettings()))));
    final list =
        tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    list.onReorderItem!(0, 4);
    await tester.pumpAndSettle();
    expect(ReaderTopActionsConfig.parse(Prefs().readerToolbar).order[4],
        ReaderTopAction.quickMark);
    final firstSwitch = find.byType(Switch).first;
    await tester.tap(firstSwitch);
    await tester.pumpAndSettle();
    expect(ReaderTopActionsConfig.parse(Prefs().readerToolbar).hidden,
        contains(ReaderTopAction.ai));
    expect(tester.takeException(), isNull);
  });
  testWidgets('native icon preview', (tester) async {
    final preview = Platform.environment['MODU_ICON_PREVIEW'];
    if (preview == null) return;
    await tester.runAsync(() async {
      final loader = FontLoader('Preview')
        ..addFont(File('/System/Library/Fonts/STHeiti Medium.ttc')
            .readAsBytes()
            .then((b) => ByteData.sublistView(b)));
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(File(
                '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
            .readAsBytes()
            .then((b) => ByteData.sublistView(b)));
      await icons.load();
    });
    await tester.binding.setSurfaceSize(const Size(800, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey();
    Widget panel(Brightness brightness) {
      final theme = ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff197e76), brightness: brightness),
          fontFamily: 'Preview');
      return Theme(
          data: theme,
          child: Builder(
              builder: (context) => Card(
                    color: theme.colorScheme.surface,
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(children: [
                          Text(brightness == Brightness.light ? '浅色主题' : '深色主题',
                              style: theme.textTheme.titleMedium),
                          const SizedBox(height: 18),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Column(children: [
                                  Icon(Icons.translate_outlined,
                                      size: 64,
                                      color: theme.colorScheme.onSurface),
                                  const SizedBox(height: 12),
                                  const Text('阅读翻译')
                                ]),
                                const SizedBox(width: 60),
                                Column(children: [
                                  IconTheme(
                                      data: IconThemeData(
                                          color: theme.colorScheme.onSurface),
                                      child: const ClassicalTranslationIcon(
                                          size: 64)),
                                  const SizedBox(height: 12),
                                  const Text('文言文互译')
                                ]),
                              ]),
                          const SizedBox(height: 28),
                          Text('实际工具栏尺寸 · 40% 宽度内显示',
                              style: theme.textTheme.bodySmall),
                          const SizedBox(height: 8),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                    onPressed: () {},
                                    icon: const Icon(Icons.arrow_back)),
                                const SizedBox(width: 8),
                                ReaderTopActions(readerWidth: 320, buttons: {
                                  for (final a in ReaderTopAction.values.where(
                                      (a) => a != ReaderTopAction.quickMark))
                                    a: IconButton(
                                        onPressed: () {},
                                        icon: a.icon,
                                        tooltip: a.label(context)),
                                }, actions: {
                                  for (final a in ReaderTopAction.values)
                                    a: () {}
                                }),
                              ]),
                        ])),
                  )));
    }

    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'Preview'),
        home: RepaintBoundary(
            key: key,
            child: Scaffold(
                backgroundColor: const Color(0xfff8f8f3),
                body: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      const Text('文言文翻译 · 按钮设计',
                          style: TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      const Text('直接复用普通翻译的「文」字形；「白」使用相同笔画粗细与直线风格。'),
                      const SizedBox(height: 18),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: panel(Brightness.light)),
                            Expanded(child: panel(Brightness.dark))
                          ]),
                      const SizedBox(height: 14),
                      const Text('默认：文言文 → 现代汉语　　可切换：现代汉语 → 文言文'),
                    ]))))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(preview).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
