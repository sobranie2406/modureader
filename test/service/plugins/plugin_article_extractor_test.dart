import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/article_capture.dart';
import 'package:modu_reader/service/plugins/plugin_article_extractor.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_http_client.dart';
import 'package:modu_reader/service/plugins/plugin_script_engine.dart';
import 'package:modu_reader/service/plugins/plugin_host_api.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_utils.dart';

const _id = 'dev.example.articles';
final _document = ArticleCaptureDocument(
    '<html><body>Raw content</body></html>',
    Uri.parse('https://final.example/article?id=2'),
    plainText: false);
const _result = {
  'title': 'Plugin title',
  'markdown': '# Plugin title\n\nPlugin-owned body.'
};

class _Host extends PluginHost {
  _Host() : manifest = createManifest();
  PluginManifest manifest;
  bool enabled = true;
  static PluginManifest createManifest({bool extractor = true}) =>
      PluginManifest.parse(manifestJson(id: _id, capabilities: [
        'script:run',
        'article:capture',
        if (extractor) 'article:extract'
      ], contributes: [
        {
          'kind': 'scriptAction',
          'schema': 1,
          'id': 'open',
          'name': 'Open',
          'entry': 'main.js',
          'surface': 'library'
        },
        if (extractor)
          {
            'kind': 'scriptAction',
            'schema': 1,
            'id': 'extract',
            'name': 'Extract',
            'entry': 'extract.js',
            'surface': 'article'
          }
      ]));
  @override
  PluginManifest? manifestFor(String id) => manifest;
  @override
  bool isScriptRunnable(String id) => enabled;
  void reload() {
    manifest = createManifest();
    notifyListeners();
  }
}

class _Download extends ArticleCaptureService {
  Future<ArticleCaptureDocument> Function()? next;
  PluginCancelToken? token;
  int calls = 0;
  @override
  Future<ArticleCaptureDocument> fetchDocument(String url,
      {required PluginCancelToken cancel}) {
    calls++;
    token = cancel;
    return next?.call() ?? Future.value(_document);
  }
}

