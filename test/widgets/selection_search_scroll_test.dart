import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:anx_reader/widgets/reading_page/selection_search_browser.dart';
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
}
