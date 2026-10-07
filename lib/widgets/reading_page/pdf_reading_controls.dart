import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/pdf_reading_view.dart';
import 'package:anx_reader/widgets/reading_page/document_enhancement_panel.dart';
import 'package:anx_reader/models/document_enhancement.dart';
import 'package:flutter/material.dart';
import 'package:anx_reader/widgets/reading_page/document_panel_widgets.dart';

/// Formal reader controls, separate from the temporary crop preview.
class PdfReadingControls extends StatefulWidget {
  const PdfReadingControls(
      {super.key,
      required this.initial,
      required this.save,
      required this.pan,
      this.watermarkAvailable = false,
      this.cropControls,
      this.layoutControls,
      this.preview,
      this.cancelPreview});
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? preview;
  final VoidCallback? cancelPreview;
  final bool watermarkAvailable;
  final Widget? cropControls;
  final Widget? layoutControls;
  final PdfReadingView initial;
  final Future<void> Function(PdfReadingView) save;
  final Future<void> Function(double, double) pan;

  @override
  State<PdfReadingControls> createState() => _PdfReadingControlsState();
}

class _PdfReadingControlsState extends State<PdfReadingControls> {
  late PdfReadingView _view = widget.initial;
  late double _zoom = _view.zoom;
  late double _autoSeconds = _view.display.autoSeconds.toDouble();
  bool _busy = false;
  String? _error;

