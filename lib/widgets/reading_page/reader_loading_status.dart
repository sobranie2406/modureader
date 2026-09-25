import 'package:flutter/material.dart';

/// Only the explicit retry button receives input; the status is not a modal.
class ReaderLoadingStatus extends StatelessWidget {
  const ReaderLoadingStatus(
      {super.key, required this.failed, this.fontFailed = false, this.onRetry});

  final bool failed;
  final bool fontFailed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // Loading is silent: no card, spinner or hit-test layer over the book.
    if (!failed) return const SizedBox.shrink();
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final showRetry = onRetry != null;
    return Center(
      child: Stack(alignment: Alignment.bottomCenter, children: [
        IgnorePointer(
            child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IgnorePointer(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    fontFailed
                        ? (zh
                            ? '本章使用的字体加载失败，请重试或切换章节。'
                            : 'A chapter font failed to load. Retry or select another chapter.')
                        : (zh
                            ? '章节加载失败，请重试或切换章节。'
                            : 'Chapter loading failed. Retry or select another chapter.'),
                    textAlign: TextAlign.center,
                  ),
                ])),
                if (showRetry) const SizedBox(height: 48),
              ],
            ),
          ),
        )),
        if (showRetry)
          Positioned(
              bottom: 20,
              child: TextButton(
                  onPressed: onRetry, child: Text(zh ? '重试' : 'Retry'))),
      ]),
    );
  }
}
