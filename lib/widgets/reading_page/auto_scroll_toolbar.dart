import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/service/reader_auto_scroll.dart';
import 'package:modu_reader/service/reader_toolbar_visibility.dart';
import 'package:modu_reader/widgets/reading_page/reader_menu_appearance.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

class AutoScrollToolbar extends StatefulWidget {
  const AutoScrollToolbar(
      {super.key,
      required this.controller,
      required this.visibility,
      required this.onStart,
      required this.onClose,
      this.onEditingChanged});
  final ReaderAutoScroll controller;
  final ReaderToolbarVisibility visibility;
  final VoidCallback onStart, onClose;
  final ValueChanged<bool>? onEditingChanged;

  @override
  State<AutoScrollToolbar> createState() => _AutoScrollToolbarState();
}

class _AutoScrollToolbarState extends State<AutoScrollToolbar> {
  Offset? _position;

  Future<void> _editSpeed() async {
    widget.onEditingChanged?.call(true);
    widget.visibility.hold(true);
    try {
      Future<dynamic>? closed;
      final value = await showReaderDialog<double>(
          context: context,
          builder: (context) {
            closed = ModalRoute.of(context)?.completed;
            return _ScrollSpeedDialog(speed: widget.controller.speed);
          });
      // Resume only after the editor and its keyboard focus have left the route.
      await closed;
      if (mounted && value != null) widget.controller.setSpeed(value);
    } finally {
      widget.visibility.hold(false);
      if (mounted) widget.onEditingChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge([widget.controller, widget.visibility]),
      builder: (context, _) {
        if (!widget.visibility.visible) return const SizedBox.shrink();
        final colors = Theme.of(context).colorScheme;
        Widget button(String name, IconData icon, String label,
                VoidCallback? action) =>
            IconButton(
                key: ValueKey('auto-scroll-$name'),
                tooltip: label,
                icon: Icon(icon, size: 22),
                color: colors.primary,
                constraints:
                    const BoxConstraints.tightFor(width: 44, height: 44),
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                onPressed: action == null
                    ? null
                    : () {
                        widget.visibility.reveal();
                        action();
                      });
        return LayoutBuilder(builder: (context, constraints) {
          final width =
              math.min(340.0, math.max(0.0, constraints.maxWidth - 24));
          final padding = MediaQuery.viewPaddingOf(context);
          final minY = math.min(
              padding.top + 12, math.max(0.0, constraints.maxHeight - 44));
          final maxY =
              math.max(minY, constraints.maxHeight - 44 - padding.bottom - 24);
          Offset clamp(Offset value) => Offset(
              value.dx.clamp(
                  12.0, math.max(12.0, constraints.maxWidth - width - 12)),
              value.dy.clamp(minY, maxY));
          final position = clamp(
              _position ?? Offset((constraints.maxWidth - width) / 2, maxY));
          return Stack(children: [
            Positioned(
              left: position.dx,
              top: position.dy,
              width: width,
              child: PointerInterceptor(
                  child: Listener(
                onPointerDown: (_) => widget.visibility.hold(true),
                onPointerUp: (_) => widget.visibility.hold(false),
                onPointerCancel: (_) => widget.visibility.hold(false),
                child: GestureDetector(
                  onPanUpdate: (details) => setState(
                      () => _position = clamp(position + details.delta)),
                  child: Material(
                    key: const ValueKey('auto-scroll-toolbar'),
                    color: colors.surfaceContainer.withValues(alpha: .2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                        side: BorderSide(
                            color:
                                colors.outlineVariant.withValues(alpha: .5))),
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(
                        height: 44,
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              const SizedBox(
                                  width: 24,
                                  child: Icon(Icons.drag_indicator, size: 20)),
                              button(
                                  'play-pause',
                                  widget.controller.running
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  ModuStrings.text(
                                      context,
                                      widget.controller.running
                                          ? '暂停滚动'
                                          : '开始滚动',
                                      widget.controller.running
                                          ? 'Pause scrolling'
                                          : 'Start scrolling'),
                                  widget.controller.active &&
                                          !widget.controller.running
                                      ? null
                                      : widget.controller.running
                                          ? widget.controller.stop
                                          : widget.onStart),
                              const SizedBox(
                                  height: 16, child: VerticalDivider(width: 1)),
                              button(
                                  'decrease',
                                  Icons.remove_rounded,
                                  ModuStrings.text(
                                      context, '降低 0.1', 'Decrease by 0.1'),
                                  widget.controller.speed <= .1
                                      ? null
                                      : () => widget.controller.setSpeed(
                                          widget.controller.speed - .1)),
                              SizedBox(
                                  width: 56,
                                  child: TextButton(
                                      key: const ValueKey('auto-scroll-speed'),
                                      style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero),
                                      onPressed: _editSpeed,
                                      child: Text(
                                          '${widget.controller.speed.toStringAsFixed(1)}×',
                                          textScaler: TextScaler.noScaling,
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: colors.onSurface)))),
                              button(
                                  'increase',
                                  Icons.add_rounded,
                                  ModuStrings.text(
                                      context, '提高 0.1', 'Increase by 0.1'),
                                  widget.controller.speed >= 4
                                      ? null
                                      : () => widget.controller.setSpeed(
                                          widget.controller.speed + .1)),
                              const SizedBox(
                                  height: 16, child: VerticalDivider(width: 1)),
                              button(
                                  'close',
                                  Icons.close_rounded,
                                  ModuStrings.text(
                                      context, '关闭自动滚动', 'Close auto scroll'),
                                  widget.onClose),
                            ])),
                  ),
                ),
              )),
            )
          ]);
        });
      });
}

class _ScrollSpeedDialog extends StatefulWidget {
  const _ScrollSpeedDialog({required this.speed});
  final double speed;
  @override
  State<_ScrollSpeedDialog> createState() => _ScrollSpeedDialogState();
}

class _ScrollSpeedDialogState extends State<_ScrollSpeedDialog> {
  late final input =
      TextEditingController(text: widget.speed.toStringAsFixed(1));
  String? error;
  void submit() {
    final value = double.tryParse(input.text.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite || value < .1 || value > 4) {
      setState(() =>
          error = ModuStrings.text(context, '请输入 0.1～4.0', 'Enter 0.1–4.0'));
    } else {
      Navigator.pop(context, value);
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(ModuStrings.text(context, '滚动倍速', 'Scroll speed')),
          content: TextField(
              key: const ValueKey('auto-scroll-speed-input'),
              controller: input,
              autofocus: true,
              textAlign: TextAlign.center,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(suffixText: '×', errorText: error),
              onTap: () => input.selection =
                  TextSelection(baseOffset: 0, extentOffset: input.text.length),
              onSubmitted: (_) => submit()),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
            TextButton(
                onPressed: submit,
                child: Text(ModuStrings.text(context, '确定', 'OK'))),
          ]);
}
