import 'package:modu_reader/widgets/webview/recoverable_webview.dart';
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
