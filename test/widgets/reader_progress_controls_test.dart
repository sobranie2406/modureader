import 'dart:async';

import 'package:anx_reader/enums/reading_info.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/reader_progress.dart';
import 'package:anx_reader/widgets/reading_page/progress_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const position = ReaderProgress(
    percentage: .27,
    chapterTitle: '第二章',
    currentChapter: 2,
    totalChapters: 3,
    currentPage: 9,
    totalPages: 15,
    chapters: [
      ReaderProgressChapter(number: 1, title: '第一章', start: 0, end: .1),
      ReaderProgressChapter(number: 2, title: '第二章', start: .1, end: .9),
      ReaderProgressChapter(number: 3, title: '第三章', start: .9, end: 1),
    ]);

Widget app(Widget body, {double scale = 1}) => MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        ...GlobalMaterialLocalizations.delegates
      ],
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(body: Center(child: SizedBox(width: 600, child: body))),
    );

void main() {
  Finder key(String value) => find.byKey(ValueKey(value));
  final actions = <String>[];
  final seeks = <double>[];
  Widget controls(ReaderProgress progress,
          {Future<void> Function(double)? onSeek}) =>
      ReadingProgressControls(
          progress: progress,
          onSeek: onSeek ??
              (value) async {
                seeks.add(value);
              },
          onPreviousChapter: () => actions.add('previousChapter'),
          onPreviousPage: () => actions.add('previousPage'),
          onNextPage: () => actions.add('nextPage'),
          onNextChapter: () => actions.add('nextChapter'));
  setUp(() {
    actions.clear();
    seeks.clear();
  });
  Future<void> mount(WidgetTester tester, Widget body,
      {double scale = 1}) async {
    await tester.pumpWidget(app(body, scale: scale));
    await tester.pumpAndSettle();
  }

  testWidgets('chapter and page buttons call four independent reader actions',
      (tester) async {
    await mount(tester, controls(position));
    for (final name in [
      'previous-chapter',
      'previous-page',
      'next-page',
      'next-chapter'
    ]) {
      await tester.tap(key('reader-$name'));
    }
    expect(actions,
        ['previousChapter', 'previousPage', 'nextPage', 'nextChapter']);
    expect(seeks, isEmpty);
    expect(find.byTooltip('上一章'), findsOneWidget);
    expect(find.byTooltip('向前翻页'), findsOneWidget);
    expect(find.byTooltip('向后翻页'), findsOneWidget);
    expect(find.byTooltip('下一章'), findsOneWidget);
  });
  testWidgets('drag previews chapter title without navigating until release',
      (tester) async {
    await mount(tester, controls(position));
    final slider = tester.widget<Slider>(key('reader-progress-slider'));
    slider.onChangeStart!(.27);
    slider.onChanged!(.8);
    await tester.pump();
    expect(tester.widget<Text>(key('reader-progress-chapter-title')).data,
        '第二章 (2/3)');
    expect(seeks, isEmpty);
    slider.onChanged!(.95);
    await tester.pump();
    expect(tester.widget<Text>(key('reader-progress-chapter-title')).data,
        '第三章 (3/3)');
    expect(seeks, isEmpty);
    slider.onChangeEnd!(.95);
    await tester.pumpAndSettle();
    expect(seeks, [.95]);
    expect(tester.takeException(), isNull);
  });
  testWidgets('a real thumb drag previews the destination before navigating',
      (tester) async {
    await mount(tester, controls(position));
    final sliderRect = tester.getRect(key('reader-progress-slider'));
    final slider = tester.widget<Slider>(key('reader-progress-slider'));
    // Material sliders reserve a small horizontal inset around the track.
    final trackStart = sliderRect.left + 24;
    final trackWidth = sliderRect.width - 48;
    final gesture = await tester.startGesture(
        Offset(trackStart + trackWidth * slider.value, sliderRect.center.dy));
    await gesture
        .moveTo(Offset(trackStart + trackWidth * .98, sliderRect.center.dy));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<Text>(key('reader-progress-chapter-title')).data,
        '第三章 (3/3)');
    expect(seeks, isEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(seeks, hasLength(1));
    expect(seeks.single, greaterThan(.9));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'reader relocation updates thumb and chapter page counters immediately',
      (tester) async {
    final signal = ValueNotifier(position);
    addTearDown(signal.dispose);
    await mount(
        tester,
        ValueListenableBuilder<ReaderProgress>(
            valueListenable: signal,
            builder: (_, value, child) => controls(value)));
    expect(find.text('9'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    signal.value = const ReaderProgress(
        percentage: .93,
        chapterTitle: '第三章',
        currentChapter: 3,
        totalChapters: 3,
        currentPage: 2,
        totalPages: 7);
    await tester.pump();
    expect(tester.widget<Slider>(key('reader-progress-slider')).value, .93);
    expect(find.text('第三章'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('9'), findsNothing);
    expect(find.text('15'), findsNothing);
  });
  testWidgets('page/section counts remain distinct and labels are correct',
      (tester) async {
    await mount(
        tester,
        Builder(
            builder: (context) => Column(children: [
                  Text(ReadingInfoEnum.chapterProgress.getL10n(context)),
                  Text(ReadingInfoEnum.chapterPageProgress.getL10n(context)),
                  controls(position),
                ])));
    expect(find.text('章节进度'), findsOneWidget);
    expect(find.text('本章进度'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
  });
  testWidgets('an untitled chapter shows its ordinal while dragging',
      (tester) async {
    await mount(
        tester,
        controls(position.copyWithChapters([
          const ReaderProgressChapter(number: 3, title: '', start: 0, end: 1)
        ])));
    tester.widget<Slider>(key('reader-progress-slider')).onChanged!(.5);
    await tester.pump();
    expect(tester.widget<Text>(key('reader-progress-chapter-title')).data,
        '第 3 章 (3/3)');
  });
  testWidgets(
      'unloaded reader does not expose enabled navigation or false page counts',
      (tester) async {
    await mount(tester, controls(const ReaderProgress()));
    expect(
        tester.widget<Slider>(key('reader-progress-slider')).onChanged, isNull);
    expect(
        tester.widget<IconButton>(key('reader-next-page')).onPressed, isNull);
    expect(find.text('—'), findsNWidgets(2));
  });
  testWidgets(
      'leaving after a seek does not leave timers or setState after dispose',
      (tester) async {
    final completed = Completer<void>();
    await mount(tester, controls(position, onSeek: (_) => completed.future));
    tester.widget<Slider>(key('reader-progress-slider')).onChangeEnd!(.5);
    await tester.pumpWidget(const SizedBox());
    completed.complete();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('all four buttons fit a narrow screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await mount(tester, controls(position), scale: 1.5);
    for (final name in [
      'previous-chapter',
      'previous-page',
      'next-page',
      'next-chapter'
    ]) {
      expect(key('reader-$name').hitTestable(), findsOneWidget);
      expect(tester.getRect(key('reader-$name')).right, lessThanOrEqualTo(320));
    }
    expect(tester.takeException(), isNull);
  });
}
