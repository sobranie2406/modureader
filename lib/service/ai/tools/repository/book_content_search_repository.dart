import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/knowledge/book_source_fingerprint.dart';
import 'package:anx_reader/page/home_page.dart';
import 'package:anx_reader/service/ai/tools/input/book_content_search_input.dart';
import 'package:anx_reader/service/ai/tools/repository/books_repository.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/webView/gererate_url.dart';
import 'package:anx_reader/utils/webView/webview_console_message.dart';
import 'package:anx_reader/utils/webView/anx_headless_webview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

typedef BookChapterExtractionProgress = void Function(
  String chapterId,
  int completed,
  int total,
);

class BookContentSearchRepository {
  BookContentSearchRepository({
    BooksRepository? booksRepository,
    Duration? searchTimeout,
    Duration? sessionIdleTimeout,
  })  : _booksRepository = booksRepository ?? const BooksRepository(),
        _searchTimeout = searchTimeout ?? const Duration(seconds: 15),
        _sessionIdleTimeout = sessionIdleTimeout ?? const Duration(minutes: 3);

  final BooksRepository _booksRepository;
  final Duration _searchTimeout;
  final Duration _sessionIdleTimeout;

  final Map<int, _HeadlessSearchSession> _sessions = {};

  /// Extracts all readable chapters through the same Foliate reader used by
  /// normal reading, without navigating away from the bookshelf.
  Future<Map<String, String>> extractChaptersForIndex(
    Book book, {
    BookChapterExtractionProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (book.id <= 0 || book.isDeleted) {
      throw StateError('Book is not available for indexing.');
    }
    if (!await File(book.fileFullPath).exists()) {
      throw StateError('The local book file is not available.');
    }

    final session = await _getOrCreateSession(book);
    try {
      return await session.extractChapters(
        onProgress: onProgress,
        timeout: _searchTimeout,
        isCancelled: isCancelled,
      );
    } finally {
      if (session.isActive) {
        session.scheduleDispose(_sessionIdleTimeout);
      } else {
        _sessions.remove(book.id);
      }
    }
  }

  Future<Map<String, dynamic>> search(BookContentSearchInput input) async {
    final keyword = input.keyword.trim();
    if (keyword.isEmpty) {
      throw ArgumentError('keyword must not be empty');
    }

    final book = await _resolveBook(input.bookId);
    AnxLog.info(
        'BookContentSearchRepository: Starting search for book=${book.id}, keyword="$keyword"');

    final session = await _getOrCreateSession(book);

    try {
      final response = await session
          .runSearch(
            keyword: keyword,
            maxResults: input.resolvedMaxResults(),
            maxSnippets: input.resolvedMaxSnippets(),
            maxCharacters: input.resolvedMaxCharacters(),
            timeout: _searchTimeout,
          )
          .timeout(
            _searchTimeout,
            onTimeout: () => throw TimeoutException(
              'Search timed out after ${_searchTimeout.inSeconds} seconds',
            ),
          );

      return {
        'bookId': book.id,
        'bookTitle': book.title,
        'keyword': keyword,
        'results': response.results.map((result) => result.toMap()).toList(),
        'searchDurationMs': response.duration.inMilliseconds,
        'completed': response.completed,
      };
    } on Object catch (error, stackTrace) {
      AnxLog.severe(
          'BookContentSearchRepository: Search failed for book=${book.id}, keyword="$keyword": $error\n$stackTrace');
      rethrow;
    } finally {
      if (session.isActive) {
        session.scheduleDispose(_sessionIdleTimeout);
      } else {
        _sessions.remove(book.id);
      }
    }
  }

  Future<Book> _resolveBook(int bookId) async {
    if (bookId <= 0) {
      throw ArgumentError('bookId must be greater than zero');
    }

    final books = await _booksRepository.fetchByIds([bookId]);
    final book = books[bookId];
    if (book == null) {
      throw StateError('Book with id=$bookId not found.');
    }
    if (book.isDeleted) {
      throw StateError('Book with id=$bookId has been deleted.');
    }
    return book;
  }

  Future<_HeadlessSearchSession> _getOrCreateSession(Book book) async {
    final fingerprint = await bookSourceFingerprint(book);
    final existing = _sessions[book.id];
    if (existing != null &&
        existing.isActive &&
        existing.sourceFingerprint == fingerprint) {
      existing.cancelDisposalTimer();
      await existing.ensureInitialized();
      return existing;
    }
    await existing?.dispose();

    late final _HeadlessSearchSession session;
    session = _HeadlessSearchSession(
      book: book,
      sourceFingerprint: fingerprint,
      idleCallback: () {
        if (identical(_sessions[book.id], session)) _sessions.remove(book.id);
      },
    );

    _sessions[book.id] = session;
    try {
      await session.ensureInitialized();
    } catch (_) {
      await session.dispose();
      if (identical(_sessions[book.id], session)) _sessions.remove(book.id);
      rethrow;
    }
    return session;
  }
}

class _HeadlessSearchSession {
  _HeadlessSearchSession({
    required this.book,
    required this.sourceFingerprint,
    required this.idleCallback,
  });

