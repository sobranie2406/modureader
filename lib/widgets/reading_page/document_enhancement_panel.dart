import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'reader_menu_group.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/document_enhancement.dart';
import 'widget_title.dart';
import 'package:flutter/material.dart';
import 'package:anx_reader/widgets/reading_page/document_panel_widgets.dart';

/// Preview only until Confirm succeeds. The book file is never modified.
class DocumentEnhancementPanel extends StatefulWidget {
  const DocumentEnhancementPanel(
      {super.key,
      required this.initial,
      required this.render,
      required this.cancelRender,
      this.bottomPanel = false,
      required this.save});
  final bool bottomPanel;
  final DocumentEnhancement initial;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) render;
  final VoidCallback cancelRender;
  final Future<void> Function(DocumentEnhancement) save;
  @override
  State<DocumentEnhancementPanel> createState() =>
      _DocumentEnhancementPanelState();
}

class _DocumentEnhancementPanelState extends State<DocumentEnhancementPanel> {
  late DocumentEnhancement _draft = widget.initial;
  Uint8List? _bytes;
  Uint8List? _originalPreview, _enhancedPreview;
  String? _enhancedKey;
  Timer? _timer;
  int _generation = 0;
  bool _busy = true, _failed = false, _saving = false, _original = false;
  ImageProvider? _image;
  final _previewTransform = TransformationController();
  String tr(String zh, String en) => ModuStrings.text(context, zh, en);
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule({bool comparison = false}) {
    _timer?.cancel();
    widget.cancelRender();
    final generation = ++_generation;
    final key = jsonEncode(_draft.toJson());
    final cached = _original
        ? _originalPreview
        : (_enhancedKey == key ? _enhancedPreview : null);
    if (comparison && cached != null) {
      _image?.evict();
      setState(() {
        _bytes = cached;
        _image = MemoryImage(cached);
        _busy = false;
        _failed = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
    });
    _timer = Timer(const Duration(milliseconds: 150), () async {
      try {
        final result = await widget.render({
          'width': 900,
          'height': 900,
          'region': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
          'rotation': 0,
          'enhancement':
              (_original ? const DocumentEnhancement() : _draft).toJson()
        });
        if (!mounted || generation != _generation) return;
        final url = result['dataUrl'];
        if (url is! String || !url.startsWith('data:image/png;base64,')) {
          throw const FormatException('Invalid image');
        }
        final bytes =
            base64Decode(url.substring('data:image/png;base64,'.length));
        if (_original || !_draft.enabled) _originalPreview = bytes;
        if (!_original) {
          _enhancedKey = key;
          _enhancedPreview = bytes;
        }
        _image?.evict();
        setState(() {
          _bytes = bytes;
          _image = MemoryImage(bytes);
          _busy = false;
        });
      } catch (_) {
        if (mounted && generation == _generation) {
          setState(() {
            _busy = false;
            _failed = true;
          });
        }
      }
    });
  }

  void _change(String key, double value) {
    setState(() {
      _draft = _draft.withValue(key, value);
      _original = false;
    });
    _schedule();
  }

  Future<void> _save() async {
    if (_saving || _busy || _failed) return;
    setState(() => _saving = true);
    try {
      await widget.save(_draft);
      if (!mounted) return;
      setState(() => _saving = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, _draft);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    widget.cancelRender();
    _image?.evict();
    _previewTransform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: Dialog(
          alignment:
              widget.bottomPanel ? Alignment.bottomCenter : Alignment.center,
          insetPadding: EdgeInsets.zero,
          constraints: BoxConstraints(
              maxWidth: widget.bottomPanel ? 1100 : double.infinity),
          child: DocumentPanelTheme(
              child: SizedBox(
                  width: double.infinity,
                  height: MediaQuery.sizeOf(context).height *
                      (widget.bottomPanel
                          ? (MediaQuery.sizeOf(context).height < 480
                              ? .85
                              : .68)
                          : 1),
                  child: SafeArea(
                      child: Column(children: [
                    Row(children: [
                      IconButton(
                          tooltip: tr('返回版式', 'Back to layout'),
                          onPressed:
                              _saving ? null : () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back)),
                      Expanded(
                          child: Text(tr('图像增强', 'Image enhancement'),
                              style: readerSubmenuTitleStyle(context))),
                    ]),
                    SizedBox(
                        key: const ValueKey('enhancement-preview'),
                        height: widget.bottomPanel &&
                                MediaQuery.sizeOf(context).height < 480
                            ? 72
                            : (MediaQuery.sizeOf(context).height *
                                    (widget.bottomPanel ? .28 : .42))
                                .clamp(96.0, 520.0),
                        child: Stack(fit: StackFit.expand, children: [
                          if (_bytes != null)
                            InteractiveViewer(
                                key: const ValueKey('enhancement-preview-zoom'),
                                transformationController: _previewTransform,
                                minScale: 1,
                                maxScale: 4,
                                child: SizedBox.expand(
                                    child: Image(
                                        image: _image!, fit: BoxFit.contain))),
                          if (_busy)
                            const Align(
                                alignment: Alignment.topCenter,
                                child: EinkStaticIndicator(
                                    child: LinearProgressIndicator())),
                        ])),
                    TextButton(
                        onPressed: _saving
                            ? null
                            : () {
                                setState(() => _original = !_original);
                                _schedule(comparison: true);
                              },
                        child: Text(_original
                            ? tr('查看增强', 'Show enhanced')
                            : tr('对照原图', 'Compare original'))),
                    Expanded(
                        child: ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: [
                          ReaderMenuGroup(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  key: ValueKey(
                                      'paper-mode-${_draft.paperMode}'),
                                  initialValue: _draft.paperMode,
                                  decoration: InputDecoration(
                                      labelText:
                                          tr('漂白策略', 'Whitening strategy')),
                                  items: [
                                    DropdownMenuItem(
                                        value: 'preserve',
                                        child: Text(
                                            tr('漫画保色',
                                                'Preserve comic colours'),
                                            overflow: TextOverflow.ellipsis)),
                                    DropdownMenuItem(
                                        value: 'text',
                                        child: Text(
                                            tr('文字扫描净底',
                                                'Clean text scan paper'),
                                            overflow: TextOverflow.ellipsis)),
                                  ],
                                  onChanged: _saving
                                      ? null
                                      : (value) {
                                          if (value == null) return;
                                          setState(() {
                                            _draft =
                                                _draft.withPaperMode(value);
                                            _original = false;
                                          });
                                          _schedule();
                                        },
                                ),
                                SettingHelp(
                                    title: Text(ModuStrings.text(
                                        context, "调整效果", "Adjust enhancement")),
                                    description: Text(tr("调整强度，并对照原图查看效果。",
                                        "Adjust the strength and compare with the original."))),
                              ],
                            ),
                          ),
                          for (final entry
                              in DocumentEnhancement.limits.entries)
                            ReaderMenuGroup(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: DocumentControlRow(
                                  label: switch (entry.key) {
                                    'ink' => tr('文字加黑', 'Stroke strength'),
                                    'contrast' => tr('对比度', 'Contrast'),
                                    'darken' => tr('加黑', 'Darken'),
                                    'whiten' => tr('漂白', 'Paper whitening'),
                                    'watermark' =>
                                      tr('扫描水印减淡', 'Scan watermark fading'),
                                    _ => tr('锐化', 'Sharpen'),
                                  },
                                  child: LayoutBuilder(
                                      builder: (context, constraints) {
                                    return Row(children: [
                                      SizedBox(
                                          width: 36,
                                          child: Text(
                                              '${_draft.values[entry.key]!.round()}',
                                              textAlign: TextAlign.center)),
                                      IconButton(
                                          tooltip: tr('减少', 'Decrease'),
                                          onPressed: _saving
                                              ? null
                                              : () => _change(
                                                  entry.key,
                                                  (_draft.values[entry.key]! -
                                                          1)
                                                      .clamp(entry.value.$1,
                                                          entry.value.$2)),
                                          icon: const Icon(Icons.remove)),
                                      Expanded(
                                          child: Slider(
                                              key: ValueKey(
                                                  'enhancement-${entry.key}'),
                                              value: _draft.values[entry.key]!,
                                              min: entry.value.$1,
                                              max: entry.value.$2,
                                              divisions: (entry.value.$2 -
                                                      entry.value.$1)
                                                  .round(),
                                              onChanged: _saving
                                                  ? null
                                                  : (v) =>
                                                      _change(entry.key, v))),
                                      IconButton(
                                          tooltip: tr('增加', 'Increase'),
                                          onPressed: _saving
                                              ? null
                                              : () => _change(
                                                  entry.key,
                                                  (_draft.values[entry.key]! +
                                                          1)
                                                      .clamp(entry.value.$1,
                                                          entry.value.$2)),
                                          icon: const Icon(Icons.add)),
                                      if (constraints.maxWidth >= 540)
                                        OutlinedButton(
                                            onPressed: _saving
                                                ? null
                                                : () => _change(entry.key, 0),
                                            child: Text(tr('恢复默认', 'Reset')))
                                      else
                                        IconButton(
                                            tooltip: tr('恢复默认', 'Reset'),
                                            onPressed: _saving
                                                ? null
                                                : () => _change(entry.key, 0),
                                            icon:
                                                const Icon(Icons.restart_alt)),
                                    ]);
                                  }),
                                )),
                          SettingHelp(
                              title:
                                  Text(ModuStrings.text(context, '说明', 'Help')),
                              description: Text(tr("淡化纸张底色，改善文字对比。",
                                  "Lighten the paper background to improve text contrast."))),
                          SettingHelp(
                              title:
                                  Text(ModuStrings.text(context, '说明', 'Help')),
                              description: Text(tr("调高可减淡浅色水印，0 为关闭。",
                                  "Increase to lighten faint watermarks. Set to 0 to turn off."))),
                        ])),
                    if (_failed)
                      TextButton(
                          onPressed: _saving ? null : _schedule,
                          child: Text(tr('预览或保存失败，点击重试',
                              'Preview or save failed. Retry'))),
                    OverflowBar(alignment: MainAxisAlignment.end, children: [
                      TextButton(
                          onPressed: _saving
                              ? null
                              : () {
                                  setState(() {
                                    _draft = const DocumentEnhancement();
                                    _original = false;
                                  });
                                  _schedule();
                                },
                          child: Text(tr('全部重置', 'Reset all'))),
                      TextButton(
                          onPressed:
                              _saving ? null : () => Navigator.pop(context),
                          child: Text(tr('取消', 'Cancel'))),
                      FilledButton(
                          onPressed: _saving || _busy || _failed ? null : _save,
                          child: Text(_saving
                              ? tr('保存中…', 'Saving…')
                              : tr('确定', 'Confirm'))),
                    ]),
                    const SizedBox(height: 8),
                  ]))))));
}
