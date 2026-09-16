import 'dart:io';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/search_result_model.dart';
import 'package:anx_reader/providers/toc_search.dart';
import 'package:anx_reader/widgets/reading_page/book_search.dart';
import 'package:anx_reader/widgets/reading_page/search_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

SearchResultModel group(int first, int count) => SearchResultModel(
    label: 'Chapter $first',
    cfi: 'chapter-$first',
    subitems: List.generate(
        count,
        (i) => SearchResultSubitemModel(
            cfi: 'hit-${first + i}',
            pre: 'Before ',
            match: 'word ${first + i}',
            post: ' after')));

Widget app(Widget child, {ProviderContainer? container}) {
  final material = MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      home: Scaffold(body: child));
  return container == null
      ? ProviderScope(child: material)
      : UncontrolledProviderScope(container: container, child: material);
}

void main() {
  for (final viewport in [
    const Size(1200, 800),
    const Size(390, 800),
    const Size(800, 360)
  ]) {
    testWidgets(
        'floating search handles results, dismissal and keyboard at $viewport',
        (tester) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(tocSearchProvider.notifier);
      final targets = <String>[];
      await tester.pumpWidget(app(
          Builder(
              builder: (context) => TextButton(
                    onPressed: () => showBookSearchDialog(
                      context,
                      onSearch: (query) =>
                          notifier.start(query, originCfi: 'origin'),
                      onClear: notifier.clear,
                      onNavigate: (cfi) async {
                        targets.add(cfi);
                      },
                    ),
                    child: const Text('Open search'),
                  )),
          container: container));
      await tester.pumpAndSettle();
      Future<void> open() async {
        await tester.tap(find.text('Open search'));
        await tester.pumpAndSettle();
      }

      await open();
      expect(find.byType(Dialog), findsOneWidget);
      expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isTrue);
      expect(tester.getSize(find.byType(BookSearch)).width,
          lessThanOrEqualTo(680));
      if (viewport.width < 1000) {
        tester.view.viewInsets =
            FakeViewPadding(bottom: viewport.height > 500 ? 320 : 180);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.enterText(
          find.byKey(const ValueKey('book-search-query')), 'word');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      notifier.addResult(group(1, 2));
      notifier.updateProgress(1);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(targets, isEmpty);
      expect(container.read(tocSearchProvider).activeIndex, -1);
      expect(container.read(tocSearchProvider).originCfi, 'origin');
      // Dismiss an unselected search without issuing any reader navigation.
      await tester.tap(find.byKey(const ValueKey('book-search-close')));
      await tester.pumpAndSettle();
      expect(targets, isEmpty);
      await open();
      final result = find.text('Before word 1 after', findRichText: true);
      await tester.ensureVisible(result);
      await tester.pumpAndSettle();
      await tester.tap(result);
      await tester.pumpAndSettle();
      expect(targets, ['hit-1']);
      expect(find.byType(Dialog), findsNothing);
      expect(container.read(tocSearchProvider).isActive, isTrue);
      await open();
      expect(
          tester
              .widget<TextField>(
                  find.byKey(const ValueKey('book-search-query')))
              .controller!
              .text,
          'word');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await open();
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(container.read(tocSearchProvider).originCfi, 'origin');
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets('toolbar counts matches, not chapters, at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = <String>[];
      final state = TocSearchState(
          query: 'word',
          results: [group(1, 8), group(9, 8)],
          activeCfi: 'hit-9',
          originCfi: 'origin');
      await tester.pumpWidget(app(Align(
          alignment: Alignment.bottomCenter,
          child: SearchNavigationBar(
              state: state,
              onSearch: () => events.add('search'),
              onPrevious: () => events.add('previous'),
              onNext: () => events.add('next'),
              onReturn: () => events.add('return'),
              onClose: () => events.add('close')))));
      await tester.pumpAndSettle();
      expect(find.text('9/16'), findsOneWidget);
      for (final action in ['previous', 'next', 'return', 'close', 'search']) {
        await tester.tap(find.byKey(ValueKey('search-nav-$action')));
      }
      expect(events, ['previous', 'next', 'return', 'close', 'search']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('first/last boundaries and streaming count are explicit',
      (tester) async {
    Future<void> render(String cfi, bool searching) =>
        tester.pumpWidget(app(SearchNavigationBar(
            state: TocSearchState(
                query: 'word',
                results: [group(1, 2)],
                activeCfi: cfi,
                isSearching: searching),
            onSearch: () {},
            onPrevious: () {},
            onNext: () {},
            onReturn: () {},
            onClose: () {})));
    await render('hit-1', true);
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('搜索中…'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(
                find.byKey(const ValueKey('search-nav-previous')))
            .onPressed,
        isNull);
    await render('hit-2', false);
    await tester.pumpAndSettle();
    expect(find.text('2/2'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('search-nav-next')))
            .onPressed,
        isNull);
    expect(find.text('搜索中…'), findsNothing);
  });

  testWidgets(
      'search submits, streams without erasing draft, navigates and clears',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(tocSearchProvider.notifier);
    final queries = <String>[], targets = <String>[];
    var closed = false;
    await tester.pumpWidget(app(
        BookSearch(
            onSearch: (q) {
              queries.add(q);
              notifier.start(q, originCfi: 'origin');
            },
            onClear: notifier.clear,
            onNavigate: targets.add,
            onClose: () {
              closed = true;
            }),
        container: container));
    await tester.pumpAndSettle();
    final query = find.byKey(const ValueKey('book-search-query'));
    await tester.enterText(query, '  word  ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(queries, ['word']);
    notifier.addResult(group(1, 2));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(query, 'unfinished draft');
    notifier.updateProgress(0.5);
    await tester.pump();
    expect(
        tester.widget<TextField>(query).controller!.text, 'unfinished draft');
    notifier.updateProgress(1);
    await tester.pumpAndSettle();
    expect(targets, isEmpty);
    expect(container.read(tocSearchProvider).activeCfi, isNull);
    await tester.tap(find.text('Before word 2 after', findRichText: true));
    expect(targets, ['hit-2']);
    await tester.tap(find.byKey(const ValueKey('book-search-clear')));
    await tester.pumpAndSettle();
    expect(container.read(tocSearchProvider).isActive, isFalse);
    expect(tester.widget<TextField>(query).controller!.text, '');
    await tester.tap(find.byKey(const ValueKey('book-search-close')));
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  test(
      'reader exposes translation/search/bookmark in order and directory no longer embeds search',
      () {
    final page = File('lib/page/reading_page.dart').readAsStringSync();
    expect(page.indexOf("ValueKey('reader-translation-button')"),
        lessThan(page.indexOf("ValueKey('reader-search-button')")));
    expect(page.indexOf("ValueKey('reader-search-button')"),
        lessThan(page.indexOf("ValueKey('reader-bookmark-button')")));
    final toc = File('lib/widgets/reading_page/widgets/book_toc.dart')
        .readAsStringSync();
    expect(toc, isNot(contains('SearchBar(')));
    expect(toc, isNot(contains('tocSearchProvider')));
  });

  test(
      'new queries preserve origin; closing invalidates pending request and clears navigation',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(tocSearchProvider.notifier);
    notifier.start('first', originCfi: 'origin');
    notifier.addResult(group(1, 16));
    notifier.selectMatch('hit-9');
    expect(container.read(tocSearchProvider).activeIndex, 8);
    final oldRequest = container.read(tocSearchProvider).requestId;
    notifier.start('second', originCfi: 'hit-9');
    expect(container.read(tocSearchProvider).originCfi, 'origin');
    expect(
        container.read(tocSearchProvider).requestId, greaterThan(oldRequest));
    notifier.clear();
    final cleared = container.read(tocSearchProvider);
    expect(cleared.isActive, isFalse);
    expect(cleared.originCfi, isNull);
    expect(cleared.activeIndex, -1);
    expect(cleared.matches, isEmpty);
  });
}
