import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/service/tts/base_tts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'dart:math' as math;

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
    required this.onStop,
    required this.onOpenSettings,
    this.floating = false,
  });

  final ValueListenable<TtsStateEnum> stateListenable;
  final AsyncCallback onReturnToPosition;
  final AsyncCallback onReadHere;
  final AsyncCallback onPrevious;
  final AsyncCallback onNext;
  final AsyncCallback onPlay;
  final AsyncCallback onPause;
  final AsyncCallback onStop;
  final VoidCallback onOpenSettings;
  final bool floating;

  @override
  State<TtsQuickToolbar> createState() => _TtsQuickToolbarState();
}

class _TtsQuickToolbarState extends State<TtsQuickToolbar> {
  bool _busy = false;
  Offset? _position;

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
        final hereLabel = ModuStrings.text(context, '此页朗读', 'Read from here');

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
              style: IconButton.styleFrom(
                minimumSize: const Size(44, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
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
        final returnButton = iconButton('tts-quick-return', returnLabel,
            Icons.my_location_rounded, widget.onReturnToPosition);
        final hereButton = iconButton('tts-quick-read-here', hereLabel,
            Icons.play_lesson_outlined, widget.onReadHere);
        final stop = iconButton(
            'tts-quick-stop',
            ModuStrings.text(context, '停止朗读', 'Stop narration'),
            Icons.stop_circle_outlined,
            widget.onStop);

        return LayoutBuilder(builder: (context, constraints) {
          final width = widget.floating
              ? math.min(440.0, math.max(0.0, constraints.maxWidth - 24))
              : constraints.maxWidth;
          final compact = width < 7 * 44;
          final height = compact ? 88.0 : 44.0;
          final padding = MediaQuery.viewPaddingOf(context);
          final minY = math.min(
              padding.top + 12, math.max(0.0, constraints.maxHeight - height));
          final maxX = math.max(12.0, constraints.maxWidth - width - 12);
          final maxY = math.max(
              minY, constraints.maxHeight - height - padding.bottom - 24);
          Offset clampPosition(Offset offset) => Offset(
              offset.dx.clamp(12.0, maxX).toDouble(),
              offset.dy.clamp(minY, maxY).toDouble());
          final position = clampPosition(
              _position ?? Offset((constraints.maxWidth - width) / 2, maxY));
          final bar = PointerInterceptor(
              child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: widget.floating
                      ? (details) => setState(() => _position = clampPosition(
                          clampPosition(_position ?? position) + details.delta))
                      : null,
                  child: SizedBox(
                    key: const ValueKey('tts-quick-toolbar'),
                    width: width,
                    height: height,
                    child: Material(
                      color: colors.surfaceContainer.withValues(alpha: 0.2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                          side: BorderSide(
                              color: colors.outlineVariant
                                  .withValues(alpha: 0.5))),
                      clipBehavior: Clip.antiAlias,
                      child: compact
                          ? Column(children: [
                              Expanded(
                                  child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [returnButton, hereButton])),
                              Expanded(
                                  child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
                                      children: [
                                    settings,
                                    previous,
                                    playPause,
                                    next,
                                    stop,
                                  ])),
                            ])
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                  settings,
                                  returnButton,
                                  previous,
                                  playPause,
                                  next,
                                  hereButton,
                                  stop,
                                ]),
                    ),
                  )));
          if (!widget.floating) return bar;
          return Stack(children: [
            Positioned(
                left: position.dx, top: position.dy, width: width, child: bar),
          ]);
        });
      },
    );
  }
}