  @override
  void didUpdateWidget(covariant PdfReadingControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy) {
      _view = widget.initial;
      _zoom = _view.zoom;
      _autoSeconds = _view.display.autoSeconds.toDouble();
    }
  }

  Future<void> _apply(PdfReadingView next) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.save(next);
      if (mounted) setState(() => _view = next);
    } catch (_) {
      if (mounted) {
        setState(() => _error = ModuStrings.text(
            context, '调整失败，请重试', 'Could not apply. Please retry.'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _zoom = _view.zoom;
          _autoSeconds = _view.display.autoSeconds.toDouble();
        });
      }
    }
  }

  Future<void> _pan(double x, double y) async {
    try {
      await widget.pan(x, y);
    } catch (_) {
      if (mounted) {
        setState(() => _error = ModuStrings.text(
            context, '移动失败，请重试', 'Could not move. Please retry.'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String text(String zh, String en) => ModuStrings.text(context, zh, en);
    Widget button(IconData icon, String label, VoidCallback action) =>
        IconButton(
            tooltip: label, onPressed: _busy ? null : action, icon: Icon(icon));
    Widget choices(Map<String, String> options, String selected,
            ValueChanged<String> change) =>
        Wrap(
          spacing: 0,
          runSpacing: 4,
          children: [
            for (final option in options.entries)
              ChoiceChip(
                selectedColor: Theme.of(context).colorScheme.primary,
                checkmarkColor: Theme.of(context).colorScheme.onPrimary,
                label: Text(option.value,
                    style: TextStyle(
                        color: selected == option.key
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSurface)),
                selected: selected == option.key,
                onSelected: _busy ? null : (_) => change(option.key),
              ),
          ],
        );
    Future<void> enhance() async {
      if (_busy || widget.preview == null) return;
      final result = await showDialog<DocumentEnhancement>(
        animationStyle: AppMotion.style,
        context: context,
        builder: (_) => DocumentEnhancementPanel(
          bottomPanel: true,
          initial: _view.enhancement,
          render: widget.preview!,
          cancelRender: widget.cancelPreview ?? () {},
          save: (value) => widget.save(_view.copyWith(enhancement: value)),
        ),
      );
      if (mounted && result != null) {
        setState(() => _view = _view.copyWith(enhancement: result));
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DocumentControlRow(
          label: text('缩放', 'Original page zoom'),
          child: Row(children: [
            Text('${(_zoom * 100).round()}%'),
            button(
                Icons.remove,
                text('缩小', 'Zoom out'),
                () => _apply(
                    _view.copyWith(zoom: (_view.zoom - .25).clamp(1.0, 15.0)))),
            Expanded(
                child: Slider(
              value: _zoom,
              min: 1,
              max: 15,
              divisions: 56,
              label: '${(_zoom * 100).round()}%',
              onChanged: _busy ? null : (v) => setState(() => _zoom = v),
              onChangeEnd:
                  _busy ? null : (v) => _apply(_view.copyWith(zoom: v)),
            )),
            button(
                Icons.add,
                text('放大', 'Zoom in'),
                () => _apply(
                    _view.copyWith(zoom: (_view.zoom + .25).clamp(1.0, 15.0)))),
          ]),
        ),
        DocumentControlRow(
          label: text('模式', 'Mode'),
          child: Wrap(spacing: 16, runSpacing: 6, children: [
            choices({
              'single': text('单页', 'Single page'),
              'scroll': text('连续卷轴', 'Continuous scroll')
            }, _view.mode, (v) => _apply(_view.copyWith(mode: v))),
            choices({
              'screen': text('适应屏幕', 'Fit screen'),
              'width': text('适应屏宽', 'Fit width')
            }, _view.fit, (v) => _apply(_view.copyWith(fit: v, zoom: 1))),
          ]),
        ),
        if (widget.cropControls != null)
          DocumentControlRow(
              label: text('裁边', 'Crop'), child: widget.cropControls!),
        if (widget.layoutControls != null)
          DocumentControlRow(
              label: text('版式', 'Layout'), child: widget.layoutControls!),
        if (widget.preview != null)
          DocumentControlRow(
            label: text('图像增强', 'Image enhancement'),
            child: Wrap(spacing: 4, runSpacing: 4, children: [
              for (final entry in {
                'ink': text('文字加黑', 'Stroke strength'),
                'contrast': text('对比度', 'Contrast'),
                'darken': text('加黑', 'Darken'),
                'whiten': text('漂白', 'Paper whitening'),
                'sharpen': text('锐化', 'Sharpen'),
                'watermark': text('扫描水印减淡', 'Scan watermark fading'),
              }.entries)
                OutlinedButton(
                  onPressed: _busy ? null : enhance,
                  child: Text(
                      '${entry.value} ${_view.enhancement.values[entry.key]!.round()}'),
                ),
            ]),
          ),
        DocumentControlRow(
          label: text('旋屏', 'Rotation'),
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            button(
                Icons.rotate_left,
                text('左转 90°', 'Rotate left'),
                () => _apply(
                    _view.copyWith(rotation: (_view.rotation + 270) % 360))),
            Text('${_view.rotation}°'),
            button(
                Icons.rotate_right,
                text('右转 90°', 'Rotate right'),
                () => _apply(
                    _view.copyWith(rotation: (_view.rotation + 90) % 360))),
            TextButton(
                onPressed: _busy
                    ? null
                    : () => _apply(PdfReadingView(
                        mode: _view.mode,
                        enhancement: _view.enhancement,
                        display: _view.display)),
                child: Text(text('恢复适屏', 'Reset view'))),
          ]),
        ),
        if (_error != null)
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ExpansionTile(
            title: Text(text('更多原版阅读设置', 'More original-page settings')),
            children: [
              DocumentControlRow(
                label: text('移动视口', 'Move viewport'),
                child: Wrap(children: [
                  button(Icons.arrow_back, text('向左', 'Move left'),
                      () => _pan(-160, 0)),
                  button(Icons.arrow_upward, text('向上', 'Move up'),
                      () => _pan(0, -160)),
                  button(Icons.arrow_downward, text('向下', 'Move down'),
                      () => _pan(0, 160)),
                  button(Icons.arrow_forward, text('向右', 'Move right'),
                      () => _pan(160, 0)),
                ]),
              ),
              for (final entry in {
                'border': text('页面边界线', 'Page border'),
                if (widget.watermarkAvailable)
                  'hideWatermarks': text('隐藏独立水印图层（仅显示）',
                      'Hide named watermark layers (display only)'),
                'separators': text('卷轴页面间隔', 'Space between scroll pages'),
                'grayscale': text(
                    '灰度显示（应用内 256 级）', 'Grayscale display (256 app levels)'),
                'tapPan':
                    text('放大时先滚屏，再翻页', 'Pan enlarged pages before turning'),
                'swipeMenu': text('上滑显示菜单', 'Swipe up for menu'),
              }.entries)
                SwitchListTile(
                    title: Text(entry.value),
                    value: _view.display.toJson()[entry.key] as bool,
                    subtitle: entry.key == 'swipeMenu'
                        ? Text(text('仅单页、100% 且未使用上下翻页时生效',
                            'Only in single-page mode at 100%, without vertical swiping'))
                        : entry.key == 'grayscale'
                            ? Text(text('不改变屏幕硬件灰阶能力',
                                'Does not change the screen’s native grayscale capability'))
                            : null,
                    onChanged: _busy ||
                            (entry.key == 'swipeMenu' &&
                                _view.display.swipe == 'vertical')
                        ? null
                        : (value) => _apply(_view.copyWith(
                            display: _view.display.change(entry.key, value)))),
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: DropdownButtonFormField<String>(
                      initialValue: _view.display.swipe,
                      decoration: InputDecoration(
                          labelText: text('滑动翻页', 'Swipe navigation')),
                      items: {
                        'horizontal': text('左右', 'Horizontal'),
                        'reverse': text('左右反向', 'Reversed horizontal'),
                        'vertical': text('上下', 'Vertical'),
                        'tap': text('仅点击', 'Tap only'),
                      }
                          .entries
                          .map((e) => DropdownMenuItem(
                              value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (value) {
                              if (value != null) {
                                _apply(_view.copyWith(
                                    display:
                                        _view.display.change('swipe', value)));
                              }
                            })),
              SwitchListTile(
                  title: Text(text('自动翻页', 'Automatic page turning')),
                  subtitle: Text(text('后台、菜单、输入和文字选择期间暂停',
                      'Paused in background, menus, text input and selections')),
                  value: _view.display.autoSeconds > 0,
                  onChanged: _busy
                      ? null
                      : (enabled) => _apply(_view.copyWith(
                          display: _view.display
                              .change('autoSeconds', enabled ? 30 : 0)))),
              if (_view.display.autoSeconds > 0)
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      Expanded(
                          child: Slider(
                              value: _autoSeconds.clamp(5, 600),
                              min: 5,
                              max: 600,
                              divisions: 119,
                              label: '${_autoSeconds.round()}s',
                              onChanged: _busy
                                  ? null
                                  : (value) =>
                                      setState(() => _autoSeconds = value),
                              onChangeEnd: _busy
                                  ? null
                                  : (value) => _apply(_view.copyWith(
                                      display: _view.display.change(
                                          'autoSeconds', value.round()))))),
                      Text('${_autoSeconds.round()}s'),
                    ])),
            ]),
      ]),
    );
  }
}