class _Runtime extends PluginScriptRuntime {
  _Runtime(PluginHost host) : super(host: host);
  Future<Map<String, dynamic>> Function()? next;
  PluginCancelToken? token;
  Map<String, Object?>? input;
  PluginHostCall? hostCall;
  int calls = 0, cancelledJobs = 0, idCancellations = 0;
  @override
  void cancelPlugin(String id) {
    idCancellations++;
  }

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
    token = cancel;
    this.input = input;
    this.hostCall = hostCall;
    final result = Completer<Map<String, dynamic>>();
    cancel?.whenCancelled(() {
      if (!result.isCompleted) {
        cancelledJobs++;
        result.completeError(const PluginScriptFailure('cancelled'));
      }
    });
    (next?.call() ?? Future.value(_result)).then((value) {
      if (!result.isCompleted) result.complete(value);
    }, onError: (Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    });
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Host host;
  late _Download service;
  late _Runtime runtime;
  late PluginArticleExtractor extractor;
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    host = _Host();
    service = _Download();
    runtime = _Runtime(host);
    extractor = PluginArticleExtractor(host: host, runtime: runtime);
  });
  tearDown(() {
    runtime.dispose();
    host.dispose();
  });
  Future<CapturedArticle> capture([PluginCancelToken? token]) =>
      extractor.capture('https://initial.example',
          pluginId: _id,
          service: service,
          cancel: token ?? PluginCancelToken(),
          isContextValid: () => true);
  Matcher failure(String code) =>
      throwsA(isA<ArticleCaptureFailure>().having((e) => e.code, 'code', code));

  test(
      'only the owning plugin processes raw content and native provenance stays fixed',
      () async {
    final article = await capture();
    expect(runtime.input, {
      'html': _document.content,
      'url': _document.sourceUrl.toString(),
      'plainText': false
    });
    expect(runtime.hostCall, isNull);
    expect(article.title, _result['title']);
    expect(article.markdown, _result['markdown']);
    expect(article.sourceUrl, _document.sourceUrl);
    expect(runtime.idCancellations, 0);
  });
  test('old plugins require an update before any download', () async {
    host.manifest = _Host.createManifest(extractor: false);
    expect(extractor.available(_id), false);
    await expectLater(capture(), failure('upgrade'));
    expect(service.calls, 0);
    expect(runtime.calls, 0);
  });
  test('network and decode failures retain their existing category', () async {
    for (final code in ['url', 'format', 'network', 'size', 'redirect']) {
      service.next = () => Future.error(ArticleCaptureFailure(code));
      await expectLater(capture(), failure(code));
    }
    expect(runtime.calls, 0);
  });
  test('UTF8 input and output limits are enforced beyond character counts',
      () async {
    service.next = () async => ArticleCaptureDocument(
        'é' * (ArticleCaptureService.maxBytes ~/ 2 + 1), _document.sourceUrl,
        plainText: true);
    await expectLater(capture(), failure('size'));
    expect(runtime.calls, 0);
    service.next = null;
    runtime.next = () async => {
          'title': 'Article',
          'markdown': 'é' * (PluginLimits.maxArticleMarkdownBytes ~/ 2 + 1)
        };
    await expectLater(capture(), failure('size'));
  });
  test('malformed results, injected provenance and invalid titles are rejected',
      () async {
    for (final result in <Map<String, dynamic>>[
      {
        'title': 'Article',
        'markdown': 'body',
        'sourceUrl': 'https://fake.example'
      },
      {'title': 42, 'markdown': 'body'},
      {'title': 'Article', 'markdown': 42},
      {'title': 'x' * 201, 'markdown': 'body'},
      {'title': 'unsafe\nname', 'markdown': 'body'},
      {'title': 'Article', 'markdown': ' '},
      {'title': 'Article', 'markdown': 'unsafe\u0000text'},
      {'title': 'Article', 'markdown': 'unsafe\u001ftext'},
    ]) {
      runtime.next = () async => result;
      await expectLater(capture(), failure('result'));
    }
  });
  test('Unicode titles and normal Markdown whitespace use the runtime rules',
      () async {
    runtime.next =
        () async => {'title': '😀' * 150, 'markdown': '# Heading\n\nA\tB\r\n'};
    expect((await capture()).title.runes.length, 150);
    runtime.next = () async => {'title': '😀' * 201, 'markdown': 'body'};
    await expectLater(capture(), failure('result'));
  });
  test(
      'pre-cancelled captures never start acquisition or touch another plugin job',
      () async {
    final token = PluginCancelToken()..cancel();
    await expectLater(capture(token), failure('cancelled'));
    expect(service.calls, 0);
    expect(runtime.calls, 0);
    expect(runtime.idCancellations, 0);
  });
  test(
      'cancelling acquisition closes its token without cancelling any other job by ID',
      () async {
    final downloaded = Completer<ArticleCaptureDocument>();
    service.next = () => downloaded.future;
    final token = PluginCancelToken();
    final result = capture(token);
    final rejected = expectLater(result, failure('cancelled'));
    token.cancel();
    await rejected;
    expect(service.token!.isCancelled, true);
    expect(runtime.calls, 0);
    expect(runtime.idCancellations, 0);
    downloaded.complete(_document);
    await Future<void>.delayed(Duration.zero);
  });
  test(
      'cancelling extraction aborts only its accepted job and ignores a late result',
      () async {
    final parsed = Completer<Map<String, dynamic>>();
    runtime.next = () => parsed.future;
    final token = PluginCancelToken();
    final result = capture(token);
    final rejected = expectLater(result, failure('cancelled'));
    await Future<void>.delayed(Duration.zero);
    expect(runtime.calls, 1);
    token.cancel();
    await rejected;
    expect(runtime.cancelledJobs, 1);
    expect(runtime.idCancellations, 0);
    parsed.complete(_result);
    await Future<void>.delayed(Duration.zero);
  });
  test('one fifteen-second deadline covers acquisition and extraction together',
      () {
    fakeAsync((clock) {
      final downloaded = Completer<ArticleCaptureDocument>();
      final parsed = Completer<Map<String, dynamic>>();
      service.next = () => downloaded.future;
      runtime.next = () => parsed.future;
      Object? outcome;
      capture().then<void>((value) => outcome = value,
          onError: (Object e) => outcome = e);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 10));
      downloaded.complete(_document);
      clock.flushMicrotasks();
      expect(runtime.calls, 1);
      clock.elapse(const Duration(seconds: 4));
      expect(outcome, isNull);
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(
          outcome,
          isA<ArticleCaptureFailure>()
              .having((e) => e.code, 'code', 'timeout'));
      expect(service.token!.isCancelled, true);
      expect(runtime.cancelledJobs, 1);
      expect(clock.pendingTimers, isEmpty);
      parsed.complete(_result);
      clock.flushMicrotasks();
    });
  });
  test('global two-capture quota stays occupied while parsers are running',
      () async {
    final parsed = Completer<Map<String, dynamic>>();
    runtime.next = () => parsed.future;
    final firstToken = PluginCancelToken(), secondToken = PluginCancelToken();
    final first = capture(firstToken), second = capture(secondToken);
    final checks = [
      expectLater(first, failure('cancelled')),
      expectLater(second, failure('cancelled'))
    ];
    await Future<void>.delayed(Duration.zero);
    expect(runtime.calls, 2);
    await expectLater(capture(), failure('busy'));
    expect(service.calls, 2);
    firstToken.cancel();
    secondToken.cancel();
    await Future.wait(checks);
    parsed.complete(_result);
    await Future<void>.delayed(Duration.zero);
    runtime.next = null;
    expect((await capture()).title, 'Plugin title');
  });
  test(
      'same-version reload immediately cancels pending download before worker start',
      () async {
    final downloaded = Completer<ArticleCaptureDocument>();
    service.next = () => downloaded.future;
    final result = capture();
    final rejected = expectLater(result, failure('cancelled'));
    host.reload();
    await rejected;
    expect(service.token!.isCancelled, true);
    expect(runtime.calls, 0);
    downloaded.complete(_document);
    await Future<void>.delayed(Duration.zero);
  });
  test('unavailable workers are distinguished from network failures', () async {
    runtime.next = () => Future.error(const PluginScriptFailure('execution'));
    await expectLater(capture(), failure('extract'));
    runtime.next = () => Future.error(const PluginScriptFailure('unavailable'));
    await expectLater(capture(), failure('upgrade'));
  });
}
