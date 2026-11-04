import 'package:flutter/material.dart';

/// Keep both reader elements in place when rotating or toggling comparison.
/// In particular, never recreate the source WebView to show the original page.
class DocumentComparisonView extends StatefulWidget {
  const DocumentComparisonView({
    super.key,
    required this.original,
    this.reflow,
    this.compare = false,
    required this.onOriginalInteraction,
    required this.onReflowInteraction,
  });

  final Widget original;
  final Widget? reflow;
  final bool compare;
  final VoidCallback onOriginalInteraction, onReflowInteraction;

  @override
  State<DocumentComparisonView> createState() => _DocumentComparisonViewState();
}

class _DocumentComparisonViewState extends State<DocumentComparisonView> {
  double _originalFraction = .5;

  @override
  void didUpdateWidget(covariant DocumentComparisonView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.compare || widget.reflow == null) _originalFraction = .5;
  }

  void _resize(double fraction) {
    final next = fraction.clamp(.2, .8);
    if (next != _originalFraction) {
      setState(() => _originalFraction = next);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
        final split = widget.compare && widget.reflow != null;
        final horizontal = size.maxWidth > size.maxHeight;
        final width = size.maxWidth;
        final height = size.maxHeight;
        final extent = horizontal ? width : height;
        final dividerExtent = extent.clamp(0.0, 24.0);
        final available = extent - dividerExtent;
        final sourceWidth =
            split && horizontal ? available * _originalFraction : width;
        final sourceHeight =
            split && !horizontal ? available * _originalFraction : height;
        void drag(DragUpdateDetails details) {
          if (available > 0) {
            _resize(_originalFraction + details.primaryDelta! / available);
          }
        }

        final label = Localizations.localeOf(context).languageCode == 'zh'
            ? '拖动调整原文与重排比例'
            : 'Drag to resize original and reflow';
        return Stack(children: [
          Positioned(
            left: 0,
            top: 0,
            width: sourceWidth,
            height: sourceHeight,
            child: Visibility(
              visible: widget.reflow == null || split,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: true,
              child: ClipRect(
                child: Listener(
                  onPointerDown: (_) => widget.onOriginalInteraction(),
                  onPointerSignal: (_) => widget.onOriginalInteraction(),
                  child: widget.original,
                ),
              ),
            ),
          ),
          if (widget.reflow != null)
            Positioned(
              left: split && horizontal ? sourceWidth + dividerExtent : 0,
              top: split && !horizontal ? sourceHeight + dividerExtent : 0,
              right: 0,
              bottom: 0,
              child: ClipRect(
                child: Listener(
                  onPointerDown: (_) => widget.onReflowInteraction(),
                  onPointerSignal: (_) => widget.onReflowInteraction(),
                  child: widget.reflow!,
                ),
              ),
            ),
          if (split)
            Positioned(
              left: horizontal ? sourceWidth : 0,
              top: horizontal ? 0 : sourceHeight,
              width: horizontal ? dividerExtent : width,
              height: horizontal ? height : dividerExtent,
              child: Semantics(
                label: label,
                value: '${(_originalFraction * 100).round()}%',
                increasedValue:
                    '${((_originalFraction + .05).clamp(.2, .8) * 100).round()}%',
                decreasedValue:
                    '${((_originalFraction - .05).clamp(.2, .8) * 100).round()}%',
                onIncrease: () => _resize(_originalFraction + .05),
                onDecrease: () => _resize(_originalFraction - .05),
                child: MouseRegion(
                  cursor: horizontal
                      ? SystemMouseCursors.resizeColumn
                      : SystemMouseCursors.resizeRow,
                  child: GestureDetector(
                    key: const ValueKey('document-comparison-divider'),
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: horizontal ? drag : null,
                    onVerticalDragUpdate: horizontal ? null : drag,
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surface,
                      child: Center(
                        child: Container(
                          width: horizontal ? 4 : 36,
                          height: horizontal ? 36 : 4,
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]);
      });
}
