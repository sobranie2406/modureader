import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:flutter/material.dart';

/// Shared entry point in vector settings and the bookshelf's live queue.
class StopVectorizationButton extends StatefulWidget {
  const StopVectorizationButton({
    super.key,
    this.compact = false,
    this.queue,
    this.onStop,
  });

  final bool compact;
  final BookKnowledgeIndexQueue? queue;
  final Future<void> Function()? onStop;

  @override
  State<StopVectorizationButton> createState() =>
      _StopVectorizationButtonState();
}

class _StopVectorizationButtonState extends State<StopVectorizationButton> {
  bool _stopping = false;

  Future<void> _stop() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    try {
      await (widget.onStop?.call() ??
          stopBookVectorization(queue: widget.queue));
    } catch (_) {
      if (mounted) {
        AnxToast.show(ModuStrings.text(context, '停止向量化未完成，请重试',
            'Could not finish stopping indexing. Please retry.'));
      }
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = widget.queue ?? bookKnowledgeIndexQueue;
    return AnimatedBuilder(
      animation: queue,
      builder: (context, _) {
        final active = queue.activeItems;
        final stopping = _stopping ||
            (active.isNotEmpty &&
                active.every((item) =>
                    item.status == BookKnowledgeQueueStatus.cancelling));
        final label = stopping
            ? ModuStrings.text(context, '正在停止…', 'Stopping…')
            : ModuStrings.text(context, '停止向量化', 'Stop indexing');
        final onPressed = active.isNotEmpty && !stopping ? _stop : null;
        if (widget.compact) {
          return IconButton(
            tooltip: label,
            onPressed: onPressed,
            icon: const Icon(Icons.stop_circle_outlined),
          );
        }
        return OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.stop_circle_outlined),
          label: Text(label),
        );
      },
    );
  }
}
