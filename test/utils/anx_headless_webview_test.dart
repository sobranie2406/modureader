import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/main.dart' show navigatorKey;
import 'package:modu_reader/utils/webView/anx_headless_webview.dart';

class _Browser extends InAppWebViewPlatform {
  _Browser({this.failHeadless = false});

  final bool failHeadless;
  _Headless? headless;
  PlatformInAppWebViewWidgetCreationParams? overlay;

  @override
  PlatformHeadlessInAppWebView createPlatformHeadlessInAppWebView(
          PlatformHeadlessInAppWebViewCreationParams params) =>
      headless = _Headless(params, failHeadless);

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
      PlatformInAppWebViewWidgetCreationParams params) {
    overlay = params;
    return _View(params);
  }
}

class _Headless extends PlatformHeadlessInAppWebView {
  _Headless(super.params, this.fail) : super.implementation();

  final bool fail;
  int runs = 0, disposals = 0;

  @override
  Future<void> run() async {
    runs++;
    if (fail) throw StateError('Headless unavailable');
  }

  @override
  Future<void> dispose() async => disposals++;
}

class _View extends PlatformInAppWebViewWidget {
  _View(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      throw UnimplementedError();

  @override
  void dispose() {}
}

class _Controller extends PlatformInAppWebViewController {
  _Controller()
      : super.implementation(
            const PlatformInAppWebViewControllerCreationParams(id: 'host'));
}

class _Environment extends PlatformWebViewEnvironment {
  _Environment()
      : super.implementation(const PlatformWebViewEnvironmentCreationParams());
}

void main() {
  setUp(AnxHeadlessWebView.resumeAccepting);

  for (final overlay in [false, true]) {
    testWidgets(
        '${overlay ? 'overlay fallback' : 'headless'} retains data origin and all host policies',
        (tester) async {
      final previous = InAppWebViewPlatform.instance;
      final browser = _Browser(failHeadless: overlay);
      InAppWebViewPlatform.instance = browser;
      addTearDown(() {
        if (previous != null) InAppWebViewPlatform.instance = previous;
      });
      await tester.pumpWidget(MaterialApp(
          navigatorKey: navigatorKey, home: const Scaffold(body: SizedBox())));

      final environment =
          WebViewEnvironment.fromPlatform(platform: _Environment());
      final data = InAppWebViewInitialData(
          data: '<!doctype html><title>isolated host</title>',
          baseUrl: WebUri('about:blank'));
      final settings = InAppWebViewSettings(
          allowFileAccess: false,
          useShouldOverrideUrlLoading: true,
          useShouldInterceptRequest: true);
      final seen = <Object>[];
      final blocked = WebResourceResponse(
          statusCode: 403, reasonPhrase: 'Blocked', data: Uint8List(0));
      var created = 0;
      final view = AnxHeadlessWebView(
          initialData: data,
          initialSettings: settings,
          webViewEnvironment: environment,
          onWebViewCreated: (_) => created++,
          shouldOverrideUrlLoading: (_, action) {
            seen.add(action);
            return NavigationActionPolicy.CANCEL;
          },
          shouldInterceptRequest: (_, request) async {
            seen.add(request);
            return blocked;
          },
          onCreateWindow: (_, action) async {
            seen.add(action);
            return false;
          },
          onPermissionRequest: (_, request) {
            seen.add(request);
            return PermissionResponse(
                resources: request.resources,
                action: PermissionResponseAction.DENY);
          });
      addTearDown(view.dispose);
      await tester.runAsync(view.run);
      await tester.pump();
      final PlatformWebViewCreationParams params =
          overlay ? browser.overlay! : browser.headless!.params;
      expect(params.initialData, same(data));
      expect(params.initialUrlRequest, isNull);
      expect(params.initialSettings, same(settings));
      expect(
          overlay
              ? browser.overlay!.webViewEnvironment
              : browser.headless!.params.webViewEnvironment,
          same(environment.platform));
      // The wrapper must not change global storage policy to create isolation.
      expect(settings.incognito, false);
      final controller =
          InAppWebViewController.fromPlatform(platform: _Controller());
      params.onWebViewCreated!(controller);
      expect(created, 1);
      final request = URLRequest(url: WebUri('https://example.com'));
      final navigation =
          NavigationAction(request: request, isForMainFrame: true);
      final resource = WebResourceRequest(url: request.url!);
      final window = CreateWindowAction(
          request: request, isForMainFrame: true, windowId: 1);
      final permission = PermissionRequest(
          origin: WebUri('https://example.com'),
          resources: [PermissionResourceType.CAMERA]);
      expect(await params.shouldOverrideUrlLoading!(controller, navigation),
          NavigationActionPolicy.CANCEL);
      expect(await params.shouldInterceptRequest!(controller, resource),
          same(blocked));
      expect(await params.onCreateWindow!(controller, window), false);
      final response =
          await params.onPermissionRequest!(controller, permission);
      expect(response!.action, PermissionResponseAction.DENY);
      expect(response.resources, permission.resources);
      expect(seen, [navigation, resource, window, permission]);
      await tester.runAsync(view.dispose);
      await tester.pump();
      expect(find.byType(InAppWebView, skipOffstage: false), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  test(
      'existing URL-only reader keeps optional policies unset and disposes once',
      () async {
    final previous = InAppWebViewPlatform.instance;
    final browser = _Browser();
    InAppWebViewPlatform.instance = browser;
    addTearDown(() {
      if (previous != null) InAppWebViewPlatform.instance = previous;
    });
    final request = URLRequest(url: WebUri('http://127.0.0.1/reader.html'));
    final view = AnxHeadlessWebView(initialUrlRequest: request);
    await Future.wait([view.run(), view.run()]);
    final params = browser.headless!.params;
    expect(params.initialUrlRequest, same(request));
    expect(params.initialData, isNull);
    expect(params.shouldOverrideUrlLoading, isNull);
    expect(params.shouldInterceptRequest, isNull);
    expect(params.onCreateWindow, isNull);
    expect(params.onPermissionRequest, isNull);
    expect(browser.headless!.runs, 1);
    await Future.wait([view.dispose(), view.dispose()]);
    expect(browser.headless!.disposals, 1);
  });
}
