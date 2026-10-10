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
    required this.onPrevious,
    required this.onNext,
    required this.onPlay,
    required this.onPause,
    required this.onOpenSettings,
  });

  final ValueListenable<TtsStateEnum> stateListenable;
  final AsyncCallback onReturnToPosition;
  final AsyncCallback onReadHere;
  final AsyncCallback onPrevious;
  final AsyncCallback onNext;
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
            ModuStrings.text(context, '回朗读页', 'Return to narration');
        final hereLabel = ModuStrings.text(context, '此页开始', 'Read from here');

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

        Widget iconButton(String key, String label, IconData icon,
                AsyncCallback action) =>
            IconButton(
              key: ValueKey(key),
              tooltip: label,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              padding: EdgeInsets.zero,
              iconSize: 22,
              color: key == 'tts-quick-play-pause'
                  ? colors.primary
                  : colors.onSurface,
              onPressed: _busy ? null : () => _run(action),
              icon: Icon(icon),
            );

        final settings = iconButton('tts-quick-settings', l10n.settingsNarrate,
            Icons.headphones_outlined, () async => widget.onOpenSettings());
        final previous = iconButton(
            'tts-quick-previous',
            ModuStrings.text(context, '上一段', 'Previous passage'),
            Icons.chevron_left_rounded,
            widget.onPrevious);
        final playPause = iconButton(
            'tts-quick-play-pause',
            playing ? l10n.commonPause : l10n.commonResume,
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            playing ? widget.onPause : widget.onPlay);
        final next = iconButton(
            'tts-quick-next',
            ModuStrings.text(context, '下一段', 'Next passage'),
            Icons.chevron_right_rounded,
            widget.onNext);
        final returnButton = labelButton(
            'tts-quick-return', returnLabel, widget.onReturnToPosition);
        final hereButton =
            labelButton('tts-quick-read-here', hereLabel, widget.onReadHere);

        double labelWidth(String label) {
          final painter = TextPainter(
              text: TextSpan(text: label, style: const TextStyle(fontSize: 12)),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context))
            ..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        return PointerInterceptor(
          child: LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth <
                4 * 44 + 24 + labelWidth(returnLabel) + labelWidth(hereLabel);
            return SizedBox(
              key: const ValueKey('tts-quick-toolbar'),
              height: compact ? 88 : 44,
              child: Material(
                color: colors.surfaceContainer.withValues(alpha: 0.96),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                    side: BorderSide(
                        color: colors.outlineVariant.withValues(alpha: 0.5))),
                clipBehavior: Clip.antiAlias,
                child: compact
                    ? Column(children: [
                        Expanded(
                            child: Row(children: [returnButton, hereButton])),
                        Expanded(
                            child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                              settings,
                              previous,
                              playPause,
                              next
                            ])),
                      ])
                    : Row(children: [
                        settings,
                        returnButton,
                        previous,
                        playPause,
                        next,
                        hereButton,
                      ]),
              ),
            );
          }),
        );
      },
    );
  }
}
