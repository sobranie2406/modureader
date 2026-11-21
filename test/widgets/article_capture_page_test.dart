import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/page/plugins/article_capture_page.dart';
import 'package:modu_reader/service/plugins/article_capture.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_http_client.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:modu_reader/service/plugins/plugin_host_api.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:modu_reader/service/plugins/plugin_script_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Host extends PluginHost {
  _Host() : super(paths: PluginPaths(rootPath: '/tmp/modu_article_widget'));
  bool enabled = true, hasCapability = true, hasExtractor = true;
  PluginManifest? _manifest;
  void reload() {
    _manifest = null;
    notifyListeners();
  }

  void change({bool? enabled, bool? hasCapability}) {
    this.enabled = enabled ?? this.enabled;
    this.hasCapability = hasCapability ?? this.hasCapability;
    notifyListeners();
  }

  @override
  bool isScriptRunnable(String id) =>
      enabled && Prefs().experimentalPluginsEnabled;
  @override
  PluginManifest? manifestFor(String id) => hasCapability
      ? _manifest ??= PluginManifest.fromJson({
          'schemaVersion': 1,
          'hostApi': 1,
          'id': 'com.modu.web-clipper',
          'version': '1.0.0',
          'name': {'en': 'Web clipper'},
          'license': 'MIT',
          'minAppVersion': '1.3.10',
          'capabilities': [
            'script:run',
            'article:capture',
            if (hasExtractor) 'article:extract'
          ],
          'contributes': [
            {
              'kind': 'scriptAction',
              'schema': 1,
              'id': 'capture',
              'name': {'en': 'Capture'},
              'entry': 'main.js',
              'surface': 'library'
            },
            if (hasExtractor)
              {
                'kind': 'scriptAction',
                'schema': 1,
                'id': 'extract',
                'name': 'Extract',
                'entry': 'extract.js',
                'surface': 'article'
              }
          ],
        })
      : null;
}

final _document = ArticleCaptureDocument(
    '<article>Raw website text</article>', Uri.parse('https://example.com'),
    plainText: false);
final _article = CapturedArticle(
    'A captured article',
    Uri.parse('https://example.com'),
    '# A captured article\n\nUseful body text captured for offline reading, with its original source link.\n');

class _Service extends ArticleCaptureService {
  Future<ArticleCaptureDocument> Function()? next;
  PluginCancelToken? lastCancel;
  int calls = 0;
  @override
  Future<ArticleCaptureDocument> fetchDocument(String url,
      {required PluginCancelToken cancel}) {
    calls++;
    lastCancel = cancel;
    return next?.call() ?? Future.value(_document);
  }
}

class _Runtime extends PluginScriptRuntime {
  _Runtime(PluginHost host) : super(host: host);
  Future<Map<String, dynamic>> Function()? next;
  PluginCancelToken? lastCancel;
  Map<String, Object?>? lastInput;
  int calls = 0;
  @override
  Future<Map<String, dynamic>> run(
      {required String pluginId,
      required ScriptActionContribution action,
      Map<String, Object?> input = const {},
      PluginHostCall? hostCall,
      PluginHostApi? hostApi,
      bool Function()? isContextValid,
      PluginCancelToken? cancel}) {
    calls++;
    lastCancel = cancel;
    lastInput = input;
    return next?.call() ??
        Future.value({'title': _article.title, 'markdown': _article.markdown});
  }
}

