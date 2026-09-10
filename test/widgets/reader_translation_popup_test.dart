import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/translate/ai.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/widgets/ai/ai_stream.dart';
import 'package:anx_reader/widgets/context_menu/translation_menu.dart';
import 'package:anx_reader/widgets/context_menu/translation_result.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget app(Widget home) => MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        ...GlobalMaterialLocalizations.delegates
      ],
      // Reproduce a large inherited heading without changing accessibility scaling.
      theme: ThemeData(
          textTheme: const TextTheme(headlineLarge: TextStyle(fontSize: 96))),
      home: Scaffold(body: home),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await L10n.delegate.load(const Locale('zh'));
  });

  for (final size in [
    const Size(390, 844),
    const Size(1200, 900),
    const Size(844, 390)
  ]) {
    testWidgets('AI and translation use identical popup geometry at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(Builder(
          builder: (context) => Column(children: [
                TextButton(
                    onPressed: () => showReaderPopup(context,
                        builder: (_) => const Text('AI body')),
                    child: const Text('Open AI')),
                TextButton(
                    onPressed: () => showReaderPopup(context,
                        builder: (_) => TranslationMenu(
                            content: 'word',
                            resultBuilder: (_, __) =>
                                const Text('translation'))),
                    child: const Text('Open translation')),
              ]))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open AI'));
      await tester.pumpAndSettle();
      final aiSize =
          tester.getSize(find.byKey(const ValueKey('reader-popup-body')));
      expect(aiSize.height, closeTo(size.height * 0.8, 1));
      Navigator.of(tester.element(find.text('AI body'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open translation'));
      await tester.pumpAndSettle();
      final translationSize =
          tester.getSize(find.byKey(const ValueKey('reader-popup-body')));
      expect(translationSize, aiSize);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
      'long translation scrolls in one viewport and close remains visible',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(ReaderPopup(
        child: TranslationMenu(
      content: List.filled(100, 'original').join(' '),
      resultBuilder: (_, __) => Column(children: [
        const StyledMarkdown(data: '# Translation title\n\nFirst paragraph'),
        ...List.generate(70, (i) => Text('Translated paragraph $i')),
        const Text('END OF TRANSLATION'),
      ]),
    ))));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    final source = tester.widget<Text>(
        find.byKey(const ValueKey('selection-translation-source')));
    expect(source.maxLines, 3);
    final scroll = find.byKey(const ValueKey('selection-translation-scroll'));
    final controller = tester.widget<SingleChildScrollView>(scroll).controller!;
    expect(controller.positions.length, 1);
    expect(controller.position.maxScrollExtent, greaterThan(0));
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('END OF TRANSLATION').hitTestable(), findsOneWidget);
    expect(find.byIcon(Icons.close).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'translation headings stay compact; unrelated AI theme is unchanged',
      (tester) async {
    late GptMarkdownThemeData inside;
    late double bodySize;
    late GptMarkdownThemeData outside;
    await tester.pumpWidget(app(Column(children: [
      Builder(builder: (context) {
        outside = GptMarkdownTheme.of(context);
        return const SizedBox();
      }),
      TranslationResult(child: Builder(builder: (context) {
        inside = GptMarkdownTheme.of(context);
        bodySize = DefaultTextStyle.of(context).style.fontSize!;
        return const StyledMarkdown(
            data: '# Heading\n## Heading2\n### Heading3\n\nBody');
      })),
    ])));
    await tester.pumpAndSettle();
    expect(outside.h1!.fontSize, 96);
    expect(bodySize, 16);
    expect(
        [inside.h1, inside.h2, inside.h3, inside.h4, inside.h5, inside.h6]
            .every((s) => s!.fontSize! <= 18),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'changed selection restarts once with its own context; close cancels debounce',
      (tester) async {
    final calls = <String>[];
    Widget panel(String word) => app(ReaderPopup(
            child: TranslationMenu(
          content: word,
          contextText: 'context $word',
          resultBuilder: (text, context) {
            calls.add('$text/$context');
            return Text('result $text');
          },
        )));
    await tester.pumpWidget(panel('first'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.pumpWidget(panel('second'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(calls, ['first/context first', 'second/context second']);
    expect(find.text('result first'), findsNothing);
    await tester.pumpWidget(panel('third'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(calls.length, 2);
    expect(tester.takeException(), isNull);
  });

  test('AI translation delegates scrolling to the translation viewport', () {
    final widget = AiTranslateProvider()
        .translate('hello', LangListEnum.auto, LangListEnum.english);
    expect(widget, isA<AiStream>());
    expect((widget as AiStream).scrollable, isFalse);
  });

  testWidgets('popup remains above the keyboard and inside the viewport',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(MediaQuery(
      data: const MediaQueryData(
          size: Size(390, 844),
          viewInsets: EdgeInsets.only(bottom: 300),
          padding: EdgeInsets.only(top: 24)),
      child: const ReaderPopup(child: Text('popup')),
    )));
    await tester.pumpAndSettle();
    expect(
        tester.getSize(find.byKey(const ValueKey('reader-popup-body'))).height,
        520);
    expect(tester.takeException(), isNull);
  });

  test(
      'reading toolbar puts translation after AI, with no bottom-bar duplicate',
      () {
    final source = File('lib/page/reading_page.dart').readAsStringSync();
    final actions = source.substring(source.indexOf('actions: ['),
        source.indexOf('const Spacer(),', source.indexOf('actions: [')));
    expect(actions.indexOf('aiButton'),
        lessThan(actions.indexOf("ValueKey('reader-translation-button')")));
    expect(
        RegExp('onPressed: translationHandler').allMatches(source).length, 1);
    expect(source, contains('await showReaderPopup'));
  });
}