  final Book book;
  final String sourceFingerprint;
  final VoidCallback idleCallback;

  AnxHeadlessWebView? _webView;
  InAppWebViewController? _controller;
  final _AsyncLock _lock = _AsyncLock();
  Completer<void>? _readyCompleter;
  Completer<List<dynamic>>? _tocCompleter;
  _ActiveSearch? _activeSearch;
  Timer? _disposeTimer;

  bool get isActive => _webView != null;

  Future<void>? _initialization;
  Future<void> ensureInitialized() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (Platform.isWindows && webViewEnvironment == null) {
      throw StateError(
        'WebViewEnvironment is not initialized. '
        'WebView2 Runtime may not be installed.',
      );
    }

    final ready = _readyCompleter;
    if (_webView != null &&
        _controller != null &&
        ready != null &&
        ready.isCompleted) {
      return;
    }

    final url = _buildBookUrl();

    final loadCompleter = Completer<void>();
    _readyCompleter = Completer<void>();
    _tocCompleter = Completer<List<dynamic>>();

    final headless = AnxHeadlessWebView(
      webViewEnvironment: webViewEnvironment,
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        supportZoom: false,
        // transparentBackground: true,
        isInspectable: kDebugMode,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'onSearch',
          callback: (args) {
            if (args.isEmpty) {
              return null;
            }
            final data = args.first;
            if (data is Map<String, dynamic>) {
              _handleSearchEvent(data);
            } else if (data is Map) {
              _handleSearchEvent(Map<String, dynamic>.from(data));
            }
            return null;
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'onSetToc',
          callback: (args) {
            final completer = _tocCompleter;
            if (completer != null &&
                !completer.isCompleted &&
                args.isNotEmpty &&
                args.first is List) {
              completer.complete(List<dynamic>.from(args.first as List));
            }
            return null;
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'onLoadEnd',
          callback: (args) {
            final ready = _readyCompleter;
            if (ready != null && !ready.isCompleted) {
              ready.complete();
            }
            return null;
          },
        );
      },
      onLoadStop: (controller, url) {
        if (!loadCompleter.isCompleted) {
          loadCompleter.complete();
        }
      },
      onConsoleMessage: webviewConsoleMessage,
      onLoadError: (controller, url, code, message) {
        if (!loadCompleter.isCompleted) {
          loadCompleter.completeError(
            Exception('Failed to load reader: [$code] $message'),
          );
        }
      },
      onLoadHttpError: (controller, url, statusCode, description) {
        if (!loadCompleter.isCompleted) {
          loadCompleter.completeError(
            Exception(
                'HTTP error while loading reader: [$statusCode] $description'),
          );
        }
      },
    );

