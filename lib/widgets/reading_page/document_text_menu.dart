import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/service/ocr/document_ocr_precache.dart';
import 'package:anx_reader/widgets/reading_page/document_panel_widgets.dart';
import 'package:anx_reader/widgets/reading_page/ocr_precache_settings.dart';
import 'package:anx_reader/widgets/reading_page/reader_settings_scroll_view.dart';
import 'package:anx_reader/widgets/reading_page/widget_title.dart';
import 'package:flutter/material.dart';
import 'reader_menu_group.dart';

/// Presentation only: recognition, caching and export stay with the reader.
class DocumentTextMenu extends StatelessWidget {
  const DocumentTextMenu({
    super.key,
    this.openReflow,
    this.openExtraction,
    this.exportText,
    this.forceOcr = false,
    this.onForceOcrChanged,
    this.comparison = false,
    this.onComparisonChanged,
    this.cache,
  });

  final VoidCallback? openReflow;
  final VoidCallback? openExtraction;
  final VoidCallback? exportText;
  final bool forceOcr;
  final ValueChanged<bool>? onForceOcrChanged;
  final bool comparison;
  final ValueChanged<bool>? onComparisonChanged;
  final DocumentOcrPrecache? cache;

  @override
  Widget build(BuildContext context) {
    String text(String zh, String en) => ModuStrings.text(context, zh, en);
    final theme = Theme.of(context);
    Widget action({
      required Key key,
      required IconData icon,
      required String title,
      required String description,
      required VoidCallback? onTap,
    }) =>
        ListTile(
          key: key,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Icon(icon,
              color: onTap == null
                  ? theme.disabledColor
                  : theme.colorScheme.primary),
          title: SettingHelpTitle(title: title, description: description),
          trailing: const Icon(Icons.chevron_right, size: 20),
          enabled: onTap != null,
          onTap: onTap,
        );

    Widget group(Widget child) => ReaderMenuGroup(child: child);

    return DocumentPanelTheme(
      child: ReaderSettingsScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            widgetTitle(text('文字', 'Text'), null),
            const SizedBox(height: 8),
            group(Column(children: [
              action(
                key: const ValueKey('document-reflow-entry'),
                icon: Icons.article_outlined,
                title: text('文字重排', 'Reflow text'),
                description: forceOcr
                    ? text('忽略文字层，使用 OCR 识别结果',
                        'Ignore embedded text and use OCR results')
                    : text('优先使用文字层，无文字时自动 OCR',
                        'Use embedded text, or OCR when no text is available'),
                onTap: openReflow,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile(
                key: const ValueKey('document-force-ocr-switch'),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                title: SettingHelpTitle(
                  title: text('强制 OCR 重排', 'Force OCR reflow'),
                  description: text(
                      '对整本书生效：重排及各页后台预缓存均使用 OCR，忽略文字层及其缓存；需要本地 OCR 模型',
                      'Applies throughout this book: reflow and background prefetch use OCR on every page, ignoring embedded text and its cache. Requires a local OCR model.'),
                ),
                value: forceOcr,
                onChanged: onForceOcrChanged,
              ),
              if (onComparisonChanged != null) ...[
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  key: const ValueKey('document-comparison-switch'),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  title: SettingHelpTitle(
                    title: text('原页对照重排', 'Compare original and reflow'),
                    description: text('竖屏上下，横屏左右',
                        'Top/bottom in portrait, side by side in landscape'),
                  ),
                  value: comparison,
                  onChanged: onComparisonChanged,
                ),
              ],
              const Divider(height: 1, indent: 16, endIndent: 16),
              action(
                key: const ValueKey('document-extraction-entry'),
                icon: Icons.crop_free,
                title:
                    text('框选提取与连续识别', 'Region extraction and continuous OCR'),
                description: text('保留识别缓存、编辑和文字导出',
                    'Includes cached results, editing and text export'),
                onTap: openExtraction,
              ),
            ])),
            group(Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: OcrPrecacheSettings(cache: cache),
            )),
            group(action(
              key: const ValueKey('export-saved-txt'),
              icon: Icons.file_download_outlined,
              title: text('导出本书已保存文字', 'Export saved text'),
              description: text('按原始页码排列，优先导出编辑结果',
                  'Original page order; edited text takes priority'),
              onTap: exportText,
            )),
          ],
        ),
      ),
    );
  }
}
