import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/statistic_data_model.dart';
import 'package:anx_reader/providers/book_daily_reading_provider.dart';
import 'package:anx_reader/providers/last_read_book_provider.dart';
import 'package:anx_reader/providers/reading_insights.dart';
import 'package:anx_reader/providers/statistic_data.dart';
import 'package:anx_reader/service/statistic/reading_insights.dart';
import 'package:anx_reader/main.dart' show navigatorKey;
import 'package:anx_reader/page/home_page/statistics_page.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/bookshelf/book_item.dart';
import 'package:anx_reader/widgets/page_router/reader_cover_hero.dart';
import 'package:anx_reader/widgets/page_router/reading_route.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:anx_reader/widgets/statistic/reading_history_book_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Access extends ReadingHistoryBookAccess {
  Book? current;
  Book? opened;
  int calls = 0;
  Completer<void>? pending;
  bool fail = false;
  bool showReader = false;
  String? openedHeroTag;

  @override
  Future<Book?> load(int id) async {
    if (fail) throw Exception('offline database');
    return current;
  }

  @override
  Future<void> open(WidgetRef ref, BuildContext context, Book book,
      {required String heroTag}) async {
    calls++;
    opened = book;
    openedHeroTag = heroTag;
    if (showReader) {
      await Navigator.of(context).push(readingRoute<void>(
        animate: Prefs().openBookAnimation,
        builder: (_) => ReaderCoverHero(
          tag: heroTag,
          cover: const Text('flying history cover'),
          child: const Scaffold(body: Text('reader body')),
        ),
      ));
    }
    await pending?.future;
  }
}

class _LastRead extends LastReadBook {
  _LastRead(this.book);
  final Book book;
  @override
  Future<LastReadBookData?> build() async => LastReadBookData(book: book);
}

class _Statistics extends StatisticData {
  _Statistics(this.book);
  final Book book;
  @override
  Future<StatisticDataModel> build() async =>
      StatisticDataModel.mock().copyWith(bookReadingTime: [
        {book: 120}
      ]);
}