    _webView = headless;
    await headless.run();
    await loadCompleter.future.timeout(const Duration(seconds: 15),
        onTimeout: () async {
      await headless.dispose();
      _webView = null;
      _controller = null;
      throw TimeoutException('Timed out loading reader for book ${book.id}');
    });

    final readyCompleter = _readyCompleter;
    if (readyCompleter != null && !readyCompleter.isCompleted) {
      await readyCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () async {
          await headless.dispose();
          _webView = null;
          _controller = null;
          throw TimeoutException(
            'Timed out waiting for reader initialization for book ${book.id}',
          );
        },
      );
    }
  }

  Future<_SearchResponse> runSearch({
    required String keyword,
    required int maxResults,
    required int maxSnippets,
    required int? maxCharacters,
    required Duration timeout,
  }) {
    return _lock.synchronized(() async {
      cancelDisposalTimer();
      await ensureInitialized();
      await _waitUntilReady();
      final controller = _controller;
      if (controller == null) {
        throw StateError('WebView controller is not initialized');
      }

      final trimmedKeyword = keyword.trim();
      if (trimmedKeyword.isEmpty) {
        throw ArgumentError('keyword must not be empty');
      }

      final search = _ActiveSearch(
        maxResults: maxResults,
        maxSnippets: maxSnippets,
        maxCharacters: maxCharacters,
      );
      _activeSearch = search;

      final escapedKeyword = jsonEncode(trimmedKeyword);

      final stopwatch = Stopwatch()..start();
      search.stopwatch = stopwatch;

      try {
        await controller.evaluateJavascript(source: 'clearSearch()');
        await controller.evaluateJavascript(
          source:
              'search($escapedKeyword, {"scope":"book","matchCase":false,"matchDiacritics":false,"matchWholeWords":false})',
        );
      } on Object {
        _activeSearch = null;
        rethrow;
      }

      try {
        final response =
            await search.completer.future.timeout(timeout, onTimeout: () {
          if (!search.completer.isCompleted) {
            search.completer.completeError(TimeoutException(
                'Search handler timeout after ${timeout.inSeconds} seconds'));
          }
          return search.completer.future;
        });
        stopwatch.stop();
        return response.copyWith(duration: stopwatch.elapsed);
      } finally {
        await controller.evaluateJavascript(source: 'clearSearch()');
        _activeSearch = null;
      }
    });
  }

  Future<Map<String, String>> extractChapters({
    BookChapterExtractionProgress? onProgress,
    required Duration timeout,
    bool Function()? isCancelled,
  }) {
    return _lock.synchronized(() async {
      cancelDisposalTimer();
      await ensureInitialized();
      await _waitUntilReady();
      final controller = _controller;
      if (controller == null) {
        throw StateError('WebView controller is not initialized');
      }

      var tocCompleter = _tocCompleter;
      if (tocCompleter == null) {
        tocCompleter = Completer<List<dynamic>>();
        _tocCompleter = tocCompleter;
      }
      if (!tocCompleter.isCompleted) {
        await controller.evaluateJavascript(source: 'refreshToc()');
      }
      final toc = await tocCompleter.future.timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'Timed out loading table of contents for book ${book.id}',
        ),
      );
      final indexToc = await controller.callAsyncJavaScript(
        functionBody: 'return getIndexToc();',
      );
      final chapters =
          _flattenToc(indexToc?.value is List ? indexToc!.value as List : toc);
      if (chapters.isEmpty) {
        throw StateError('No readable chapters were found.');
      }

      final result = <String, String>{};
      for (var index = 0; index < chapters.length; index++) {
        if (isCancelled?.call() ?? false) break;
        final chapter = chapters[index];
        final hrefLiteral = jsonEncode(chapter.href);
        final response = await controller.callAsyncJavaScript(
          functionBody: 'return await getChapterContentByHref($hrefLiteral);',
        );
        final text = response?.value?.toString().trim() ?? '';
        if (text.isNotEmpty) result[chapter.id] = text;
        onProgress?.call(chapter.id, index + 1, chapters.length);
        await Future<void>.delayed(Duration.zero);
      }
      if (isCancelled?.call() ?? false) return result;
      if (result.isEmpty) {
        throw StateError(book.fileFullPath.toLowerCase().endsWith('.pdf')
            ? 'PDF 未检测到可提取的文字层。扫描 PDF 需要先进行 OCR。'
            : 'No readable chapter text was found.');
      }
      return result;
    });
  }

  List<_IndexChapterRef> _flattenToc(List<dynamic> toc) {
    final result = <_IndexChapterRef>[];

    void visit(dynamic raw, String fallbackId) {
      if (raw is! Map) return;
      final item = Map<String, dynamic>.from(raw);
      final href = item['href']?.toString().trim() ?? '';
      final id = item['id']?.toString().trim();
      if (href.isNotEmpty) {
        result.add(_IndexChapterRef(
          id: (id == null || id.isEmpty) ? fallbackId : id,
          href: href,
        ));
      }
      final children = item['subitems'];
      if (children is List) {
        for (var index = 0; index < children.length; index++) {
          visit(children[index], '$fallbackId.$index');
        }
      }
    }

    for (var index = 0; index < toc.length; index++) {
      visit(toc[index], 'chapter-$index');
    }
    return result;
  }

  void scheduleDispose(Duration duration) {
    cancelDisposalTimer();
    _disposeTimer = Timer(duration, () async {
      await dispose();
      idleCallback();
    });
  }

  void cancelDisposalTimer() {
    _disposeTimer?.cancel();
    _disposeTimer = null;
  }

  Future<void> dispose() async {
    cancelDisposalTimer();
    final webView = _webView;
    _webView = null;
    _controller = null;
    _readyCompleter = null;
    _tocCompleter = null;
    if (webView != null) {
      try {
        await webView.dispose();
      } catch (error, stackTrace) {
        AnxLog.warning(
            'HeadlessSearchSession(${book.id}): Failed to dispose webview: $error\n$stackTrace');
      }
    }
  }

  void _handleSearchEvent(Map<String, dynamic> data) {
    final active = _activeSearch;
    if (active == null) {
      return;
    }

    if (data.containsKey('process')) {
      final progress = _toDouble(data['process']);
      if (progress >= 1.0 && !active.completer.isCompleted) {
        active.complete(completed: true);
      }
      return;
    }

    if (active.results.length >= active.maxResults) {
      return;
    }

    try {
      final result = _SearchResult.fromJson(
        Map<String, dynamic>.from(data),
        maxSnippets: active.maxSnippets,
        maxCharacters: active.maxCharacters,
      );
      active.results.add(result);
      if (active.results.length >= active.maxResults) {
        active.complete(completed: true);
      }
    } on Object catch (error, stackTrace) {
      if (!active.completer.isCompleted) {
        active.completer.completeError(error, stackTrace);
      }
    }
  }

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? 0;
    }
    return 0;
  }

  Future<void> _waitUntilReady() async {
    final completer = _readyCompleter;
    if (completer == null) {
      throw StateError('Reader not initialized');
    }
    if (completer.isCompleted) {
      return;
    }
    await completer.future;
  }

  String _buildBookUrl() {
    final url = Server().bookUrl(File(book.fileFullPath));
    final initialCfi = book.lastReadPosition;
    return generateUrl(
      url,
      initialCfi,
      importing: false,
    );
  }
}

