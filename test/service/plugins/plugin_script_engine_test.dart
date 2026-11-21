import 'dart:async';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/service/plugins/plugin_script_engine.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:modu_reader/utils/webView/anx_headless_webview.dart';
import 'package:modu_reader/utils/webView/webview_environment_boot.dart';

/// A WebView2 environment that only needs to be non-null: the platform is
/// stubbed below, so no native object is ever created from it.
class _Environment extends PlatformWebViewEnvironment {
  _Environment()
      : super.implementation(const PlatformWebViewEnvironmentCreationParams());
}

class _Browser extends InAppWebViewPlatform {
  final created = Completer<_Headless>();

  @override
  PlatformHeadlessInAppWebView createPlatformHeadlessInAppWebView(
          PlatformHeadlessInAppWebViewCreationParams params) =>
      _Headless(params, created);
}

class _Headless extends PlatformHeadlessInAppWebView {
  _Headless(super.params, this.created) : super.implementation();
  final Completer<_Headless> created;
  final native = _Controller();
  late InAppWebViewController controller;
  int disposals = 0;

  @override
  Future<void> run() async {
    controller = InAppWebViewController.fromPlatform(platform: native);
    params.onWebViewCreated?.call(controller);
    created.complete(this);
  }

  void loadStop() => params.onLoadStop
      ?.call(controller, params.initialData?.baseUrl ?? WebUri('about:blank'));

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class _Controller extends PlatformInAppWebViewController {
  _Controller()
      : super.implementation(const PlatformInAppWebViewControllerCreationParams(
            id: 'plugin-engine-test'));

  final handlers = <String, Function>{};
  final evaluations = <String>[];
  Object? startupStatus = 'running';

  @override
  void addJavaScriptHandler(
      {required String handlerName, required Function callback}) {
    handlers[handlerName] = callback;
  }

  @override
  Future<dynamic> evaluateJavascript(
      {required String source, ContentWorld? contentWorld}) async {
    evaluations.add(source);
    return startupStatus;
  }

  Future<Object?> message(Map<String, Object?> value) =>
      rawMessage(jsonEncode(value));

  Future<Object?> rawMessage(String value) async =>
      await Function.apply(handlers.values.single, [
        [value]
      ]);

  int get starts =>
      evaluations.where((source) => source.contains('moduPluginStart')).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Browser browser;
  late WebViewPluginScriptEngine engine;
  late Future<Map<String, dynamic>> result;
  final calls = <(String, Map<String, dynamic>)>[];

  setUp(() {
    final previous = InAppWebViewPlatform.instance;
    browser = _Browser();
    InAppWebViewPlatform.instance = browser;
    // The engine now asks for the environment instead of only reading a cached
    // value, so the shared boot module needs one for the stubbed platform.
    WebViewEnvironmentBoot.instance.debugSetEnvironment(
        WebViewEnvironment.fromPlatform(platform: _Environment()));
    AnxHeadlessWebView.resumeAccepting();
    engine = WebViewPluginScriptEngine();
    calls.clear();
    addTearDown(() async {
      await engine.dispose();
      WebViewEnvironmentBoot.instance.debugSetEnvironment(null);
      if (previous != null) InAppWebViewPlatform.instance = previous;
    });
  });

  Future<_Headless> start(
      {String action = 'open',
      PluginHostCall? onCall,
      Map<String, Object?>? input}) async {
    result = engine.execute(
        'await modu.privateLibrary.$action(); return {title:"私密书籍",text:""};',
        input ?? {'actionId': action}, onCall: (method, arguments) async {
      calls.add((method, arguments));
      if (onCall != null) return onCall(method, arguments);
      return {action == 'open' ? 'opened' : 'locked': true};
    });
    result.ignore();
    return browser.created.future;
  }

  Future<void> failed() => expectLater(
      result.timeout(const Duration(seconds: 1)), throwsA(isA<StateError>()));

  test('normal bridge refuses multibyte payloads above 64KiB', () async {
    final view = await start();
    view.loadStop();
    final rejected = failed();
    await view.native.message({
      'kind': 'result',
      'value': {'text': '汉' * 23000}
    });
    await rejected;
    expect(engine.diagnosticStage, 'invalid_message');
  });

  test(
      'article bridge accepts escaped large Markdown with trusted native budget',
      () async {
    await engine.dispose();
    engine = WebViewPluginScriptEngine(
        maxMessageBytes: 4 * 1024 * 1024, maxStartBytes: 16 * 1024 * 1024);
    final view = await start(input: {'html': '\u0000' * (2 * 1024 * 1024)});
    view.loadStop();
    await Future<void>.delayed(Duration.zero);
    expect(
        view.native.evaluations.single, contains('"maxMessageBytes":4194304'));
    expect(engine.diagnosticStage, 'worker');
    final markdown = 'x\n' * (256 * 1024);
    await view.native.message({
      'kind': 'result',
      'value': {'title': 'Article', 'markdown': markdown}
    });
    expect((await result)['markdown'], markdown);
  });

  test('article bridge still refuses JSON output above 4MiB', () async {
    await engine.dispose();
    engine = WebViewPluginScriptEngine(
        maxMessageBytes: 4 * 1024 * 1024, maxStartBytes: 16 * 1024 * 1024);
    final view = await start();
    view.loadStop();
    final rejected = failed();
    await view.native.message({
      'kind': 'result',
      'value': {'markdown': '\u0000' * 750000}
    });
    await rejected;
    expect(engine.diagnosticStage, 'invalid_message');
  });

  test('article initial JSON above 16MiB fails before JavaScript evaluation',
      () async {
    await engine.dispose();
    engine = WebViewPluginScriptEngine(
        maxMessageBytes: 4 * 1024 * 1024, maxStartBytes: 16 * 1024 * 1024);
    final view = await start(input: {'html': '\u0000' * (3 * 1024 * 1024)});
    final rejected = failed();
    view.loadStop();
    await rejected;
    expect(view.native.evaluations, isEmpty);
  });

  for (final action in ['open', 'lock']) {
    test('real engine dispatches private $action and accepts its result',
        () async {
      final view = await start(action: action);
      view.loadStop();
      await Future<void>.delayed(Duration.zero);
      expect(view.native.starts, 1);
      expect(view.native.handlers.keys.single, startsWith('plugin_'));
      final reply = await view.native.message({
        'kind': 'call',
        'method': 'privateLibrary.$action',
        'arguments': <String, Object?>{},
      });
      expect(calls, hasLength(1));
      expect(calls.single.$1, 'privateLibrary.$action');
      expect(calls.single.$2, isEmpty);
      expect(reply, {
        'value': {action == 'open' ? 'opened' : 'locked': true}
      });
      await view.native.message({
        'kind': 'result',
        'value': {'title': '私密书籍', 'text': ''}
      });
      expect(await result, {'title': '私密书籍', 'text': ''});
      expect(engine.diagnosticStage, 'complete');
    });
  }

  for (final status in <Object?>[
    'missing_bootstrap',
    'bootstrap_error',
    null
  ]) {
    test('startup status $status fails without waiting for runtime timeout',
        () async {
      final view = await start();
      view.native.startupStatus = status;
      final rejected = failed();
      view.loadStop();
      await rejected;
      expect(calls, isEmpty);
      expect(engine.diagnosticStage, 'bootstrap_error');
    });
  }

  test('main-frame HTTP errors fail an unfinished engine immediately',
      () async {
    final view = await start();
    final rejected = failed();
    view.params.onReceivedHttpError!(
        view.controller,
        WebResourceRequest(
            url: view.params.initialData!.baseUrl!, isForMainFrame: true),
        WebResourceResponse(statusCode: 403, reasonPhrase: 'Blocked'));
    await rejected;
    expect(engine.diagnosticStage, 'page_http_error_403');
  });

  test('main-frame load errors fail an unfinished engine immediately',
      () async {
    final view = await start();
    final rejected = failed();
    view.params.onReceivedError!(
        view.controller,
        WebResourceRequest(
            url: WebUri('https://blocked.invalid/'), isForMainFrame: true),
        WebResourceError(
            type: WebResourceErrorType.UNKNOWN,
            description: 'test load failure'));
    await rejected;
    expect(engine.diagnosticStage, 'page_load_error');
  });

  test('worker errors fail immediately without a ten-second host timeout',
      () async {
    final view = await start();
    view.loadStop();
    // A worker error without a code means the script itself threw, so it is a
    // typed script failure rather than the generic engine StateError.
    final rejected = expectLater(
        result,
        throwsA(isA<PluginScriptFailure>()
            .having((e) => e.code, 'code', 'execution')));
    await view.native.message({'kind': 'error'});
    await rejected;
    expect(engine.diagnosticStage, 'worker_error');
  });

  test('unrecognised ready messages cannot call host APIs or complete a result',
      () async {
    final view = await start();
    view.loadStop();
    final rejected = failed();
    await view.native.message({'kind': 'ready', 'stage': 'untrusted-stage'});
    await rejected;
    expect(calls, isEmpty);
    expect(engine.diagnosticStage, 'invalid_message');
  });

  test('waiting for the bridge remains pending and can finish later', () async {
    final view = await start();
    view.native.startupStatus = 'waiting_bridge';
    view.loadStop();
    await Future<void>.delayed(Duration.zero);
    expect(engine.diagnosticStage, 'waiting_bridge');
    await view.native.message({
      'kind': 'result',
      'value': {'text': 'ready later'}
    });
    expect(await result, {'text': 'ready later'});
    expect(engine.diagnosticStage, 'complete');
  });

  test('malformed bridge JSON fails immediately without echoing its content',
      () async {
    final view = await start();
    final rejected = failed();
    await view.native.rawMessage('{"secret-test-content"');
    await rejected;
    expect(engine.diagnosticStage, 'invalid_message');
    expect(calls, isEmpty);
  });

  test('a non-object result fails immediately as an invalid message', () async {
    final view = await start();
    final rejected = failed();
    await view.native.message({'kind': 'result', 'value': 42});
    await rejected;
    expect(engine.diagnosticStage, 'invalid_message');
  });

  test('native failures return a fixed error and let the worker handle it',
      () async {
    final view = await start(onCall: (_, __) async {
      throw StateError('secret-native-exception');
    });
    view.loadStop();
    final reply = await view.native.message({
      'kind': 'call',
      'method': 'privateLibrary.open',
      'arguments': <String, Object?>{},
    });
    // An unexpected host exception is a script-level failure, and the reply
    // must never echo the exception text.
    expect(reply, {'error': 'Plugin request failed', 'code': 'execution'});
    expect(engine.diagnosticStage, 'worker');
    await view.native.message({
      'kind': 'result',
      'value': {'text': 'handled'}
    });
    expect(await result, {'text': 'handled'});
  });

  test('a host permission failure keeps its code across the bridge', () async {
    // This is the bug behind "the plugin could not run": the host refused a
    // capability the user had not granted, but every failure collapsed into one
    // fixed string, so the UI could not offer the consent sheet.
    final view = await start(onCall: (_, __) async {
      throw const PluginScriptFailure('denied');
    });
    view.loadStop();
    final reply = await view.native.message({
      'kind': 'call',
      'method': 'privateLibrary.open',
      'arguments': <String, Object?>{},
    });
    expect(reply, {'error': 'Plugin request failed', 'code': 'denied'});
  });

  test('a worker error reports the code it was given', () async {
    final view = await start();
    view.loadStop();
    final rejected = expectLater(
        result,
        throwsA(isA<PluginScriptFailure>()
            .having((e) => e.code, 'code', 'denied')));
    await view.native.message({'kind': 'error', 'code': 'denied'});
    await rejected;
    expect(engine.diagnosticStage, 'worker_error');
  });

  test('a worker cannot invent a failure code the host does not know', () async {
    final view = await start();
    view.loadStop();
    final rejected = expectLater(
        result,
        throwsA(isA<PluginScriptFailure>()
            .having((e) => e.code, 'code', 'execution')));
    await view.native.message({'kind': 'error', 'code': 'made-up-code'});
    await rejected;
  });

  test('console diagnostics retain only a fixed stage', () async {
    final view = await start();
    view.loadStop();
    await Future<void>.delayed(Duration.zero);
    view.params.onConsoleMessage!(
        view.controller,
        ConsoleMessage(
            message: 'secret-console-text',
            messageLevel: ConsoleMessageLevel.ERROR));
    expect(engine.diagnosticStage, 'javascript_error');
    await view.native.message({
      'kind': 'result',
      'value': {'text': 'finished'}
    });
    expect(await result, {'text': 'finished'});
  });

  test('duplicate load-stop callbacks start the worker only once', () async {
    final view = await start();
    view.loadStop();
    view.loadStop();
    await Future<void>.delayed(Duration.zero);
    expect(view.native.starts, 1);
    await view.native.message({
      'kind': 'result',
      'value': {'text': 'done'}
    });
    expect(await result, {'text': 'done'});
  });

  test(
      'dispose is idempotent and late bridge messages never invoke native work',
      () async {
    final view = await start();
    view.loadStop();
    final rejected = failed();
    await engine.dispose();
    await rejected;
    await engine.dispose();
    expect(view.disposals, 1);
    expect(
        await view.native.message({
          'kind': 'call',
          'method': 'privateLibrary.open',
          'arguments': <String, Object?>{},
        }),
        isNull);
    expect(
        await view.native.message({
          'kind': 'result',
          'value': {'text': 'late'}
        }),
        isNull);
    expect(calls, isEmpty);
  });

  test('dispose awaits the stop call before tearing the view down', () async {
    // A platform message still pending when the native view dies is reported by
    // the Flutter engine as "Failed to respond to a message. This is a memory
    // leak." Dispose therefore has to await the stop call instead of firing it
    // and walking away.
    final view = await start();
    view.loadStop();
    final rejected = failed();
    await engine.dispose();
    await rejected;
    expect(view.disposals, 1);
    expect(
        view.native.evaluations
            .any((source) => source.contains('moduPluginStop')),
        isTrue);
  });

  test('memory document keeps file, network, navigation and popup isolation',
      () async {
    final view = await start();
    final settings = view.params.initialSettings!;
    expect(settings.javaScriptEnabled, true);
    expect(settings.blockNetworkLoads, true);
    expect(settings.allowFileAccess, false);
    expect(settings.allowContentAccess, false);
    expect(settings.allowUniversalAccessFromFileURLs, false);
    expect(settings.domStorageEnabled, false);
    expect(view.params.initialData!.data, contains("connect-src 'none'"));
    expect(view.params.initialData!.data, contains('worker-src blob:'));
    final response = await view.params.shouldInterceptRequest!(view.controller,
        WebResourceRequest(url: WebUri('https://blocked.invalid/source.js')));
    expect(response!.statusCode, 403);
    final navigation = await view.params.shouldOverrideUrlLoading!(
        view.controller,
        NavigationAction(
            request: URLRequest(url: WebUri('https://blocked.invalid/')),
            isForMainFrame: true));
    expect(navigation, NavigationActionPolicy.CANCEL);
  });

  test('only the exact initial main document is served from memory', () async {
    final view = await start();
    final url = view.params.initialData!.baseUrl!;
    final response = await view.params.shouldInterceptRequest!(view.controller,
        WebResourceRequest(url: url, isForMainFrame: true, method: 'GET'));
    expect(response!.statusCode, 200);
    expect(response.contentType, 'text/html');
    expect(utf8.decode(response.data!), view.params.initialData!.data);
    expect(url.scheme, 'https');
    expect(url.host, endsWith('.modu-plugin.invalid'));
    for (final request in [
      WebResourceRequest(url: url, isForMainFrame: false),
      WebResourceRequest(url: url, isForMainFrame: true, method: 'POST'),
      WebResourceRequest(url: WebUri('$url?changed=1'), isForMainFrame: true),
      WebResourceRequest(
          url: WebUri('https://modu-plugin.invalid/another/index.html'),
          isForMainFrame: true),
    ]) {
      expect(
          (await view.params.shouldInterceptRequest!(view.controller, request))!
              .statusCode,
          403);
    }
    view.loadStop();
    await Future<void>.delayed(Duration.zero);
    expect(
        (await view.params.shouldInterceptRequest!(view.controller,
                WebResourceRequest(url: url, isForMainFrame: true)))!
            .statusCode,
        403);
    await view.native.message({
      'kind': 'result',
      'value': {'text': 'ok'}
    });
    expect(await result, {'text': 'ok'});
  });

  test('a blocked auxiliary HTTP request cannot abort the memory runtime',
      () async {
    final view = await start();
    view.params.onReceivedHttpError!(
        view.controller,
        WebResourceRequest(url: WebUri('https://blocked.invalid/')),
        WebResourceResponse(statusCode: 403, reasonPhrase: 'Blocked'));
    view.loadStop();
    await view.native.message({
      'kind': 'result',
      'value': {'text': 'ok'}
    });
    expect(await result, {'text': 'ok'});
  });

  test('separate executions never share a web storage origin', () async {
    final first = await start();
    final secondBrowser = _Browser();
    InAppWebViewPlatform.instance = secondBrowser;
    final secondEngine = WebViewPluginScriptEngine();
    addTearDown(secondEngine.dispose);
    secondEngine
        .execute('return {text:"ok"};', {}, onCall: (_, __) async => null)
        .ignore();
    final second = await secondBrowser.created.future;
    final firstUrl = first.params.initialData!.baseUrl!;
    final secondUrl = second.params.initialData!.baseUrl!;
    expect(firstUrl.host, isNot(secondUrl.host));
    expect(firstUrl.host,
        matches(r'^run-[a-z0-9-]+-local\.modu-plugin\.invalid$'));
    expect(secondUrl.host,
        matches(r'^run-[a-z0-9-]+-local\.modu-plugin\.invalid$'));
    InAppWebViewPlatform.instance = browser;
  });
}
