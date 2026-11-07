import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/page/settings_page/appearance.dart';
import 'package:anx_reader/page/settings_page/weread_settings.dart';
import 'package:anx_reader/service/weread/weread_api.dart';
import 'package:anx_reader/service/weread/weread_store.dart';
import 'package:anx_reader/widgets/weread/weread_book_card.dart';
import 'package:anx_reader/widgets/weread/weread_link_page.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/book_detail_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryWereadStore extends WereadStore {
  MemoryWereadStore() : super('test');
  Map<String, dynamic> data = WereadData.empty();
  int binds = 0;
  @override
  Future<Map<String, dynamic>> read() async => data;
  @override
  Future<Map<String, dynamic>> bind(Map<String, dynamic>? info) async {
    binds++;
    final stamp = WereadData.stamp(
        [if (WereadData.revision(data) case final String s) s]);
    return data = WereadData.normalize({
      'version': 1,
      'binding': {'bookId': info?['bookId'], 'stamp': stamp},
      'sections': {
        if (info != null) 'info': {'stamp': stamp, 'data': info}
      },
    });
  }

  @override
  Future<Map<String, dynamic>> saveSection(String expectedRevision, String name,
      Map<String, dynamic> content) async {
    if (WereadData.revision(data) != expectedRevision) return data;
    return data = WereadData.normalize({
      ...data,
      'sections': {
        ...wereadMap(data['sections']),
        name: {
          'stamp': WereadData.stamp([expectedRevision]),
          'data': content
        }
      },
    });
  }
}

class FakeWereadApi extends WereadApi {
  FakeWereadApi() : super('wrk-test');
  int searches = 0,
      infos = 0,
      reviewCalls = 0,
      highlightCalls = 0,
      coverCalls = 0;
  Completer<Map<String, dynamic>>? pendingInfo, pendingHighlights;
  bool failHighlights = false, emptyHighlights = false, failCover = false;
  bool fail = false;
  final details = <String, dynamic>{
    'bookId': 'w1',
    'title': 'Candidate',
    'author': 'Author',
    'isbn': '9781234567890',
    'translator': 'Translator',
    'publisher': 'Publisher',
    'publishTime': '2020-01-01',
    'intro': 'External description',
    'newRating': 75.4,
    'newRatingCount': 1454,
  };
  @override
  Future<WereadSearchPage> search(String title, String author,
      {int cursor = 0}) async {
    searches++;
    expect(title, 'Local title');
    expect(author, 'Author');
    return WereadSearchPage([details], false, 1);
  }

  @override
  Future<Map<String, dynamic>> info(String id) async {
    infos++;
    if (pendingInfo != null) return pendingInfo!.future;
    if (fail) throw const WereadException('network');
    return {...details};
  }

  @override
  Future<Map<String, dynamic>> reviews(String id,
      {int cursor = 0, int synckey = 0}) async {
    reviewCalls++;
    return {
      'items': [
        {'id': 'r', 'content': 'Public review', 'author': 'Reader', 'star': 100}
      ],
      'total': 1,
      'hasMore': false,
      'maxIdx': 1,
      'synckey': 1
    };
  }

  @override
  Future<Map<String, dynamic>> highlights(String id) async {
    highlightCalls++;
    if (pendingHighlights != null) return pendingHighlights!.future;
    if (failHighlights) throw const WereadException('network');
    return {
      'items': emptyHighlights
          ? []
          : [
              {'text': 'A highlight', 'count': 8}
            ]
    };
  }

  @override
  Future<Uint8List> cover(String url) async {
    coverCalls++;
    if (failCover) throw const WereadException('network');
    return base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4AWMAAQAABQABDQottAAAAABJRU5ErkJggg==');
  }
}

Widget app(Widget body) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: body);

