import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:pointer_interceptor/pointer_interceptor.dart';

class PdfZoomToolbar extends StatefulWidget {
  const PdfZoomToolbar(
      {super.key, required this.zoom, required this.change, this.boxZoom});
  final ValueNotifier<double> zoom;
  final Future<void> Function(double zoom, bool reset) change;
  final Future<void> Function(bool enabled)? boxZoom;
  @override
  State<PdfZoomToolbar> createState() => _PdfZoomToolbarState();
}

class _PdfZoomToolbarState extends State<PdfZoomToolbar> {
  bool _busy = false, _box = false, _collapsed = false, _hidden = false;
  Timer? _hideTimer;
  int _activityId = 0;
  Alignment _alignment = const Alignment(0, .9);

  @override
  void initState() {
    super.initState();
    widget.zoom.addListener(_activity);
    _activity();
  }

  @override
  void didUpdateWidget(covariant PdfZoomToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoom != widget.zoom) {
      oldWidget.zoom.removeListener(_activity);
      widget.zoom.addListener(_activity);
    }
  }

  void _activity() {
    final activity = ++_activityId;
    _hideTimer?.cancel();
    if (_hidden && mounted) setState(() => _hidden = false);
    _hideTimer = Timer(const Duration(seconds: 5), () async {
      if (!mounted) return;
      if (_busy || _box) {
        _activity();
        return;
      }
      if (mounted && activity == _activityId) setState(() => _hidden = true);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.zoom.removeListener(_activity);
    if (_box) unawaited(widget.boxZoom?.call(false).catchError((Object _) {}));
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    _activity();
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ModuStrings.text(
                context, '调整失败，请重试', 'Could not apply. Please retry.'))));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _activity();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    String t(String zh, String en) => ModuStrings.text(context, zh, en);
    return SafeArea(
        child: Padding(
            padding: const EdgeInsets.all(8),
            child: LayoutBuilder(
                builder: (context, bounds) => Align(
                      alignment: _alignment,
                      child: GestureDetector(
                          onPanUpdate: (event) {
                            _activity();
                            setState(() => _alignment = Alignment(
                                (_alignment.x +
                                        event.delta.dx * 2 / bounds.maxWidth)
                                    .clamp(-1.0, 1.0),
                                (_alignment.y +
                                        event.delta.dy * 2 / bounds.maxHeight)
                                    .clamp(-1.0, 1.0)));
                          },
                          child: PointerInterceptor(
                              child: Material(
                            elevation: 0,
                            borderRadius: BorderRadius.circular(28),
                            color: Theme.of(context)
                                .colorScheme
                                .surface
                                .withValues(alpha: .20),
                            child: ValueListenableBuilder<double>(
                                valueListenable: widget.zoom,
                                builder: (context, zoom, _) => Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (!_collapsed) ...[
                                            IconButton(
                                                tooltip: t('缩小', 'Zoom out'),
                                                icon: const Icon(Icons.remove),
                                                onPressed: _busy || zoom <= 1
                                                    ? null
                                                    : () => _run(() =>
                                                        widget.change(
                                                            (zoom - .25)
                                                                .clamp(1, 8),
                                                            false))),
                                            Text('${zoom.toStringAsFixed(1)}×'),
                                            IconButton(
                                                tooltip: t('放大', 'Zoom in'),
                                                icon: const Icon(Icons.add),
                                                onPressed: _busy || zoom >= 8
                                                    ? null
                                                    : () => _run(() =>
                                                        widget.change(
                                                            (zoom + .25)
                                                                .clamp(1, 8),
                                                            false))),
                                            IconButton(
                                                tooltip: t('恢复原样（保留裁边）',
                                                    'Reset zoom (keep crop)'),
                                                icon: const Icon(
                                                    Icons.restart_alt),
                                                onPressed: _busy
                                                    ? null
                                                    : () => _run(() => widget
                                                        .change(1, true))),
                                            if (widget.boxZoom != null)
                                              IconButton(
                                                  tooltip: t(
                                                      '框选放大', 'Rectangle zoom'),
                                                  isSelected: _box,
                                                  icon: const Stack(
                                                      alignment:
                                                          Alignment.center,
                                                      children: [
                                                        Icon(Icons.crop_free),
                                                        Icon(Icons.zoom_in,
                                                            size: 16),
                                                      ]),
                                                  onPressed: _busy
                                                      ? null
                                                      : () => _run(() async {
                                                            await widget
                                                                    .boxZoom!(
                                                                !_box);
                                                            if (mounted) {
                                                              setState(() =>
                                                                  _box = !_box);
                                                            }
                                                          })),
                                          ],
                                          IconButton(
                                              tooltip: _collapsed
                                                  ? t('展开缩放', 'Show zoom')
                                                  : t('收起缩放', 'Hide zoom'),
                                              icon: Icon(_collapsed
                                                  ? Icons.zoom_in
                                                  : Icons.expand_more),
                                              onPressed: () {
                                                _activity();
                                                setState(() =>
                                                    _collapsed = !_collapsed);
                                              }),
                                        ])),
                          ))),
                    ))));
  }
}
