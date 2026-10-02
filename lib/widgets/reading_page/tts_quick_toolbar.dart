import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// A small overlay, never an inset that changes the reader's viewport.
class TtsQuickToolbar extends StatefulWidget {
  const TtsQuickToolbar({
    super.key,
    required this.stateListenable,
    required this.onReturnToPosition,
    required this.onReadHere,
    required this.onPlay,
    required this.onPause,
    required this.onOpenSettings,
  });

  final ValueListenable<TtsStateEnum> stateListenable;
  final AsyncCallback onReturnToPosition;
  final AsyncCallback onReadHere;
  final AsyncCallback onPlay;
  final AsyncCallback onPause;
  final VoidCallback onOpenSettings;

  @override
  State<TtsQuickToolbar> createState() => _TtsQuickToolbarState();
}

class _TtsQuickToolbarState extends State<TtsQuickToolbar> {
  bool _busy = false;

  Future<void> _run(AsyncCallback action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(ModuStrings.text(
              context, '朗读操作失败，请重试', 'Narration action failed. Please retry.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TtsStateEnum>(
      valueListenable: widget.stateListenable,
      builder: (context, state, _) {
        if (state != TtsStateEnum.playing && state != TtsStateEnum.paused) {
          return const SizedBox.shrink();
        }
        final playing = state == TtsStateEnum.playing;
        final colors = Theme.of(context).colorScheme;
        final l10n = L10n.of(context);
        final returnLabel =
            ModuStrings.text(context, '回到朗读位置', 'Return to narration');
        final hereLabel = ModuStrings.text(context, '从此处朗读', 'Read from here');

        Widget labelButton(String key, String label, AsyncCallback action) =>
            Expanded(
              child: Tooltip(
                message: label,
                child: TextButton(
                  key: ValueKey(key),
                  onPressed: _busy ? null : () => _run(action),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: colors.onSurface,
                  ),
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
            );

        return PointerInterceptor(
          child: SizedBox(
            key: const ValueKey('tts-quick-toolbar'),
            height: 44,
            child: Material(
              color: colors.surfaceContainer.withValues(alpha: 0.96),
              shape: StadiumBorder(
                  side: BorderSide(
                      color: colors.outlineVariant.withValues(alpha: 0.5))),
              clipBehavior: Clip.antiAlias,
              child: Row(children: [
                IconButton(
                  key: const ValueKey('tts-quick-settings'),
                  tooltip: l10n.settingsNarrate,
                  constraints:
                      const BoxConstraints.tightFor(width: 44, height: 44),
                  padding: EdgeInsets.zero,
                  iconSize: 19,
                  onPressed: _busy ? null : widget.onOpenSettings,
                  icon: const Icon(Icons.headphones_outlined),
                ),
                labelButton(
                    'tts-quick-return', returnLabel, widget.onReturnToPosition),
                IconButton(
                  key: const ValueKey('tts-quick-play-pause'),
                  tooltip: playing ? l10n.commonPause : l10n.commonResume,
                  constraints:
                      const BoxConstraints.tightFor(width: 44, height: 44),
                  padding: EdgeInsets.zero,
                  iconSize: 22,
                  onPressed: _busy
                      ? null
                      : () => _run(playing ? widget.onPause : widget.onPlay),
                  icon: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                ),
                labelButton(
                    'tts-quick-read-here', hereLabel, widget.onReadHere),
              ]),
            ),
          ),
        );
      },
    );
  }
}
