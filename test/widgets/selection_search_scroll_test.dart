import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:anx_reader/widgets/reading_page/selection_search_browser.dart';
import 'package:anx_reader/widgets/reading_page/selection_search_zoom.dart';
import 'package:anx_reader/service/translate/web_view.dart';
import 'package:anx_reader/widgets/webview/page_zoom_button.dart';
import 'package:anx_reader/widgets/webview/popup_page_layout.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Exercise the production route and native-view configuration without network
// requests. A scrollable test page stands in for the OS-rendered web contents.
class _BrowserPlatform extends InAppWebViewPlatform {
  final scroll = ScrollController();
  PlatformInAppWebViewWidgetCreationParams? latestParams;

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
      PlatformInAppWebViewWidgetCreationParams params) {
    latestParams = params;
    return _BrowserPage(params, scroll);
  }
}

class _BrowserPage extends PlatformInAppWebViewWidget {
  _BrowserPage(super.params, this.scroll) : super.implementation();
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) => ListView.builder(
        key: const ValueKey('web-results'),
        controller: scroll,
        itemExtent: 64,
        itemCount: 80,
        itemBuilder: (_, index) => Text('Result $index'),
      );

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      throw UnimplementedError();

  @override
  void dispose() {}
}

class _ZoomController extends PlatformInAppWebViewController {
  _ZoomController()
      : super.implementation(
            const PlatformInAppWebViewControllerCreationParams(id: 'zoom'));
  final scripts = <UserScript>[];
  final evaluated = <String>[];
  bool failNext = false;

  @override
  Future<void> removeUserScriptsByGroupName({required String groupName}) async {
    scripts.removeWhere((script) => script.groupName == groupName);
  }

  @override
  Future<void> addUserScript({required UserScript userScript}) async {
    scripts.add(userScript);
  }

  @override
  Future<dynamic> evaluateJavascript(
      {required String source, ContentWorld? contentWorld}) async {
    if (failNext) {
      failNext = false;
      throw StateError('Test page navigated during zoom');
    }
    evaluated.add(source);
    return null;
  }

  @override
  Future<bool> canGoBack() async => false;
  @override
  Future<bool> canGoForward() async => false;
  @override
  Future<void> loadUrl(
      {required URLRequest urlRequest,
      Uri? iosAllowingReadAccessTo,
      WebUri? allowingReadAccessTo}) async {}
}

