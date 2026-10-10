import 'dart:async';

import 'package:anx_reader/page/home_page.dart' show webViewEnvironment;
import 'package:anx_reader/service/dictionary/dictionary_document.dart';
import 'package:anx_reader/service/dictionary/local_dictionary.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dictionary_common.dart';

/// Inline original content, isolated from the reader and its application bridge.
class DictionaryOriginal extends StatefulWidget {
  const DictionaryOriginal(
      {super.key, required this.store, required this.entry});
  final LocalDictionaryStore store;
  final DictionaryEntry entry;
  @override
  State<DictionaryOriginal> createState() => _DictionaryOriginalState();
}

class _DictionaryOriginalState extends State<DictionaryOriginal> {
  DictionaryDocument? document;
  InAppWebViewController? controller;
  Timer? timer;
  bool failed = false, measuring = false;
  double height = 48;
  double fontSize = 14;
  String foreground = '202124';
  // ponytail: cap native surface size; exceptionally long entries scroll inside.
  static const maxHeight = 8000.0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    fontSize = MediaQuery.textScalerOf(context).scale(14);
    foreground = (Theme.of(context).colorScheme.onSurface.toARGB32() & 0xffffff)
        .toRadixString(16)
        .padLeft(6, '0');
    timer?.cancel();
    // Read layout from the host, never expose a JS handler to dictionary scripts.
    if (TickerMode.valuesOf(context).enabled) {
      timer = Timer.periodic(const Duration(seconds: 1), (_) => _measure());
    }
  }

  Future<void> _open() async {
    try {
      final result = await DictionaryDocument.open(widget.store, widget.entry);
      if (!mounted) {
        await result.close();
        return;
      }
      setState(() => document = result);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  Future<void> _measure() async {
    if (!mounted || failed || measuring || controller == null) return;
    measuring = true;
    try {
      final result = await controller!.evaluateJavascript(source: '''
        (() => {
          const b = document.body;
          if (!b) return 0;
          b.style.fontSize = '${fontSize}px';
          b.style.color = '#$foreground';
          return Math.ceil(Math.max(b.getBoundingClientRect().height, b.scrollHeight));
        })()
      ''');
      if (!mounted || result is! num || !result.isFinite || result <= 0) return;
      final next = (result.toDouble() + 2).clamp(24.0, maxHeight);
      if ((next - height).abs() >= 1) setState(() => height = next);
    } catch (_) {
      // Navigation/disposal can race layout reads. Keep the last known height.
    } finally {
      measuring = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    controller = null;
    document?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            dictionaryLabel(context, '原版加载失败，显示文字释义。',
                'Original unavailable; showing text.'),
            style: Theme.of(context).textTheme.bodySmall),
        SelectableText(compactDictionaryText(widget.entry.definition),
            style: const TextStyle(fontSize: 14, height: 1.4)),
      ]);
    }
    if (document == null) {
      return Text(dictionaryLabel(context, '正在加载图文…', 'Loading content…'),
          style: Theme.of(context).textTheme.bodySmall);
    }
    return SizedBox(
      height: height,
      child: InAppWebView(
        webViewEnvironment: webViewEnvironment,
        initialUrlRequest: URLRequest(url: WebUri(document!.uri.toString())),
        gestureRecognizers: height >= maxHeight
            ? {
                Factory<VerticalDragGestureRecognizer>(
                    VerticalDragGestureRecognizer.new)
              }
            : const {},
        initialSettings: InAppWebViewSettings(
          javaScriptBridgeEnabled: false,
          javaScriptCanOpenWindowsAutomatically: false,
          supportMultipleWindows: true,
          useShouldOverrideUrlLoading: true,
          allowFileAccess: false,
          allowContentAccess: false,
          allowFileAccessFromFileURLs: false,
          allowUniversalAccessFromFileURLs: false,
          mediaPlaybackRequiresUserGesture: true,
          transparentBackground: true,
        ),
        onWebViewCreated: (value) => controller = value,
        onLoadStop: (_, __) => _measure(),
        onContentSizeChanged: (_, __, ___) => _measure(),
        shouldOverrideUrlLoading: (_, action) async =>
            document!.allows(action.request.url)
                ? NavigationActionPolicy.ALLOW
                : NavigationActionPolicy.CANCEL,
        onCreateWindow: (_, __) async => false,
        onPermissionRequest: (_, request) async => PermissionResponse(
            resources: request.resources,
            action: PermissionResponseAction.DENY),
        onReceivedError: (_, request, __) {
          if (request.isForMainFrame == true && mounted) {
            setState(() => failed = true);
          }
        },
      ),
    );
  }
}
