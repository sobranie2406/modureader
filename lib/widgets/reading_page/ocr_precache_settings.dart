import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';
import 'package:anx_reader/service/ocr/document_ocr_precache.dart';
import 'package:anx_reader/service/ocr/document_reflow_loader.dart';

class OcrPrecacheSettings extends StatefulWidget {
  const OcrPrecacheSettings({super.key, this.cache});
  final DocumentOcrPrecache? cache;
  @override
  State<OcrPrecacheSettings> createState() => _OcrPrecacheSettingsState();
}

class _OcrPrecacheSettingsState extends State<OcrPrecacheSettings> {
  bool _saving = false;
  Future<void> _save({bool? enabled, int? pages}) async {
    setState(() => _saving = true);
    try {
      await Prefs().saveOcrPrecache(enabled: enabled, pages: pages);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ModuStrings.text(
                context, '保存失败，请重试', 'Could not save. Please retry.'))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Prefs(),
      builder: (context, _) =>
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: SettingHelpTitle(
                    title: ModuStrings.text(
                        context, '后台预缓存 OCR', 'Background OCR cache'),
                    description: ModuStrings.text(context, "提前识别当前页及后续页面，加快重排。",
                        "Recognize the current and following pages in advance for faster reflow.")),
                value: Prefs().ocrPrecacheEnabled,
                onChanged: _saving ? null : (value) => _save(enabled: value)),
            if (Prefs().ocrPrecacheEnabled)
              Row(children: [
                Expanded(
                    child:
                        Text(ModuStrings.text(context, '缓存页数', 'Cache pages'))),
                IconButton(
                    tooltip: ModuStrings.text(context, '减少缓存页数', 'Fewer pages'),
                    onPressed: _saving || Prefs().ocrPrecachePages <= 1
                        ? null
                        : () => _save(pages: Prefs().ocrPrecachePages - 1),
                    icon: const Icon(Icons.remove)),
                Semantics(
                    liveRegion: true,
                    label: ModuStrings.text(context, '缓存页数', 'Cache pages'),
                    child: Text('${Prefs().ocrPrecachePages}')),
                IconButton(
                    tooltip: ModuStrings.text(context, '增加缓存页数', 'More pages'),
                    onPressed: _saving || Prefs().ocrPrecachePages >= 5
                        ? null
                        : () => _save(pages: Prefs().ocrPrecachePages + 1),
                    icon: const Icon(Icons.add)),
              ]),
            if (Prefs().ocrPrecacheEnabled && widget.cache != null)
              ListenableBuilder(
                  listenable: widget.cache!,
                  builder: (context, _) {
                    final cache = widget.cache!;
                    final message = cache.error is ReflowModelUnavailable
                        ? ModuStrings.text(context, '缺少本地 OCR 模型，请先在设置中下载或导入。',
                            'Install or import the local OCR model in Settings first.')
                        : cache.error != null
                            ? ModuStrings.text(
                                context,
                                '预缓存失败，返回阅读后重试；已保存结果保留。',
                                'Precache failed. Return to reading to retry. Saved results are kept.')
                            : cache.total == 0 || cache.startPage < 0
                                ? ModuStrings.text(context, '等待原页就绪',
                                    'Waiting for the original page')
                                : ModuStrings.text(
                                    context,
                                    '第 ${cache.startPage + 1}–${cache.startPage + cache.total} 页：已处理 ${cache.completed}/${cache.total} 页（含已有缓存和校对稿）',
                                    'Pages ${cache.startPage + 1}–${cache.startPage + cache.total}: ${cache.completed}/${cache.total} processed (including saved OCR and edits)');
                    return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                            '$message\n${cache.running ? ModuStrings.text(context, '正在处理第 ${cache.currentPage! + 1} 页${cache.progress == null ? '' : '（${cache.progress!.$1}/${cache.progress!.$2}）'}', 'Processing page ${cache.currentPage! + 1}${cache.progress == null ? '' : ' (${cache.progress!.$1}/${cache.progress!.$2})'}') : ModuStrings.text(context, "已缓存的页面自动跳过。", "Cached pages are skipped.")}',
                            style: Theme.of(context).textTheme.bodySmall));
                  }),
          ]));
}