void main() {
  late _BrowserPlatform platform;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final previous = InAppWebViewPlatform.instance;
    platform = _BrowserPlatform();
    InAppWebViewPlatform.instance = platform;
    addTearDown(() {
      if (previous != null) InAppWebViewPlatform.instance = previous;
      platform.scroll.dispose();
    });
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      home: Scaffold(
        body: Builder(
            builder: (context) => Column(children: [
                  TextButton(
                      onPressed: () =>
                          showSelectionSearchBrowser(context, text: '古文'),
                      child: const Text('Search')),
                  TextButton(
                      onPressed: () => showReaderPopup(context,
                          builder: (_) => const Text('Other popup')),
                      child: const Text('Other')),
                ])),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
  }

  testWidgets('search owns native gestures and swipes do not move the sheet',
      (tester) async {
    await open(tester);
    expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).enableDrag, false);
    final recognizers = platform.latestParams!.gestureRecognizers!;
    expect(recognizers, hasLength(1));
    final recognizer = recognizers.single.constructor();
    expect(recognizer, isA<EagerGestureRecognizer>());
    recognizer.dispose();
    // Keep the separate browser unprivileged when changing gesture handling.
    expect(
        platform.latestParams!.initialSettings!.javaScriptBridgeEnabled, false);
    expect(platform.latestParams!.initialSettings!.allowFileAccess, false);
    expect(
        platform.latestParams!.initialSettings!.disableHorizontalScroll, true);
    expect(platform.latestParams!.initialSettings!.horizontalScrollBarEnabled,
        false);
    expect(
        platform.latestParams!.initialSettings!.disableVerticalScroll, false);
    expect(platform.latestParams!.initialSettings!.useWideViewPort, false);

    final body = find.byKey(const ValueKey('reader-popup-body'));
    final before = tester.getRect(body);
    final results = find.byKey(const ValueKey('web-results'));
    await tester.drag(results, const Offset(0, -260));
    await tester.pumpAndSettle();
    final lower = platform.scroll.offset;
    expect(lower, greaterThan(0));
    await tester.drag(results, const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(platform.scroll.offset, lessThan(lower));
    expect(tester.getRect(body), before);

    platform.scroll.jumpTo(0);
    await tester.drag(results, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionSearchBrowser), findsOneWidget);
    expect(tester.getRect(body), before);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('百度').last);
    await tester.pumpAndSettle();
    expect(Prefs().selectionSearchSettings.selectedId, 'baidu');
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionSearchBrowser), findsNothing);

    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).enableDrag, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mouse wheel scrolls search contents without moving the popup',
      (tester) async {
    await open(tester);
    final body = find.byKey(const ValueKey('reader-popup-body'));
    final before = tester.getRect(body);
    await tester.sendEventToBinding(PointerScrollEvent(
      position: tester.getCenter(find.byKey(const ValueKey('web-results'))),
      scrollDelta: const Offset(0, 200),
    ));
    await tester.pumpAndSettle();
    expect(platform.scroll.offset, greaterThan(0));
    expect(tester.getRect(body), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zoom shrinks page, survives navigation and reopen, and resets',
      (tester) async {
    await open(tester);
    final native = _ZoomController();
    final controller = InAppWebViewController.fromPlatform(platform: native);
    platform.latestParams!.onWebViewCreated!(controller);
    expect(platform.latestParams!.initialUserScripts!.single.source,
        selectionSearchZoomScript(100));
    final before = tester.getRect(find.byKey(const ValueKey('web-results')));
    await tester.tap(find.byTooltip('网页缩放'));
    await tester.pumpAndSettle();
    final eighty = find.widgetWithText(CheckedPopupMenuItem<int>, '80%');
    await tester.ensureVisible(eighty);
    await tester.pumpAndSettle();
    await tester.tap(eighty);
    await tester.pumpAndSettle();
    expect(Prefs().selectionSearchZoomPercent, 80);
    expect(native.evaluated.last, selectionSearchZoomScript(80));
    expect(native.scripts.single.forMainFrameOnly, true);
    expect(native.scripts.single.source, selectionSearchZoomScript(80));
    expect(tester.getRect(find.byKey(const ValueKey('web-results'))), before);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('百度').last);
    await tester.pumpAndSettle();
    platform.latestParams!.onLoadStop!(
        controller, WebUri('https://www.baidu.com/'));
    await tester.pumpAndSettle();
    expect(native.evaluated.last, selectionSearchZoomScript(80));
    expect(native.scripts, hasLength(1));
    await tester.drag(
        find.byKey(const ValueKey('web-results')), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(platform.scroll.offset, greaterThan(0));

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(platform.latestParams!.initialUserScripts!.single.source,
        selectionSearchZoomScript(80));
    platform.latestParams!.onWebViewCreated!(controller);
    await tester.tap(find.byTooltip('网页缩放'));
    await tester.pumpAndSettle();
    final reset = find.widgetWithText(CheckedPopupMenuItem<int>, '100%（恢复默认）');
    await tester.ensureVisible(reset);
    await tester.pumpAndSettle();
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(Prefs().selectionSearchZoomPercent, 100);
    expect(native.evaluated.last, selectionSearchZoomScript(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid zoom choices keep latest value and errors allow retry',
      (tester) async {
    await open(tester);
    final native = _ZoomController();
    platform.latestParams!.onWebViewCreated!(
        InAppWebViewController.fromPlatform(platform: native));
    final menu = tester.widget<PopupMenuButton<int>>(
        find.byKey(const ValueKey('search-page-zoom')));
    for (final percent in [50, 200, 70]) {
      menu.onSelected!(percent);
    }
    await tester.pumpAndSettle();
    expect(Prefs().selectionSearchZoomPercent, 70);
    expect(native.evaluated.last, selectionSearchZoomScript(70));
    expect(native.scripts, hasLength(1));
    native.failNext = true;
    menu.onSelected!(80);
    await tester.pumpAndSettle();
    expect(find.text('网页缩放失败，请重试。'), findsOneWidget);
    menu.onSelected!(90);
    await tester.pumpAndSettle();
    expect(native.evaluated.last, selectionSearchZoomScript(90));
    expect(find.text('网页缩放失败，请重试。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'web translation zoom persists, reapplies on navigation and keeps vertical gestures',
      (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> show() async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        home: const Scaffold(
            body: SingleChildScrollView(
                child: WebTranslationView(
          url: 'https://fanyi.baidu.com/m/trans',
          text: 'Original text',
          prefill: '/* seed */',
        ))),
      ));
      await tester.pumpAndSettle();
    }

    await show();
    final native = _ZoomController();
    final controller = InAppWebViewController.fromPlatform(platform: native);
    platform.latestParams!.onWebViewCreated!(controller);
    final settings = platform.latestParams!.initialSettings!;
    expect(settings.disableHorizontalScroll, true);
    expect(settings.horizontalScrollBarEnabled, false);
    expect(settings.disableVerticalScroll, false);
    expect(settings.javaScriptBridgeEnabled, false);
    expect(settings.allowFileAccess, false);
    expect(platform.latestParams!.initialUserScripts!.single.source,
        popupPageLayoutScript(100));
    expect(
        tester
            .getRect(find.byKey(const ValueKey('translation-page-zoom')))
            .bottom,
        lessThanOrEqualTo(
            tester.getRect(find.byKey(const ValueKey('web-results'))).top));
    await tester.tap(find.byTooltip('网页缩放'));
    await tester.pumpAndSettle();
    final eighty = find.widgetWithText(CheckedPopupMenuItem<int>, '80%');
    await tester.ensureVisible(eighty);
    await tester.tap(eighty);
    await tester.pumpAndSettle();
    expect(Prefs().webTranslationZoomPercent, 80);
    expect(Prefs().selectionSearchZoomPercent, 100);
    expect(native.evaluated.last, popupPageLayoutScript(80));
    platform.latestParams!.onLoadStop!(
        controller, WebUri('https://fanyi.baidu.com/m/trans'));
    await tester.pumpAndSettle();
    expect(native.evaluated.take(native.evaluated.length - 1).last,
        popupPageLayoutScript(80));
    expect(native.evaluated.last, '/* seed */');
    await tester.drag(
        find.byKey(const ValueKey('web-results')), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(platform.scroll.offset, greaterThan(0));
    final button = tester.widget<PageZoomButton>(
        find.byKey(const ValueKey('translation-page-zoom')));
    for (final value in [50, 200, 90]) {
      button.onChanged(value);
    }
    await tester.pumpAndSettle();
    expect(native.scripts.single.source, popupPageLayoutScript(90));
    native.failNext = true;
    button.onChanged(100);
    await tester.pumpAndSettle();
    expect(find.text('网页缩放失败，请重试。'), findsOneWidget);
    button.onChanged(110);
    await tester.pumpAndSettle();
    expect(find.text('网页缩放失败，请重试。'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await show();
    expect(platform.latestParams!.initialUserScripts!.single.source,
        popupPageLayoutScript(110));
    expect(tester.takeException(), isNull);
  });
}