class _IndexChapterRef {
  const _IndexChapterRef({required this.id, required this.href});

  final String id;
  final String href;
}

class _ActiveSearch {
  _ActiveSearch({
    required this.maxResults,
    required this.maxSnippets,
    required this.maxCharacters,
  });

  final int maxResults;
  final int maxSnippets;
  final int? maxCharacters;
  final List<_SearchResult> results = [];
  final Completer<_SearchResponse> completer = Completer<_SearchResponse>();
  late Stopwatch stopwatch;

  void complete({required bool completed}) {
    if (completer.isCompleted) {
      return;
    }
    stopwatch.stop();
    completer.complete(_SearchResponse(
      results: List<_SearchResult>.from(results),
      completed: completed,
      duration: stopwatch.elapsed,
    ));
  }
}

class _SearchResult {
  _SearchResult({
    required this.chapterTitle,
    required this.chapterCfi,
    required this.matches,
  });

  final String chapterTitle;
  final String chapterCfi;
  final List<_SearchMatch> matches;

  Map<String, dynamic> toMap() {
    return {
      'chapterTitle': chapterTitle,
      'chapterCfi': chapterCfi,
      'matches': matches.map((match) => match.toMap()).toList(),
    };
  }

  static _SearchResult fromJson(
    Map<String, dynamic> json, {
    required int maxSnippets,
    required int? maxCharacters,
  }) {
    final label = (json['label'] as String?)?.trim() ?? '';
    final cfi = (json['cfi'] as String?)?.trim() ?? '';
    final rawSubitems = (json['subitems'] as List?) ?? const [];

    final matches = <_SearchMatch>[];
    for (final entry in rawSubitems.take(maxSnippets)) {
      if (entry is Map<String, dynamic>) {
        matches.add(_SearchMatch.fromJson(entry, maxCharacters: maxCharacters));
      } else if (entry is Map) {
        matches.add(
          _SearchMatch.fromJson(
            Map<String, dynamic>.from(entry),
            maxCharacters: maxCharacters,
          ),
        );
      }
    }

    return _SearchResult(
      chapterTitle: label,
      chapterCfi: cfi,
      matches: matches,
    );
  }
}