class _DailyReading extends BookDailyReading {
  @override
  Future<BookDailyReadingData> build(
          {required int bookId, int days = 30}) async =>
      BookDailyReadingData.mock();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await L10n.delegate.load(const Locale('en'));
    await L10n.delegate.load(const Locale('zh'));
  });

  Widget app(Widget child,
          {Locale locale = const Locale('en'),
          _Access? access,
          Book? dashboardBook}) =>
      ProviderScope(
        overrides: [
          if (access != null)
            readingHistoryBookAccessProvider.overrideWithValue(access),
          if (dashboardBook != null) ...[
            lastReadBookProvider.overrideWith(() => _LastRead(dashboardBook)),
            statisticDataProvider
                .overrideWith(() => _Statistics(dashboardBook)),
            bookDailyReadingProvider(bookId: dashboardBook.id)
                .overrideWith(_DailyReading.new),
            readingInsightsProvider.overrideWith((ref) async => ReadingInsights(
                  recent: [
                    ReadingInsightBook(dashboardBook,
                        lastDay: DateTime(2026, 10, 9))
                  ],
                  mostAnnotated: [
                    ReadingInsightBook(dashboardBook, noteCount: 2)
                  ],
                )),
          ],
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: locale,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(body: child),
        ),
      );

  Book fixture() => Book.mock()
    ..coverPath = 'missing-history-cover.png'
    ..filePath = 'file/history.epub';

  for (final type in [
    null,
    StatisticsDashboardTileType.continueReading,
    StatisticsDashboardTileType.topBook,
    StatisticsDashboardTileType.recentReading,
    StatisticsDashboardTileType.mostAnnotatedBooks,
  ]) {
    testWidgets('title and cover fly to/from the reader: $type',
        (tester) async {
      final book = fixture();
      final access = _Access()
        ..current = book
        ..showReader = true;
      await tester.pumpWidget(app(
        SizedBox(
            height: 300,
            child: type == null
                ? BookStatisticItem(book: book, readingTime: 120)
                : Consumer(
                    builder: (context, ref, _) => dashboardTileRegistry[type]!
                        .buildContent(context, ref))),
        access: access,
        dashboardBook: book,
      ));
      await tester.pumpAndSettle();
      final tag = tester.widget<Hero>(find.byType(Hero)).tag;
      for (final tapTitle in [true, false]) {
        await tester.tap(
            tapTitle ? find.text(book.title).last : find.byType(BookCover));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(access.openedHeroTag, tag);
        expect(find.text('flying history cover'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.text('reader body'), findsOneWidget);
        navigatorKey.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('flying history cover'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.byType(BookCover), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
        variant: TargetPlatformVariant(
            {TargetPlatform.android, TargetPlatform.iOS}));
  }

  testWidgets('title and cover open the current book, preserving its position',
      (tester) async {
    final stale = fixture()..lastReadPosition = 'old-position';
    final current = fixture()..lastReadPosition = 'latest-position';
    final access = _Access()..current = current;
    await tester.pumpWidget(
        app(BookStatisticItem(book: stale, readingTime: 120), access: access));
    await tester.pumpAndSettle();
    await tester.tap(find.text(stale.title).last);
    await tester.pump();
    expect(access.opened, same(current));
    expect(access.opened!.lastReadPosition, 'latest-position');
    await tester.tap(find.byType(BookCover));
    await tester.pump();
    expect(access.calls, 2);
    expect(tester.takeException(), isNull);
  });

  for (final missing in [false, true]) {
    testWidgets(
        'deleted or missing books keep history without opening ($missing)',
        (tester) async {
      final book = fixture()..isDeleted = !missing;
      final access = _Access()..current = missing ? null : book;
      await tester.pumpWidget(
          app(BookStatisticItem(book: book, readingTime: 120), access: access));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BookCover));
      await tester.pumpAndSettle();
      expect(access.calls, 0);
      expect(find.text(book.title), findsWidgets);
      expect(find.text('Book deleted'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('deletion after history loaded is checked on tap',
      (tester) async {
    final access = _Access()..current = (fixture()..isDeleted = true);
    await tester.pumpWidget(app(
        BookStatisticItem(book: fixture(), readingTime: 120),
        access: access));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BookCover));
    await tester.pumpAndSettle();
    expect(access.calls, 0);
    expect(find.text('Book deleted'), findsOneWidget);
  });

  testWidgets(
      'repeated taps do not open duplicate readers; lookup errors can retry',
      (tester) async {
    final access = _Access()
      ..current = fixture()
      ..fail = true;
    await tester.pumpWidget(app(
        BookStatisticItem(book: fixture(), readingTime: 120),
        access: access));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BookCover));
    await tester.pumpAndSettle();
    expect(find.text('Error · Retry'), findsOneWidget);
    access.fail = false;
    access.pending = Completer<void>();
    await tester.tap(find.byType(BookCover));
    await tester.pump();
    await tester.tap(find.byType(BookCover));
    await tester.pump();
    expect(access.calls, 1);
    access.pending!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('English index badges contain no hardcoded Chinese in any state',
      (tester) async {
    for (final status in [null, ...BookKnowledgeQueueStatus.values]) {
      await tester.pumpWidget(app(KnowledgeStatusBadge(
        indexed: true,
        item: status == null
            ? null
            : BookKnowledgeQueueItem(
                book: fixture(),
                status: status,
                requestedAt: DateTime(2026),
                completed: 1,
                total: 2,
              ),
      )));
      await tester.pumpAndSettle();
      final label = tester
          .widget<Text>(find.descendant(
              of: find.byType(KnowledgeStatusBadge),
              matching: find.byType(Text)))
          .data!;
      expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(label), false,
          reason: '$status: $label');
      if (status == null) expect(label, 'Indexed');
    }
  });

  testWidgets(
      'navigation label and indexed badge follow Chinese/English locale',
      (tester) async {
    for (final language in ['en', 'zh']) {
      await tester.pumpWidget(app(
          Builder(
              builder: (context) => Column(children: [
                    Text(L10n.of(context).navBarStatistics),
                    const KnowledgeStatusBadge(indexed: true, item: null),
                  ])),
          locale: Locale(language)));
      await tester.pumpAndSettle();
      expect(find.text(language == 'zh' ? '阅读历史' : 'Reading History'),
          findsOneWidget);
      expect(find.text(language == 'zh' ? '已索引' : 'Indexed'), findsOneWidget);
    }
  });
}
