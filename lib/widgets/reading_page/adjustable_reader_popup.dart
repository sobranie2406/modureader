import 'reader_menu_appearance.dart';
import 'dart:math' as math;

import 'package:anx_reader/config/shared_preference_provider.dart';

import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/widgets/common/app_scroll_behavior.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

Future<void> showAdjustableReaderPopup(BuildContext context,
    {required WidgetBuilder builder,
    bool readerAppearance = true,
    Rect? selectionRect,
    Color? barrierColor,
    double initialHeightFraction = 0.8}) async {
  final navigator = Navigator.of(context);
  final overlayBox =
      navigator.overlay?.context.findRenderObject() as RenderBox?;
  final localSelection = selectionRect == null || overlayBox == null
      ? selectionRect
      : Rect.fromPoints(overlayBox.globalToLocal(selectionRect.topLeft),
          overlayBox.globalToLocal(selectionRect.bottomRight));
  final menuTheme = readerAppearance
      ? ReaderMenuAppearance.theme(context)
      : Theme.of(context);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  // The builder and its state must survive dragging, keyboard and viewport changes.
  final content = Builder(builder: builder);
  final route = RawDialogRoute<void>(
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor ??
        Theme.of(context).bottomSheetTheme.modalBarrierColor ??
        Colors.black54,
    transitionDuration: AppMotion.duration(const Duration(milliseconds: 200)),
    pageBuilder: (context, animation, secondaryAnimation) => themes.wrap(
      Theme(
          data: menuTheme,
          child: AdjustableReaderPopup(
              initialHeightFraction: initialHeightFraction,
              selectionRect: localSelection,
              child: content)),
    ),
  );
  await navigator.push(route);
  // Restore native reader focus only after the reverse transition has finished.
  await route.completed;
}

/// Geometry belongs to this route only, never to preferences or a shared cache.
class AdjustableReaderPopup extends StatefulWidget {
  const AdjustableReaderPopup(
      {super.key,
      required this.child,
      this.initialHeightFraction = 0.8,
      this.selectionRect});
  final Widget child;
  final double initialHeightFraction;
  final Rect? selectionRect;

  @override
  State<AdjustableReaderPopup> createState() => _AdjustableReaderPopupState();
}

class _AdjustableReaderPopupState extends State<AdjustableReaderPopup> {
  Rect? _rect;
  Rect? _gestureRect;
  Offset? _gestureOrigin;

  double _maxHeight(Size available) => math.min(
      available.height,
      MediaQuery.sizeOf(context).height *
          Prefs().readerPopupMaxHeightPercent /
          100);

  Rect _fit(Rect rect, Size available) {
    final width = rect.width
        .clamp(math.min(320.0, available.width), available.width)
        .toDouble();
    final height = rect.height
        .clamp(math.min(320.0, _maxHeight(available)), _maxHeight(available))
        .toDouble();
    return Rect.fromLTWH(rect.left.clamp(0.0, available.width - width),
        rect.top.clamp(0.0, available.height - height), width, height);
  }

  void _update(Offset position, String edge, Size available) {
    final start = _gestureRect;
    final origin = _gestureOrigin;
    if (start == null || origin == null) return;
    final delta = position - origin;
    Rect next;
    if (edge == 'move') {
      next = _fit(start.shift(delta), available);
    } else {
      final minWidth = math.min(320.0, available.width);
      final minHeight = math.min(320.0, _maxHeight(available));
      var left = start.left, right = start.right;
      var top = start.top, bottom = start.bottom;
      if (edge.contains('left')) {
        left = (left + delta.dx).clamp(0.0, right - minWidth);
      }
      if (edge.contains('right')) {
        right = (right + delta.dx).clamp(left + minWidth, available.width);
      }
      if (edge.contains('top')) {
        top = (top + delta.dy).clamp(
            math.max(0.0, bottom - _maxHeight(available)), bottom - minHeight);
      }
      if (edge.contains('bottom')) {
        bottom = (bottom + delta.dy).clamp(top + minHeight,
            math.min(available.height, top + _maxHeight(available)));
      }
      next = Rect.fromLTRB(left, top, right, bottom);
    }
    setState(() => _rect = next);
  }