class _SearchMatch {
  _SearchMatch({
    required this.cfi,
    required this.pre,
    required this.match,
    required this.post,
  });

  final String cfi;
  final String pre;
  final String match;
  final String post;

  Map<String, dynamic> toMap() {
    return {
      'cfi': cfi,
      'pre': pre,
      'match': match,
      'post': post,
    };
  }

  static _SearchMatch fromJson(
    Map<String, dynamic> json, {
    required int? maxCharacters,
  }) {
    final cfi = (json['cfi'] as String?)?.trim() ?? '';
    final excerpt = (json['excerpt'] as Map?) ?? const {};
    final pre = _sanitizeSnippet(excerpt['pre'], maxCharacters);
    final match = _sanitizeSnippet(excerpt['match'], maxCharacters);
    final post = _sanitizeSnippet(excerpt['post'], maxCharacters);

    return _SearchMatch(
      cfi: cfi,
      pre: pre,
      match: match,
      post: post,
    );
  }

  static String _sanitizeSnippet(dynamic value, int? maxCharacters) {
    final content = (value is String ? value : value?.toString() ?? '').trim();
    if (maxCharacters == null || content.length <= maxCharacters) {
      return content;
    }
    return content.substring(0, maxCharacters);
  }
}

class _SearchResponse {
  const _SearchResponse({
    required this.results,
    required this.completed,
    required this.duration,
  });

  final List<_SearchResult> results;
  final bool completed;
  final Duration duration;

  _SearchResponse copyWith({
    List<_SearchResult>? results,
    bool? completed,
    Duration? duration,
  }) {
    return _SearchResponse(
      results: results ?? this.results,
      completed: completed ?? this.completed,
      duration: duration ?? this.duration,
    );
  }
}

class _AsyncLock {
  Future<void> _pending = Future.value();

  Future<T> synchronized<T>(Future<T> Function() action) {
    final completer = Completer<void>();
    final previous = _pending;
    _pending = completer.future;
    return previous.then((_) => action()).whenComplete(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
  }
}