void main() {
  setUpAll(() async {
    await L10n.delegate.load(const Locale('en'));
    await L10n.delegate.load(const Locale('zh', 'CN'));
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'wereadEnabled': true, 'wereadApiKey': 'wrk-test'});
    await Prefs().initPrefs();
  });

  Future<void> size(WidgetTester tester, {double width = 440}) async {
    tester.view.physicalSize = Size(width, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('WeRead settings follow cover and precede bottom navigation',
      (tester) async {
    await size(tester);
    await tester.pumpWidget(app(const Scaffold(body: AppearanceSetting())));
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView).first);
    final delegate = list.childrenDelegate as SliverChildBuilderDelegate;
    final context = tester.element(find.byType(AppearanceSetting));
    final titles = [
      for (var i = 0; i < delegate.childCount!; i++)
        ((delegate.builder(context, i) as SettingsSection).title as Text).data,
    ];
    final index = titles.indexOf('Book information');
    expect(index, greaterThan(0));
    expect(titles[index - 1], L10n.of(context).settingsBookshelfCover);
    expect(titles[index + 1],
        L10n.of(context).settingsAppearanceBottomNavigatorShow);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WeRead guidance stays in help on a narrow large-text screen',
      (tester) async {
    await size(tester, width: 320);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!),
      home: const WereadSettingsPage(),
    ));
    await tester.pumpAndSettle();
    const hint = '保存 API Key 后，关联书籍即可查看评分和书评。';
    expect(find.text(hint), findsNothing);
    expect(find.textContaining('所有参与密钥同步的设备'), findsNothing);
    expect(find.textContaining('不上传本地正文'), findsNothing);
    await tester.tap(find.byIcon(Icons.help_outline).first);
    await tester.pumpAndSettle();
    expect(find.text(hint), findsOneWidget);
    expect(Prefs().wereadEnabled, true);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text(hint), findsNothing);
    expect(find.text('保存 API Key'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('masked key, local enable switch and clearable credentials',
      (tester) async {
    await size(tester);
    await tester.pumpWidget(app(const WereadSettingsPage()));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, true);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Save API Key'));
    await tester.pumpAndSettle();
    expect(Prefs().wereadApiKey, '');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(Prefs().wereadEnabled, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search is explicit; candidate requires edition confirmation',
      (tester) async {
    await size(tester);
    final api = FakeWereadApi();
    Map<String, dynamic>? selected;
    await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
            body: TextButton(
                onPressed: () async {
                  selected = await Navigator.push(
                      context,
                      MaterialPageRoute<Map<String, dynamic>>(
                          builder: (_) => WereadLinkPage(
                              title: 'Local title',
                              author: 'Author',
                              apiFactory: (_) => api)));
                },
                child: const Text('Open'))))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(api.searches, 0);
    await tester.tap(find.text('Search books'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Candidate'));
    await tester.pumpAndSettle();
    expect(find.text('ISBN'), findsOneWidget);
    expect(find.text('9781234567890'), findsOneWidget);
    expect(find.text('Translator'), findsNWidgets(2));
    expect(selected, null);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(selected, null);
    await tester.tap(find.text('Candidate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(selected?['bookId'], 'w1');
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 1000.0]) {
    testWidgets(
        'cached detail on $width width does not call network; adoption needs confirmation',
        (tester) async {
      await size(tester, width: width);
      final store = MemoryWereadStore(), api = FakeWereadApi();
      await store.bind(api.details);
      String? adopted;
      await tester.pumpWidget(app(Scaffold(
          body: SingleChildScrollView(
              child: WereadBookCard(
        book: Book.mock(),
        store: store,
        apiFactory: (_) => api,
        onAdopt: ({String? description, Uint8List? cover}) async {
          adopted = description;
        },
      )))));
      await tester.pumpAndSettle();
      expect(api.infos, 0);
      expect(api.reviewCalls, 0);
      expect(find.text('75.4%'), findsOneWidget);
      final theme = Theme.of(tester.element(find.byType(WereadBookCard)));
      expect(
          tester.widget<Text>(find.text('Candidate')).style,
          BookDetailTypography.title(
              tester.element(find.byType(WereadBookCard))));
      expect(
          tester.widget<Text>(find.text('Author')).style,
          BookDetailTypography.author(
              tester.element(find.byType(WereadBookCard))));
      for (final title in [
        'WeRead · External information',
        'WeRead rating',
        'Description',
        'Reader reviews',
        'Popular highlights',
      ]) {
        expect(tester.widget<Text>(find.text(title)).style,
            theme.textTheme.titleMedium);
      }
      final publication = tester.widget<SelectableText>(find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText && widget.data == '9781234567890'));
      expect(publication.style, theme.textTheme.bodyMedium);
      expect(
          tester
              .widget<SelectableText>(find.byWidgetPredicate((widget) =>
                  widget is SelectableText &&
                  widget.data == 'External description'))
              .style,
          theme.textTheme.bodyMedium);
      await tester.ensureVisible(find.text('Use this description'));
      await tester.tap(find.text('Use this description'));
      await tester.pumpAndSettle();
      expect(adopted, null);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(adopted, null);
      await tester.tap(find.text('Use this description'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(adopted, 'External description');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'large text, dark and e-ink layouts retain public reviews and highlights',
      (tester) async {
    await size(tester, width: 320);
    final store = MemoryWereadStore(), api = FakeWereadApi();
    await store.bind({
      ...api.details,
      'newRatingDetail': {'good': 86, 'fair': 14, 'poor': 1},
      'wordCount': 364000,
    });
    await store.saveSection(
        WereadData.revision(store.data)!, 'reviews', await api.reviews('w1'));
    await store.saveSection(WereadData.revision(store.data)!, 'highlights', {
      'items': [
        {'text': 'A saved highlight', 'count': 8}
      ]
    });
    for (final eink in [false, true]) {
      Prefs().eInkMode = eink;
      await tester.pumpWidget(app(Theme(
        data: ThemeData(brightness: Brightness.dark),
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: WereadBookCard(
                key: ValueKey(eink),
                book: Book.mock(),
                store: store,
                onAdopt: ({String? description, Uint8List? cover}) async {},
              ),
            ),
          ),
        ),
      )));
      await tester.pumpAndSettle();
      for (final title in ['Popular highlights', 'Reader reviews']) {
        await tester.ensureVisible(find.text(title));
        await tester.pumpAndSettle();
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
      }
      expect(find.text('Public review'), findsOneWidget);
      expect(find.text('A saved highlight'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'failed refresh preserves cache; turning off ignores late network response',
      (tester) async {
    await size(tester);
    final store = MemoryWereadStore(), api = FakeWereadApi();
    await store.bind(api.details);
    await tester.pumpWidget(app(Scaffold(
        body: SingleChildScrollView(
            child: WereadBookCard(
      book: Book.mock(),
      store: store,
      apiFactory: (_) => api,
      onAdopt: ({String? description, Uint8List? cover}) async {},
    )))));
    await tester.pumpAndSettle();
    api.fail = true;
    await tester.tap(find.text('Refresh book information'));
    await tester.pumpAndSettle();
    expect(find.textContaining('WeRead information is unavailable'),
        findsOneWidget);
    expect(WereadData.content(store.data, 'info')['title'], 'Candidate');
    api.pendingInfo = Completer();
    await tester.tap(find.text('Refresh book information'));
    await tester.pump();
    await Prefs().saveWereadSettings(enabled: false);
    await tester.pump();
    api.pendingInfo!.complete({...api.details, 'title': 'Late response'});
    await tester.pumpAndSettle();
    expect(WereadData.content(store.data, 'info')['title'], 'Candidate');
    expect(find.text('WeRead rating'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  Future<void> showCard(
      WidgetTester tester, MemoryWereadStore store, FakeWereadApi api) async {
    await tester.pumpWidget(app(Scaffold(
      body: SingleChildScrollView(
        child: WereadBookCard(
          book: Book.mock(),
          store: store,
          apiFactory: (_) => api,
          onAdopt: ({String? description, Uint8List? cover}) async {},
        ),
      ),
    )));
    await tester.pumpAndSettle();
  }

  Future<void> toggle(WidgetTester tester, String title) async {
    await tester.ensureVisible(find.text(title));
    await tester.pumpAndSettle();
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  testWidgets('expanding queues both sections once and reuses cached results',
      (tester) async {
    await size(tester);
    final store = MemoryWereadStore(), api = FakeWereadApi();
    await store.bind(api.details);
    await showCard(tester, store, api);
    expect(api.highlightCalls + api.reviewCalls, 0);
    api.pendingHighlights = Completer();
    await toggle(tester, 'Popular highlights');
    await toggle(tester, 'Reader reviews');
    await toggle(tester, 'Popular highlights');
    await toggle(tester, 'Popular highlights');
    expect(api.highlightCalls, 1);
    expect(api.reviewCalls, 0);
    api.pendingHighlights!.complete({
      'items': [
        {'text': 'A highlight', 'count': 8}
      ]
    });
    await tester.pumpAndSettle();
    expect(api.reviewCalls, 1);
    expect(find.text('Public review'), findsOneWidget);
    expect(find.text('A highlight'), findsOneWidget);
    for (final name in ['Popular highlights', 'Reader reviews']) {
      await toggle(tester, name);
      await toggle(tester, name);
    }
    expect(api.highlightCalls, 1);
    expect(api.reviewCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed expansion retries on reopen; empty results are cached',
      (tester) async {
    await size(tester);
    final store = MemoryWereadStore(), api = FakeWereadApi();
    await store.bind(api.details);
    await showCard(tester, store, api);
    api.failHighlights = true;
    await toggle(tester, 'Popular highlights');
    expect(api.highlightCalls, 1);
    expect(WereadData.content(store.data, 'highlights'), isEmpty);
    api.failHighlights = false;
    api.emptyHighlights = true;
    await toggle(tester, 'Popular highlights');
    await toggle(tester, 'Popular highlights');
    expect(api.highlightCalls, 2);
    expect(find.text('No entries'), findsOneWidget);
    await toggle(tester, 'Popular highlights');
    await toggle(tester, 'Popular highlights');
    expect(api.highlightCalls, 2);
  });

  testWidgets('disable drops queued loads and ignores late responses',
      (tester) async {
    await size(tester);
    final store = MemoryWereadStore(), api = FakeWereadApi();
    await store.bind(api.details);
    await showCard(tester, store, api);
    api.pendingHighlights = Completer();
    await toggle(tester, 'Popular highlights');
    await toggle(tester, 'Reader reviews');
    await Prefs().saveWereadSettings(enabled: false);
    await tester.pumpAndSettle();
    api.pendingHighlights!.complete({'items': []});
    await tester.pumpAndSettle();
    expect(api.reviewCalls, 0);
    expect(WereadData.content(store.data, 'highlights'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('old missing-rating cache refreshes automatically once',
      (tester) async {
    await size(tester);
    final store = MemoryWereadStore(), api = FakeWereadApi();
    await store.bind({...api.details}..remove('newRating'));
    await showCard(tester, store, api);
    expect(api.infos, 1);
    expect(find.text('75.4%'), findsOneWidget);
    expect(WereadData.content(store.data, 'info')['newRating'], 75.4);
    await toggle(tester, 'Popular highlights');
    expect(api.infos, 1);
  });

  testWidgets(
      'failed cache repair and cover do not retry on rebuild or lose data',
      (tester) async {
    await size(tester);
    final store = MemoryWereadStore(), api = FakeWereadApi();
    api.fail = true;
    api.failCover = true;
    await store.bind({
      ...api.details,
      'cover': 'https://cdn.weread.qq.com/cover.jpg',
    }..remove('newRating'));
    await showCard(tester, store, api);
    expect(api.infos, 1);
    expect(api.coverCalls, 1);
    expect(find.text('Rating not provided'), findsOneWidget);
    expect(find.text('External description'), findsOneWidget);
    await toggle(tester, 'Reader reviews');
    expect(api.infos, 1);
    expect(api.coverCalls, 1);
    expect(WereadData.content(store.data, 'info')['title'], 'Candidate');
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1000.0]) {
    testWidgets(
        'cover, default description, distribution and publication at $width',
        (tester) async {
      await size(tester, width: width);
      final store = MemoryWereadStore(), api = FakeWereadApi();
      await store.bind({
        ...api.details,
        'cover': 'https://cdn.weread.qq.com/cover.jpg',
        'newRating': 83.6,
        'newRatingCount': 101,
        'newRatingDetail': {'good': 86, 'fair': 14, 'poor': 1},
        'wordCount': 364000,
      });
      await showCard(tester, store, api);
      expect(find.byType(Image), findsOneWidget);
      expect(api.coverCalls, 1);
      expect(api.infos, 0);
      expect(find.text('83.6%'), findsOneWidget);
      expect(find.text('Recommended (86)'), findsOneWidget);
      expect(find.text('Fair (14)'), findsOneWidget);
      expect(find.text('Not recommended (1)'), findsOneWidget);
      expect(find.text('Word count: 364000'), findsOneWidget);
      expect(find.text('External description'), findsOneWidget);
      expect(find.text('Publication details'), findsOneWidget);
      final bars = tester
          .widgetList<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator))
          .map((bar) => bar.value)
          .toList();
      expect(bars, [86 / 101, 14 / 101, 1 / 101]);
      final title = tester.getRect(find.text('Candidate'));
      final description = tester.getRect(find.text('Description'));
      if (width > 760) {
        expect(description.left, greaterThan(title.right));
      } else {
        expect(description.top, greaterThan(title.bottom));
      }
      await toggle(tester, 'Reader reviews');
      expect(api.coverCalls, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