  Widget _handle(String edge, Rect rect, Size available,
      {required MouseCursor cursor, Widget? child}) {
    final label = edge == 'move'
        ? ModuStrings.text(context, '移动弹窗', 'Move popup')
        : ModuStrings.text(context, '调整弹窗大小', 'Resize popup');
    return Semantics(
      label: label,
      // Assistive technology can adjust the window without precision dragging.
      onIncrease: () {
        _gestureRect = rect;
        _gestureOrigin = Offset.zero;
        _update(const Offset(24, 24), edge, available);
      },
      onDecrease: () {
        _gestureRect = rect;
        _gestureOrigin = Offset.zero;
        _update(const Offset(-24, -24), edge, available);
      },
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          key: ValueKey('reader-popup-$edge'),
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            _gestureRect = rect;
            _gestureOrigin = details.globalPosition;
          },
          onPanUpdate: (details) =>
              _update(details.globalPosition, edge, available),
          onPanEnd: (_) => _gestureRect = null,
          onPanCancel: () => _gestureRect = null,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    // Both the keyboard and physical screen edges constrain the entire frame.
    return Padding(
      padding: EdgeInsets.fromLTRB(
          media.padding.left + 8,
          media.padding.top + 8,
          media.padding.right + 8,
          math.max(media.viewInsets.bottom, media.padding.bottom) + 8),
      child: LayoutBuilder(builder: (context, constraints) {
        final available = constraints.biggest;
        if (available.isEmpty) return const SizedBox.shrink();
        final maxWidth = theme.bottomSheetTheme.constraints?.maxWidth ??
            (theme.useMaterial3 ? 640.0 : available.width);
        final width = math.min(maxWidth, available.width);
        final height = math.min(
            media.size.height * widget.initialHeightFraction, available.height);
        final anchor = widget.selectionRect
            ?.shift(-Offset(media.padding.left + 8, media.padding.top + 8));
        var initial = Rect.fromLTWH((available.width - width) / 2,
            available.height - height, width, height);
        if (anchor != null) {
          final below = available.height - anchor.bottom - 12;
          final above = anchor.top - 12;
          final placeBelow = below >= above;
          final popupHeight =
              math.min(height, math.max(320.0, placeBelow ? below : above));
          initial = Rect.fromLTWH(
              anchor.center.dx - width / 2,
              placeBelow ? anchor.bottom + 12 : anchor.top - 12 - popupHeight,
              width,
              popupHeight);
        }
        final rect = _fit(_rect ?? initial, available);
        return Stack(children: [
          if (anchor != null &&
              (Offset.zero & available).overlaps(anchor) &&
              !rect.overlaps(anchor))
            Positioned.fill(
                child: IgnorePointer(
                    child: CustomPaint(
              key: const ValueKey('reader-popup-selection-arrow'),
              painter: _SelectionArrow(anchor, rect, theme.colorScheme.outline),
            ))),
          Positioned.fromRect(
            key: const ValueKey('reader-popup-position'),
            rect: rect,
            child: PointerInterceptor(
              child: Material(
                key: const ValueKey('adjustable-reader-popup-frame'),
                color: theme.bottomSheetTheme.backgroundColor ??
                    theme.colorScheme.surface,
                elevation: theme.bottomSheetTheme.elevation ?? 4,
                shape: theme.bottomSheetTheme.shape ??
                    RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                clipBehavior: Clip.antiAlias,
                child: Stack(children: [
                  Padding(
                    // Reserve resize hit areas; they never cover text or buttons.
                    padding: const EdgeInsets.fromLTRB(12, 24, 12, 24),
                    child: Column(children: [
                      SizedBox(
                          height: 36,
                          child: Row(children: [
                            Expanded(
                                child: _handle('move', rect, available,
                                    cursor: SystemMouseCursors.move,
                                    child: Center(
                                        child: Container(
                                            width: 40,
                                            height: 4,
                                            decoration: BoxDecoration(
                                                color:
                                                    theme.colorScheme.outline,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        2)))))),
                            IconButton(
                              key: const ValueKey('reader-popup-close'),
                              tooltip: MaterialLocalizations.of(context)
                                  .closeButtonTooltip,
                              padding: EdgeInsets.zero,
                              iconSize: 20,
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close),
                            ),
                          ])),
                      Expanded(
                          child: LayoutBuilder(builder: (context, constraints) {
                        // A short landscape/keyboard viewport must still allow
                        // access to tool headers and input controls.
                        final contentHeight =
                            math.max(240.0, constraints.maxHeight);
                        return SingleChildScrollView(
                          primary: false,
                          child: SizedBox(
                            height: contentHeight,
                            child: MediaQuery(
                              data: MediaQuery.of(context)
                                  .removeViewInsets(removeBottom: true)
                                  .copyWith(
                                      size: Size(
                                          constraints.maxWidth, contentHeight),
                                      padding: EdgeInsets.zero,
                                      viewPadding: EdgeInsets.zero),
                              child: RepaintBoundary(
                                  child: ScrollConfiguration(
                                      behavior: const AppScrollBehavior(
                                          symmetricGutter: true),
                                      child: widget.child)),
                            ),
                          ),
                        );
                      })),
                    ]),
                  ),
                  Positioned(
                      left: 0,
                      top: 24,
                      bottom: 24,
                      width: 12,
                      child: _handle('left', rect, available,
                          cursor: SystemMouseCursors.resizeLeftRight)),
                  Positioned(
                      right: 0,
                      top: 24,
                      bottom: 24,
                      width: 12,
                      child: _handle('right', rect, available,
                          cursor: SystemMouseCursors.resizeLeftRight)),
                  Positioned(
                      left: 24,
                      right: 24,
                      bottom: 0,
                      height: 12,
                      child: _handle('bottom', rect, available,
                          cursor: SystemMouseCursors.resizeUpDown)),
                  for (final edge in [
                    'top-left',
                    'top-right',
                    'bottom-left',
                    'bottom-right'
                  ])
                    Positioned(
                        left: edge.contains('left') ? 0 : null,
                        right: edge.contains('right') ? 0 : null,
                        top: edge.contains('top') ? 0 : null,
                        bottom: edge.contains('bottom') ? 0 : null,
                        width: 24,
                        height: 24,
                        child: _handle(edge, rect, available,
                            cursor: edge == 'top-left' || edge == 'bottom-right'
                                ? SystemMouseCursors.resizeUpLeftDownRight
                                : SystemMouseCursors.resizeUpRightDownLeft)),
                ]),
              ),
            ),
          ),
        ]);
      }),
    );
  }
}

class _SelectionArrow extends CustomPainter {
  const _SelectionArrow(this.anchor, this.popup, this.color);
  final Rect anchor;
  final Rect popup;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final below = popup.center.dy >= anchor.center.dy;
    final target = below ? anchor.bottomCenter : anchor.topCenter;
    final x = target.dx.clamp(popup.left + 24, popup.right - 24).toDouble();
    final y = below ? popup.top : popup.bottom;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(x, y), target, paint);
    final direction = (Offset(x, y) - target).direction;
    final path = Path()
      ..moveTo(target.dx + 8 * math.cos(direction - 0.5),
          target.dy + 8 * math.sin(direction - 0.5))
      ..lineTo(target.dx, target.dy)
      ..lineTo(target.dx + 8 * math.cos(direction + 0.5),
          target.dy + 8 * math.sin(direction + 0.5));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SelectionArrow oldDelegate) =>
      anchor != oldDelegate.anchor ||
      popup != oldDelegate.popup ||
      color != oldDelegate.color;
}
