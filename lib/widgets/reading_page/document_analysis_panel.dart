import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';

/// An on-demand, local inspection of real PDF/EPUB page evidence. This panel
/// does not advertise OCR until a working OCR backend is connected.
class DocumentAnalysisPanel extends StatefulWidget {
  const DocumentAnalysisPanel(
      {super.key,
      required this.analyze,
      required this.cancel,
      this.initialOverride,
      this.saveOverride,
      this.previewPdf,
      this.previewImages});
  final Future<Map<String, dynamic>> Function() analyze;
  final VoidCallback cancel;
  final String? initialOverride;
  final Future<void> Function(String?)? saveOverride;
  final VoidCallback? previewPdf;
  final VoidCallback? previewImages;

  @override
  State<DocumentAnalysisPanel> createState() => _DocumentAnalysisPanelState();
}

class _DocumentAnalysisPanelState extends State<DocumentAnalysisPanel> {
  Map<String, dynamic>? _result;
  bool _busy = false;
  bool _failed = false;
  int _generation = 0;
  String? _override;
  bool _saving = false;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    _override = widget.initialOverride;
    _analyze();
  }

  Future<void> _saveOverride(String? value) async {
    if (_saving || widget.saveOverride == null) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await widget.saveOverride!(value);
      if (mounted) setState(() => _override = value);
    } catch (_) {
      if (mounted) setState(() => _saveFailed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _analyze() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final result = await widget.analyze();
      if (mounted && generation == _generation) {
        setState(() => _result = result);
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.cancel();
    super.dispose();
  }

  String _label(String? kind) {
    final pair = switch (kind) {
      'text' => ('文字型', 'Text-based'),
      'scanned' => ('图像页（疑似扫描）', 'Image page (likely scanned)'),
      'image-with-text' => ('图像页含文字层', 'Image page with text layer'),
      'image-candidate' => (
          '图片章节（覆盖范围待确认）',
          'Image chapter (coverage unverified)'
        ),
      'mixed' => ('混合文档', 'Mixed document'),
      'blank' => ('空白页', 'Blank page'),
      'illustrated' => ('封面或非正文', 'Cover or non-body section'),
      _ => ('尚不能确定', 'Undetermined'),
    };
    return ModuStrings.text(context, pair.$1, pair.$2);
  }

  @override
  Widget build(BuildContext context) {
    final pages = (_result?['pages'] as List?) ?? const [];
    return AlertDialog(
      title:
          Text(ModuStrings.text(context, '文档类型检测', 'Document type inspection')),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ModuStrings.text(
                context,
                '仅在本机按需抽样，不上传文档，不启动 OCR 或向量化。检测结果为初步判断。',
                'On-device sampling only. No upload, OCR or indexing. Results are provisional.')),
            const SizedBox(height: 12),
            if (widget.saveOverride != null) ...[
              Text(ModuStrings.text(context, '本书类型标记（暂不改变阅读模式）',
                  'Book type correction (does not switch reading modes)')),
              DropdownButton<String>(
                isExpanded: true,
                value: _override ?? 'auto',
                items: ['auto', 'text', 'scanned', 'image-with-text', 'mixed']
                    .map((kind) => DropdownMenuItem(
                        value: kind,
                        child: Text(kind == 'auto'
                            ? ModuStrings.text(context, '自动检测', 'Automatic')
                            : _label(kind))))
                    .toList(),
                onChanged: _saving
                    ? null
                    : (kind) => _saveOverride(kind == 'auto' ? null : kind),
              ),
              if (_saveFailed)
                Text(ModuStrings.text(context, '类型标记保存失败，请重试。',
                    'Could not save the type correction. Please retry.')),
            ],
            if (_busy)
              const EinkStaticIndicator(child: LinearProgressIndicator()),
            if (_failed)
              Text(ModuStrings.text(context, '检测失败，请重试。原文档未改动。',
                  'Inspection failed. Retry; the source document is unchanged.')),
            if (_result != null) ...[
              if (_result!['format'] == 'epub' && widget.previewImages != null)
                OutlinedButton.icon(
                    onPressed: widget.previewImages,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(ModuStrings.text(context, '扫描图片原图 · 裁边与增强',
                        'Scanned image pages · crop and enhance'))),
              if (_result!['format'] == 'pdf' && widget.previewPdf != null)
                OutlinedButton.icon(
                  onPressed: widget.previewPdf,
                  icon: const Icon(Icons.zoom_in),
                  label: Text(ModuStrings.text(context, 'PDF 局部预览 · 100%–1500%',
                      'PDF region preview · 100%–1500%')),
                ),
              Text(_label(_result!['kind'] as String?),
                  style: Theme.of(context).textTheme.titleMedium),
              Text(ModuStrings.format(context, '已检测 {sampled} / {total} 页或章节',
                  'Inspected {sampled} / {total} pages or sections', values: {
                'sampled': _result!['sampled'] ?? 0,
                'total': _result!['total'] ?? 0
              })),
              for (final page in pages.whereType<Map>())
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                      '${(page['page'] as num? ?? 0).toInt() + 1}. ${_label(page['kind'] as String?)}\n'
                      '${ModuStrings.text(context, '有效字符', 'Valid characters')}: ${page['validCharacters'] ?? page['characters'] ?? 0}'
                      '${page['imageCoverage'] is num ? ' · ${(100 * (page['imageCoverage'] as num)).round()}% ${ModuStrings.text(context, '图像覆盖', 'image coverage')}' : ''}'),
                ),
            ],
          ],
        )),
      ),
      actions: [
        if (!_busy)
          TextButton(
              onPressed: _analyze,
              child: Text(ModuStrings.text(context, '重新检测', 'Inspect again'))),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(ModuStrings.text(
                context, _busy ? '取消' : '关闭', _busy ? 'Cancel' : 'Close'))),
      ],
    );
  }
}
