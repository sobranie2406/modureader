import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/document_enhancement.dart';
import 'package:flutter/material.dart';

/// Preview only until Confirm succeeds. The book file is never modified.
class DocumentEnhancementPanel extends StatefulWidget {
  const DocumentEnhancementPanel(
      {super.key,
      required this.initial,
      required this.render,
      required this.cancelRender,
      required this.save});
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
  Timer? _timer;
  int _generation = 0;
  bool _busy = true, _failed = false, _saving = false, _original = false;
  ImageProvider? _image;
  String tr(String zh, String en) => ModuStrings.text(context, zh, en);
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    widget.cancelRender();
    final generation = ++_generation;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: Dialog.fullscreen(
          child: SafeArea(
              child: Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: Text(tr('图像增强', 'Image enhancement'),
                style: Theme.of(context).textTheme.titleLarge)),
        SizedBox(
            height: MediaQuery.sizeOf(context).height * .28,
            child: Stack(fit: StackFit.expand, children: [
              if (_bytes != null) Image(image: _image!, fit: BoxFit.contain),
              if (_busy)
                const Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator()),
            ])),
        TextButton(
            onPressed: _saving
                ? null
                : () {
                    setState(() => _original = !_original);
                    _schedule();
                  },
            child: Text(_original
                ? tr('查看增强', 'Show enhanced')
                : tr('对照原图', 'Compare original'))),
        Expanded(
            child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
              for (final entry in DocumentEnhancement.limits.entries) ...[
                Text('${switch (entry.key) {
                  'ink' => tr('文字加黑', 'Stroke strength'),
                  'contrast' => tr('对比度', 'Contrast'),
                  'darken' => tr('加黑', 'Darken'),
                  'whiten' => tr('漂白', 'Paper whitening'),
                  _ => tr('锐化', 'Sharpen'),
                }}  ${_draft.toJson()[entry.key]!.round()}'),
                Row(children: [
                  IconButton(
                      tooltip: tr('减少', 'Decrease'),
                      onPressed: _saving
                          ? null
                          : () => _change(
                              entry.key,
                              (_draft.toJson()[entry.key]! - 1)
                                  .clamp(entry.value.$1, entry.value.$2)),
                      icon: const Icon(Icons.remove)),
                  Expanded(
                      child: Slider(
                          key: ValueKey('enhancement-${entry.key}'),
                          value: _draft.toJson()[entry.key]!,
                          min: entry.value.$1,
                          max: entry.value.$2,
                          divisions: (entry.value.$2 - entry.value.$1).round(),
                          onChanged: _saving
                              ? null
                              : (value) => _change(entry.key, value))),
                  IconButton(
                      tooltip: tr('增加', 'Increase'),
                      onPressed: _saving
                          ? null
                          : () => _change(
                              entry.key,
                              (_draft.toJson()[entry.key]! + 1)
                                  .clamp(entry.value.$1, entry.value.$2)),
                      icon: const Icon(Icons.add)),
                  IconButton(
                      tooltip: tr('恢复默认', 'Reset'),
                      onPressed: _saving ? null : () => _change(entry.key, 0),
                      icon: const Icon(Icons.restart_alt)),
                ]),
              ],
              Text(tr('只改变显示，不修改原文件。漂白主要净化浅色纸张；复杂背景请保留原图。',
                  'Display only; the source file stays unchanged. Whitening targets light paper. Keep the original for complex backgrounds.')),
            ])),
        if (_failed)
          TextButton(
              onPressed: _saving ? null : _schedule,
              child: Text(tr('预览或保存失败，点击重试', 'Preview or save failed. Retry'))),
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
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: Text(tr('取消', 'Cancel'))),
          FilledButton(
              onPressed: _saving || _busy || _failed ? null : _save,
              child:
                  Text(_saving ? tr('保存中…', 'Saving…') : tr('确定', 'Confirm'))),
        ]),
        const SizedBox(height: 8),
      ]))));
}
