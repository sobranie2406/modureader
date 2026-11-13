import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/utils/log/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// A dead Android renderer must be removed, never reloaded or reused.
class RecoverableWebView extends StatefulWidget {
  const RecoverableWebView({super.key, required this.builder, this.onGone});

  final Widget Function(
          void Function(InAppWebViewController, RenderProcessGoneDetail) onGone)
      builder;
  final VoidCallback? onGone;

  @override
  State<RecoverableWebView> createState() => _RecoverableWebViewState();
}

class _RecoverableWebViewState extends State<RecoverableWebView> {
  bool _gone = false;
  int _generation = 0;

  @override
  Widget build(BuildContext context) {
    if (_gone) {
      return Center(
        child: TextButton.icon(
          icon: const Icon(Icons.refresh),
          label: Text(ModuStrings.text(context, '阅读组件已停止，点击重新加载',
              'Web content stopped. Tap to reload.')),
          onPressed: () => setState(() {
            _generation++;
            _gone = false;
          }),
        ),
      );
    }
    final generation = _generation;
    return KeyedSubtree(
      key: ValueKey(generation),
      child: widget.builder((_, detail) {
        if (!mounted || _gone || generation != _generation) return;
        AnxLog.warning('WebView renderer gone: didCrash=${detail.didCrash}');
        setState(() => _gone = true);
        widget.onGone?.call();
      }),
    );
  }
}
