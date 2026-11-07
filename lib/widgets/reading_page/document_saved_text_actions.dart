import 'reader_menu_appearance.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/service/ocr/document_reflow_store.dart';
import 'package:anx_reader/utils/save_file_to_download.dart';

Future<bool> confirmDocumentRecognition(BuildContext context) async =>
    await showReaderDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(ModuStrings.text(
                  context, '重新 OCR 本页？', 'Recognize this page again?')),
              content: Text(ModuStrings.text(context, "替换本页已保存的识别文字和编辑结果？",
                  "Replace this page’s saved recognized text and edits?")),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
                FilledButton(
                    key: const ValueKey('confirm-page-recognition'),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(
                        ModuStrings.text(context, '重新识别', 'Recognize again'))),
              ],
            )) ==
    true;

Future<DocumentReflowPage?> editSavedDocumentPage(BuildContext context,
    DocumentReflowStore store, DocumentReflowPage page) async {
  final input = TextEditingController(text: page.text);
  var saving = false;
  String? error;
  final result = await showReaderDialog<DocumentReflowPage>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(builder: (context, update) {
            String t(String zh, String en) => ModuStrings.text(context, zh, en);
            Future<void> save() async {
              if (saving) return;
              update(() {
                saving = true;
                error = null;
              });
              try {
                final edited = await store.saveEdit(page, input.text);
                if (context.mounted) Navigator.pop(context, edited);
              } catch (_) {
                if (context.mounted) {
                  update(() {
                    saving = false;
                    error = t("保存失败，请检查内容和可用空间后重试。",
                        "Could not save. Check the text and available space, then retry.");
                  });
                }
              }
            }

            return PopScope(
                canPop: !saving,
                child: AlertDialog(
                  scrollable: true,
                  title: Text(t('编辑原书第 ${page.page + 1} 页',
                      'Edit original page ${page.page + 1}')),
                  content: SizedBox(
                      width: 640,
                      height: MediaQuery.sizeOf(context).height * .55,
                      child: Column(children: [
                        const SizedBox(height: 12),
                        Expanded(
                            child: TextField(
                                key: const ValueKey('saved-page-editor'),
                                controller: input,
                                readOnly: saving,
                                expands: true,
                                maxLines: null,
                                textAlignVertical: TextAlignVertical.top,
                                maxLength: 1000000,
                                decoration: InputDecoration(
                                    border: const OutlineInputBorder(),
                                    errorMaxLines: 3,
                                    errorText: error))),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: saving ? null : () => Navigator.pop(context),
                        child: Text(t('取消', 'Cancel'))),
                    FilledButton(
                        key: const ValueKey('save-page-edit'),
                        onPressed: saving ? null : save,
                        child: Text(t(saving ? '保存中…' : '保存',
                            saving ? 'Saving…' : 'Save'))),
                  ],
                ));
          }));
  WidgetsBinding.instance.addPostFrameCallback((_) => input.dispose());
  return result;
}

Future<void> exportSavedDocumentText(
    BuildContext context, DocumentReflowStore store) async {
  String t(String zh, String en) => ModuStrings.text(context, zh, en);
  try {
    final format = await showReaderDialog<DocumentTextExportFormat>(
        context: context,
        builder: (context) => SimpleDialog(
              title: Text(t('选择导出格式', 'Choose export format')),
              children: [
                for (final format in DocumentTextExportFormat.values)
                  SimpleDialogOption(
                    key: ValueKey('export-format-${format.extension}'),
                    onPressed: () => Navigator.pop(context, format),
                    child: Text(format == DocumentTextExportFormat.txt
                        ? 'TXT (.txt)'
                        : 'Markdown (.md)'),
                  ),
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context),
                    child: Text(t('取消', 'Cancel'))),
              ],
            ));
    if (format == null || !context.mounted) return;
    final text = await store.exportText(format: format);
    if (!context.mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('暂无已保存的页面', 'No saved pages yet'))));
      return;
    }
    final path = await saveFileToDownload(
        bytes: Uint8List.fromList(utf8.encode(text)),
        fileName:
            'Modu-OCR-${DateTime.now().millisecondsSinceEpoch}.${format.extension}',
        mimeType: format.mimeType);
    if (path != null && context.mounted) {
      final label = format == DocumentTextExportFormat.txt ? 'TXT' : 'Markdown';
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('$label 已导出', '$label exported'))));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              t('导出失败，已保存的文字未改变', 'Export failed; saved text is unchanged'))));
    }
  }
}
