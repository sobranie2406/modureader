import 'reader_menu_appearance.dart';
import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'reader_menu_group.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/pdf_reading_view.dart';
import 'package:modu_reader/widgets/reading_page/document_enhancement_panel.dart';
import 'package:modu_reader/models/document_enhancement.dart';
import 'package:flutter/material.dart';
import 'package:modu_reader/widgets/reading_page/document_panel_widgets.dart';

/// Formal reader controls, separate from the temporary crop preview.
class PdfReadingControls extends StatefulWidget {
  const PdfReadingControls(
      {super.key,
      required this.initial,
      required this.save,
      this.watermarkAvailable = false,
      this.cropControls,
      this.preview,
      this.cancelPreview});
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? preview;
  final VoidCallback? cancelPreview;
  final bool watermarkAvailable;
  final Widget? cropControls;
  final PdfReadingView initial;
  final Future<void> Function(PdfReadingView) save;

  @override
  State<PdfReadingControls> createState() => _PdfReadingControlsState();
}

class _PdfReadingControlsState extends State<PdfReadingControls> {
  late PdfReadingView _view = widget.initial;
  bool _busy = false;
  String? _error;

  @override
  void didUpdateWidget(covariant PdfReadingControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy) {
      _view = widget.initial;
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
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String text(String zh, String en) => ModuStrings.text(context, zh, en);
    Widget section(String title, IconData icon, List<Widget> children) =>
        ReaderMenuGroup(
            child: ExpansionTile(
          title: Text(title),
          leading: Icon(icon),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 12),
          children: children,
        ));
    Widget button(IconData icon, String label, VoidCallback action) =>
        IconButton(
            tooltip: label, onPressed: _busy ? null : action, icon: Icon(icon));
    Widget choices(Map<String, String> options, String selected,
            ValueChanged<String> change) =>
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options.entries)
              ChoiceChip(
                selectedColor: Prefs().eInkMode
                    ? Colors.transparent
                    : Theme.of(context).colorScheme.primary,
                checkmarkColor: Prefs().eInkMode
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onPrimary,
                label: Text(option.value,
                    style: TextStyle(
                        color: selected == option.key && !Prefs().eInkMode
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSurface)),
                selected: selected == option.key,
                onSelected: _busy ? null : (_) => change(option.key),
              ),
          ],
        );
    Future<void> enhance() async {
      if (_busy || widget.preview == null) return;
      final result = await showReaderDialog<DocumentEnhancement>(
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

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      section(text('页面适配', 'Page fit'), Icons.fit_screen, [
        DocumentControlRow(
          label: text('页面适配', 'Page fit'),
          child: choices({
            'screen': text('适应屏幕', 'Fit screen'),
            'width': text('适应屏宽', 'Fit width')
          }, _view.fit, (v) => _apply(_view.copyWith(fit: v, zoom: 1))),
        ),
      ]),
      if (widget.cropControls != null)
        ReaderMenuGroup(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: widget.cropControls!),
      if (widget.preview != null)
        ReaderMenuGroup(
            padding: const EdgeInsets.all(12),
            child: DocumentControlRow(
              label: text('图像增强', 'Image enhancement'),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                        icon: const Icon(Icons.tune),
                        onPressed: _busy ? null : enhance,
                        label: Text(text('调整图像效果', 'Adjust image effects'))),
                    const SizedBox(height: 8),
                    Text(
                        {
                          'ink': text('文字加黑', 'Stroke strength'),
                          'contrast': text('对比度', 'Contrast'),
                          'darken': text('加黑', 'Darken'),
                          'whiten': text('漂白', 'Paper whitening'),
                          'sharpen': text('锐化', 'Sharpen'),
                          'watermark': text('扫描水印减淡', 'Scan watermark fading'),
                        }
                            .entries
                            .map((entry) =>
                                '${entry.value} ${_view.enhancement.values[entry.key]!.round()}')
                            .join(' · '),
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
            )),
      section(text('旋屏', 'Rotation'), Icons.screen_rotation, [
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
        )
      ]),
      if (_error != null)
        Text(_error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ReaderMenuGroup(
          child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: const Icon(Icons.swipe),
              title: Text(text('翻页与相关选项', 'Page turning and options')),
              children: [
            DocumentControlRow(
              label: text('翻页方式', 'Page turning'),
              child: choices({
                'single': text('单页', 'Single page'),
                'scroll': text('连续卷轴', 'Continuous scroll')
              }, _view.mode, (v) => _apply(_view.copyWith(mode: v))),
            ),
            for (final entry in {
              'border': text('页面边界线', 'Page border'),
              if (widget.watermarkAvailable)
                'hideWatermarks': text('隐藏独立水印图层（仅显示）',
                    'Hide named watermark layers (display only)'),
              'separators': text('卷轴页面间隔', 'Space between scroll pages'),
            }.entries)
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value),
                  value: _view.display.toJson()[entry.key] as bool,
                  onChanged: _busy
                      ? null
                      : (value) => _apply(_view.copyWith(
                          display: _view.display.change(entry.key, value)))),
          ])),
    ]);
  }
}