void main() {
  late _Host host;
  late _Service service;
  late _Runtime runtime;
  var exports = 0, imports = 0;
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    host = _Host();
    service = _Service();
    runtime = _Runtime(host);
    exports = 0;
    imports = 0;
  });
  tearDown(() {
    runtime.dispose();
    host.dispose();
  });

  test('article filenames preserve Unicode without exceeding filesystem limits',
      () {
    const stamp = 1790000000000000;
    for (final title in ['书' * 80, '😀' * 80, '${'A' * 79}😀']) {
      final name = articleCaptureFileName(title, timestamp: stamp);
      expect(utf8.encode(name).length, lessThanOrEqualTo(240));
      expect(utf8.decode(utf8.encode(name)), name);
      expect(name, endsWith('-$stamp.md'));
      expect(name, isNot(contains('\uFFFD')));
    }
    expect(articleCaptureFileName('${'A' * 79}😀', timestamp: stamp),
        '${'A' * 79}😀-$stamp.md');
    expect(articleCaptureFileName('', timestamp: stamp), 'Article-$stamp.md');
    final sanitized =
        articleCaptureFileName('a/b\\c:*?"<>|\n', timestamp: stamp);
    expect(sanitized, isNot(contains(RegExp(r'[\\/:*?"<>|\x00-\x1f]'))));
  });

  Future<void> show(WidgetTester tester,
      {Size size = const Size(390, 844),
      double textScale = 1,
      double keyboard = 0,
      Future<void> Function(CapturedArticle)? onExport}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      locale: const Locale('en'),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              viewInsets: EdgeInsets.only(bottom: keyboard)),
          child: child!),
      home: ArticleCapturePage(
          pluginId: 'com.modu.web-clipper',
          host: host,
          service: service,
          scriptRuntime: runtime,
          onExport: onExport ??
              (_) async {
                exports++;
              },
          onImport: (_) async {
            imports++;
          }),
    )));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester) async {
    await tester.enterText(find.byKey(const ValueKey('article-url')),
        'https://example.com/article');
    await tester.tap(find.byKey(const ValueKey('article-fetch')));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'capture previews Markdown, then exports or imports only on demand',
      (tester) async {
    await show(tester);
    expect(find.byKey(const ValueKey('article-export')), findsNothing);
    await capture(tester);
    expect(service.calls, 1);
    expect(find.byKey(const ValueKey('article-preview')), findsOneWidget);
    expect(exports, 0);
    expect(imports, 0);
    await tester.tap(find.byKey(const ValueKey('article-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('article-import')));
    await tester.pumpAndSettle();
    expect(exports, 1);
    expect(imports, 1);
    expect(find.text('Added to your bookshelf.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'narrow large text and a landscape keyboard remain scrollable without overflow',
      (tester) async {
    await show(tester, size: const Size(390, 844), textScale: 2);
    await capture(tester);
    expect(tester.takeException(), isNull);
    await show(tester, size: const Size(640, 360), textScale: 2, keyboard: 160);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('article-import')), 100,
        scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabling the plugin cancels capture and discards a late result',
      (tester) async {
    final pending = Completer<ArticleCaptureDocument>();
    service.next = () => pending.future;
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('article-fetch')));
    await tester.pump();
    host.change(enabled: false);
    await tester.pumpAndSettle();
    expect(service.lastCancel!.isCancelled, isTrue);
    expect(find.text('This plugin is disabled.'), findsOneWidget);
    pending.complete(_document);
    await tester.pumpAndSettle();
    host.change(enabled: true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('article-preview')), findsNothing);
    expect(find.byKey(const ValueKey('article-import')), findsNothing);
  });

  testWidgets(
      'revoking capability clears preview and global switch blocks the page',
      (tester) async {
    await show(tester);
    await capture(tester);
    host.change(hasCapability: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('article-preview')), findsNothing);
    host.change(hasCapability: true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('article-fetch')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await show(tester);
    await capture(tester);
    await Prefs().saveExperimentalPluginsEnabled(false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('article-export')), findsNothing);
    expect(find.text('This plugin is disabled.'), findsOneWidget);
  });

  testWidgets('cancelled and replaced captures cannot replace a newer preview',
      (tester) async {
    final first = Completer<ArticleCaptureDocument>();
    service.next = () => first.future;
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('article-fetch')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('article-cancel')));
    await tester.pumpAndSettle();
    expect(service.lastCancel!.isCancelled, isTrue);
    service.next = () async => _document;
    await capture(tester);
    first.complete(ArticleCaptureDocument('Old raw result', _article.sourceUrl,
        plainText: false));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('article-preview')), findsOneWidget);
    expect(find.textContaining('Old result'), findsNothing);
  });

  testWidgets('backgrounding cancels acquisition and does not resume it',
      (tester) async {
    final pending = Completer<ArticleCaptureDocument>();
    service.next = () => pending.future;
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('article-fetch')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(service.lastCancel!.isCancelled, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    pending.complete(_document);
    await tester.pumpAndSettle();
    expect(service.calls, 1);
    expect(find.byKey(const ValueKey('article-preview')), findsNothing);
  });

  testWidgets(
      'native save stays busy during system dialog lifecycle and exposes no false cancel',
      (tester) async {
    final save = Completer<void>();
    var calls = 0;
    await show(tester, onExport: (_) {
      calls++;
      return save.future;
    });
    await capture(tester);
    await tester.tap(find.byKey(const ValueKey('article-export')));
    await tester.pump();
    expect(find.byKey(const ValueKey('article-cancel')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('article-export')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('article-import')))
            .onPressed,
        isNull);
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    save.complete();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('article-export')))
            .onPressed,
        isNotNull);
  });

  testWidgets(
      'capture errors are concise and do not reflect URL or server details',
      (tester) async {
    service.next = () => Future.error(const ArticleCaptureFailure('network'));
    await show(tester);
    await capture(tester);
    expect(
        find.text(
            'Unable to capture this page. Check the address and try again.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('article-preview')), findsNothing);
  });

  testWidgets(
      'disposing the page cancels a pending capture without late UI work',
      (tester) async {
    final pending = Completer<ArticleCaptureDocument>();
    service.next = () => pending.future;
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('article-fetch')));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(service.lastCancel!.isCancelled, isTrue);
    pending.complete(_document);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('same-version reload revokes the original page and late capture',
      (tester) async {
    final pending = Completer<ArticleCaptureDocument>();
    service.next = () => pending.future;
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('article-fetch')));
    await tester.pump();
    host.reload();
    await tester.pumpAndSettle();
    expect(service.lastCancel!.isCancelled, true);
    pending.complete(_document);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('article-preview')), findsNothing);
    expect(find.byKey(const ValueKey('article-import')), findsNothing);
    expect(find.byKey(const ValueKey('article-fetch')), findsNothing);
  });
  testWidgets('old capture-only plugins show an update prompt before fetching',
      (tester) async {
    host.hasExtractor = false;
    await show(tester);
    expect(find.byKey(const ValueKey('article-update-plugin')), findsOneWidget);
    expect(find.byKey(const ValueKey('article-fetch')), findsNothing);
    expect(service.calls, 0);
    expect(runtime.calls, 0);
  });

  testWidgets(
      'plugin extraction receives downloaded content and never auto-fetches preview images',
      (tester) async {
    runtime.next = () async => {
          'title': 'Plugin title',
          'markdown':
              '# Plugin title\n\n![Remote](https://image.example/photo.png)\n\n[Unsafe](file:///private/secret)'
        };
    await show(tester);
    await capture(tester);
    expect(runtime.lastInput, {
      'html': _document.content,
      'url': _document.sourceUrl.toString(),
      'plainText': false
    });
    expect(find.text('Image link'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling during plugin parsing rejects its late result',
      (tester) async {
    final parsed = Completer<Map<String, dynamic>>();
    runtime.next = () => parsed.future;
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('article-fetch')));
    await tester.pump();
    expect(runtime.calls, 1);
    await tester.tap(find.byKey(const ValueKey('article-cancel')));
    await tester.pumpAndSettle();
    expect(runtime.lastCancel!.isCancelled, true);
    parsed.complete({'title': 'Late title', 'markdown': '# Late title'});
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('article-preview')), findsNothing);
  });

  testWidgets('one overall deadline cancels a pending plugin parser',
      (tester) async {
    final parsed = Completer<Map<String, dynamic>>();
    runtime.next = () => parsed.future;
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('article-fetch')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(runtime.lastCancel!.isCancelled, true);
    expect(find.text('The request timed out. Try again.'), findsOneWidget);
    parsed.complete({'title': 'Late title', 'markdown': '# Late title'});
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('article-preview')), findsNothing);
  });
}
