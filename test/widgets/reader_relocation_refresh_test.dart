import 'dart:io';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/enums/reading_info.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/main.dart' show navigatorKey;
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/reading_info.dart';
import 'package:modu_reader/page/book_player/epub_player.dart';
import 'package:modu_reader/service/book_player/book_player_server.dart';
import 'package:modu_reader/utils/get_path/get_base_path.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Controller extends Fake implements InAppWebViewController {
  final handlers = <String, Function>{};
  final labels = <String>[];

  @override
  void addJavaScriptHandler(
      {required String handlerName, required Function callback}) {
    handlers[handlerName] = callback;
  }

  @override
  Future<dynamic> evaluateJavascript(
      {required String source, ContentWorld? contentWorld}) async {
    labels.add(source);
    return null;
  }
}

class _Player extends EpubPlayer {
  _Player({required super.book, required super.updateParent})
      : super(
            initialThemes: const [],
            onLoadEnd: () {},
            showOrHideAppBarAndBottomBar: (_) {});

  @override
  ConsumerState<EpubPlayer> createState() => _PlayerState();
}

class _PlayerState extends EpubPlayerState {
  int webViewBuilds = 0;

  // Exercise production reader state, metadata and bridge handlers without
  // creating an OS WebView or making requests for a real/private book.
  @override
  Widget buildWebviewWithIOSWorkaround(
      BuildContext context, String url, String initialCfi) {
    webViewBuilds++;
    return const SizedBox.expand(key: ValueKey('native-reader'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late String previousPath;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    Prefs().readingInfo = const ReadingInfoModel(
        header: ReadingInfoSectionModel(left: ReadingInfoEnum.chapterTitle),
        footer: ReadingInfoSectionModel(
            center: ReadingInfoEnum.chapterPageProgress,
            right: ReadingInfoEnum.bookProgress));
    root = await Directory.systemTemp.createTemp('modu-reader-refresh-');
    await File('${root.path}/test.epub')
        .writeAsString('synthetic test fixture');
    previousPath = documentPath;
    documentPath = root.path;
    await Server().start();
  });
  tearDown(() async {
    await Server().stop();
    documentPath = previousPath;
    await root.delete(recursive: true);
  });

  testWidgets(
      'page/chapter relocation updates footer without rebuilding WebView',
      (tester) async {
    final controller = _Controller();
    final bookmarks = <bool>[];
    late _PlayerState state;
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      navigatorKey: navigatorKey,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: _Player(
        book: Book.mock()..filePath = 'test.epub',
        updateParent: () => bookmarks.add(state.bookmarkExists),
      ),
    )));
    await tester.pumpAndSettle();
    state = tester.state<_PlayerState>(find.byType(_Player));
    await state.setHandler(controller);
    final builds = state.webViewBuilds;
    for (var page = 1; page <= 40; page++) {
      controller.handlers['onRelocated']!([
        {
          'cfi': 'page-$page',
          'percentage': page / 100,
          'chapterTitle': page <= 20 ? 'First chapter' : 'Second chapter',
          'chapterHref': page <= 20 ? 'first.xhtml' : 'second.xhtml',
          'chapterCurrentPage': (page - 1) % 20 + 1,
          'chapterTotalPages': 20,
          'currentChapter': page <= 20 ? 1 : 2,
          'totalChapters': 5,
          'bookCurrentPage': page - 1,
          'bookTotalPages': 100,
          'writingMode': 'horizontal-tb',
          'bookmark': {'exists': page.isEven, 'cfi': 'page-$page'},
          'readingAction': false,
        }
      ]);
      await tester.pump();
      expect(find.text(page <= 20 ? 'First chapter' : 'Second chapter'),
          findsOneWidget);
      expect(find.text('${(page - 1) % 20 + 1}/20'), findsOneWidget);
      expect(find.text('${page.toStringAsFixed(2)}%'), findsOneWidget);
      expect(state.webViewBuilds, builds);
      expect(bookmarks.last, page.isEven);
    }
    expect(state.readingProgress.value.currentChapter, 2);
    expect(state.bookTotalPages, 100);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
