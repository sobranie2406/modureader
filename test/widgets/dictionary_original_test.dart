import 'dart:io';

import 'package:anx_reader/service/dictionary/local_dictionary.dart';
import 'package:anx_reader/widgets/dictionary/dictionary_original.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDictionaryBrowser extends InAppWebViewPlatform {
  PlatformInAppWebViewWidgetCreationParams? params;
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
      PlatformInAppWebViewWidgetCreationParams params) {
    this.params = params;
    return _View(params);
  }
}

class _View extends PlatformInAppWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox(key: ValueKey('html'));
  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      throw UnimplementedError();
  @override
  void dispose() {}
}

class _Controller extends PlatformInAppWebViewController {
  _Controller()
      : super.implementation(const PlatformInAppWebViewControllerCreationParams(
            id: 'dictionary'));
  num height = 80;
  int reads = 0;
  @override
  Future<dynamic> evaluateJavascript(
      {required String source, ContentWorld? contentWorld}) async {
    reads++;
    return height;
  }
}

void main() {
  testWidgets(
      'inline original resizes, isolates content and falls back in place',
      (tester) async {
    final previous = InAppWebViewPlatform.instance;
    final browser = FakeDictionaryBrowser();
    InAppWebViewPlatform.instance = browser;
    addTearDown(() {
      if (previous != null) InAppWebViewPlatform.instance = previous;
    });
    final temp = Directory.systemTemp.createTempSync('modu-inline-dict-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ValueListenableBuilder<bool>(
                valueListenable: active,
                builder: (_, enabled, child) =>
                    TickerMode(enabled: enabled, child: child!),
                child: SingleChildScrollView(
                    child: DictionaryOriginal(
                        store: LocalDictionaryStore(temp.path),
                        entry: const DictionaryEntry(
                            'Demo', 'word', '例句\n\nexample',
                            dictionaryId: 'test', html: '<p>example</p>')))))));
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && browser.params == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });
    expect(browser.params, isNotNull);
    final settings = browser.params!.initialSettings!;
    expect(settings.javaScriptBridgeEnabled, false);
    expect(settings.allowFileAccess, false);
    expect(settings.allowContentAccess, false);
    expect(settings.mediaPlaybackRequiresUserGesture, true);
    final native = _Controller();
    final controller = InAppWebViewController.fromPlatform(platform: native);
    browser.params!.onWebViewCreated!(controller);
    browser.params!.onLoadStop!(
        controller, browser.params!.initialUrlRequest!.url);
    await tester.pump();
    expect(tester.getSize(find.byKey(const ValueKey('html'))).height, 82);
    native.height = 380;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(tester.getSize(find.byKey(const ValueKey('html'))).height, 382);
    native.height = 40;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(tester.getSize(find.byKey(const ValueKey('html'))).height, 42);
    active.value = false;
    await tester.pump();
    final reads = native.reads;
    await tester.pump(const Duration(seconds: 3));
    expect(native.reads, reads);
    active.value = true;
    await tester.pump();
    native.height = 50000;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(tester.getSize(find.byKey(const ValueKey('html'))).height, 8000);
    expect(browser.params!.gestureRecognizers, isNotEmpty);
    browser.params!.onReceivedError!(
        controller,
        WebResourceRequest(
            url: browser.params!.initialUrlRequest!.url!, isForMainFrame: true),
        WebResourceError(
            type: WebResourceErrorType.UNKNOWN, description: 'test'));
    await tester.pump();
    expect(find.text('例句\nexample'), findsOneWidget);
    expect(find.byType(InAppWebView), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
