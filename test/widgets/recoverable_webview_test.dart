import 'package:modu_reader/widgets/webview/recoverable_webview.dart';
import 'package:modu_reader/widgets/webview/webview_hit_region.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

class _Controller extends Fake implements InAppWebViewController {}

class _Page extends StatefulWidget {
  const _Page(this.onDispose);
  final VoidCallback onDispose;
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('web content');
}

void main() {
  testWidgets('macOS protects covered WebViews across nested popups',
      (tester) async {
    var disposals = 0;
    final hitRegions = find.byType(MacOSWebViewHitRegion);
    const outside = Offset(20, 20);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) {
        return Column(children: [
          Expanded(
            child: RecoverableWebView(builder: (_) => _Page(() => disposals++)),
          ),
          TextButton(
            onPressed: () => showModalBottomSheet<void>(
                context: context,
                barrierColor: Colors.transparent,
                builder: (context) => WebViewRouteGuard(
                      child: TextButton(
                          onPressed: () => showDialog<void>(
                                context: context,
                                barrierColor: Colors.transparent,
                                barrierDismissible: false,
                                builder: (context) => AlertDialog(
                                  title: const Text('Blocking dialog'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Confirm'),
                                    ),
                                  ],
                                ),
                              ),
                          child: const Text('Nested dialog')),
                    )),
            child: const Text('Open popup'),
          ),
        ]);
      }),
    )));
    expect(hitRegions, findsNothing);
    await tester.tap(find.text('Open popup'));
    await tester.pumpAndSettle();
    expect(hitRegions, findsOneWidget);

    await tester.tap(find.text('Nested dialog'));
    await tester.pumpAndSettle();
    expect(hitRegions, findsNWidgets(2));
    await tester.tapAt(outside);
    await tester.pumpAndSettle();
    expect(find.text('Blocking dialog'), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(hitRegions, findsOneWidget);
    expect(find.text('Nested dialog'), findsOneWidget);
    await tester.tapAt(outside);
    await tester.pumpAndSettle();
    expect(find.text('Nested dialog'), findsNothing);
    expect(hitRegions, findsNothing);
    expect(disposals, 0);
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets(
      'renderer loss disposes the native subtree; retry creates a new one',
      (tester) async {
    late void Function(InAppWebViewController, RenderProcessGoneDetail) gone;
    var disposals = 0, failures = 0;
    await tester.pumpWidget(MaterialApp(
      home: RecoverableWebView(
        onGone: () => failures++,
        builder: (callback) {
          gone = callback;
          return _Page(() => disposals++);
        },
      ),
    ));
    final stale = gone;
    stale(_Controller(), RenderProcessGoneDetail(didCrash: true));
    stale(_Controller(), RenderProcessGoneDetail(didCrash: true));
    await tester.pump();
    expect(failures, 1);
    expect(disposals, 1);
    expect(find.text('web content'), findsNothing);
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(find.text('web content'), findsOneWidget);
    stale(_Controller(), RenderProcessGoneDetail(didCrash: true));
    await tester.pump();
    expect(failures, 1, reason: 'late callbacks cannot kill the replacement');
    gone(_Controller(), RenderProcessGoneDetail(didCrash: false));
    await tester.pump();
    expect(failures, 2, reason: 'system-killed renderers also need disposal');
    expect(disposals, 2);
    await tester.pumpWidget(const SizedBox());
    gone(_Controller(), RenderProcessGoneDetail(didCrash: true));
    expect(tester.takeException(), isNull);
  });
}
