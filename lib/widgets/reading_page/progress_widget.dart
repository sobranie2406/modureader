import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/reader_progress.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:flutter/material.dart';

class ProgressWidget extends StatelessWidget {
  const ProgressWidget({super.key, required this.epubPlayerKey});
  final GlobalKey<EpubPlayerState> epubPlayerKey;

  @override
  Widget build(BuildContext context) {
    final player = epubPlayerKey.currentState;
    if (player == null) return const SizedBox.shrink();
    return ValueListenableBuilder<ReaderProgress>(
      valueListenable: player.readingProgress,
      builder: (context, progress, _) => ReadingProgressControls(
        progress: progress,
        onSeek: player.goToPercentage,
        onPreviousChapter: player.prevChapter,
        onPreviousPage: player.prevPage,
        onNextPage: player.nextPage,
        onNextChapter: player.nextChapter,
      ),
    );
  }
}

/// Preview locally while dragging; navigate only when the thumb is released.
/// Reader relocation notifications keep the slider and page counters current.
class ReadingProgressControls extends StatefulWidget {
  const ReadingProgressControls({
    super.key,
    required this.progress,
    required this.onSeek,
    required this.onPreviousChapter,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onNextChapter,
  });
  final ReaderProgress progress;
  final Future<void> Function(double) onSeek;
  final VoidCallback onPreviousChapter,
      onPreviousPage,
      onNextPage,
      onNextChapter;

  @override
  State<ReadingProgressControls> createState() =>
      _ReadingProgressControlsState();
}

class _ReadingProgressControlsState extends State<ReadingProgressControls> {
  double? _dragProgress;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final progress = widget.progress;
    final fraction = (_dragProgress ?? progress.percentage).clamp(0.0, 1.0);
    final target = _dragProgress == null ? null : progress.chapterAt(fraction);
    final title = target == null
        ? progress.chapterTitle
        : '${target.title.isEmpty ? l10n.readingPageChapterNumber(target.number) : target.title} (${target.number}/${progress.totalChapters})';
    Widget button(
            String key, String tooltip, IconData icon, VoidCallback action) =>
        IconButton(
          key: ValueKey(key),
          tooltip: tooltip,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints.tightFor(width: 40, height: 48),
          style: const ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          icon: Icon(icon),
          onPressed: progress.isReady ? action : null,
        );

    return Padding(
      key: const ValueKey('reader-progress-panel'),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 10),
        Text(
          title.isEmpty && progress.currentChapter > 0
              ? l10n.readingPageChapterNumber(progress.currentChapter)
              : title,
          key: const ValueKey('reader-progress-chapter-title'),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const Divider(),
        Row(children: [
          button('reader-previous-chapter', l10n.readingPagePreviousChapter,
              Icons.skip_previous, widget.onPreviousChapter),
          button('reader-previous-page', l10n.readingPagePreviousPage,
              Icons.chevron_left, widget.onPreviousPage),
          Expanded(
            child: Slider(
              key: const ValueKey('reader-progress-slider'),
              inactiveColor: Colors.grey.shade300,
              value: fraction,
              label: title,
              onChangeStart: progress.isReady
                  ? (value) => setState(() => _dragProgress = value)
                  : null,
              onChanged: progress.isReady
                  ? (value) => setState(() => _dragProgress = value)
                  : null,
              onChangeEnd: progress.isReady
                  ? (value) async {
                      setState(() => _dragProgress = null);
                      await widget.onSeek(value);
                    }
                  : null,
            ),
          ),
          button('reader-next-page', l10n.readingPageNextPage,
              Icons.chevron_right, widget.onNextPage),
          button('reader-next-chapter', l10n.readingPageNextChapter,
              Icons.skip_next, widget.onNextChapter),
        ]),
        Row(children: [
          ProgressDisplay(
            mainText: progress.totalPages > 0 ? '${progress.currentPage}' : '—',
            subText: l10n.readingPageCurrentPage,
          ),
          ProgressDisplay(
            mainText: progress.totalPages > 0 ? '${progress.totalPages}' : '—',
            subText: l10n.readingPageChapterPages,
          ),
          ProgressDisplay(
            mainText: (fraction * 100).toStringAsFixed(2),
            subText: '%',
          ),
        ]),
        const SizedBox(height: 10),
      ]),
    );
  }
}

class ProgressDisplay extends StatelessWidget {
  const ProgressDisplay(
      {super.key, required this.mainText, required this.subText});
  final String mainText, subText;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(mainText,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Text(subText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11)),
        ]),
      );
}
