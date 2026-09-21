// Manual native-input regression. Serve vertical-input.html and reader sources
// from an isolated localhost fixture directory, then run with:
// flutter run -d macos -t test/fixtures/mac_vertical_input_harness.dart
// No app initialization, preferences, library or sync services are used.
import 'package:anx_reader/widgets/reading_page/vertical_page_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void main() => runApp(const MaterialApp(home: _Harness()));

class _Harness extends StatefulWidget {
  const _Harness();
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool legacyOverlay = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(
              legacyOverlay ? 'Legacy Flutter overlay' : 'Fixed web chrome'),
          actions: [
            TextButton(
                onPressed: () => setState(() => legacyOverlay = !legacyOverlay),
                child: const Text('Toggle overlay')),
          ],
        ),
        body: Stack(children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
                url: WebUri(
                    'http://127.0.0.1:8769/test/fixtures/vertical-input.html')),
          ),
          if (legacyOverlay)
            const VerticalPageChrome(
              geometry: VerticalPageGeometry(EdgeInsets.zero, 12, 12),
              chapterTitle: 'Test',
              remainingPages: 40,
              currentPage: 1,
              totalPages: 100,
              color: Colors.black,
              redFrame: true,
            ),
        ]),
      );
}
