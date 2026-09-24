import 'package:flutter/material.dart';

/// Informational only: never place an input-blocking surface over the WebView.
class ReaderLoadingStatus extends StatelessWidget {
  const ReaderLoadingStatus({super.key, required this.failed});

  final bool failed;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return IgnorePointer(
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!failed) ...[
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  failed
                      ? (zh
                          ? '书籍加载失败或超时，请返回书架重试。'
                          : 'Book loading failed or timed out. Return to the shelf and retry.')
                      : (zh ? '正在打开书籍…' : 'Opening book…'),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
