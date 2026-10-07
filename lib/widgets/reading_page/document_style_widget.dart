import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/book_player/document_type_store.dart';
import 'package:anx_reader/service/book_player/document_layout_store.dart';
import 'package:anx_reader/models/document_page_layout.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/widgets/reading_page/document_analysis_panel.dart';
import 'package:anx_reader/widgets/reading_page/pdf_region_preview.dart';
import 'package:anx_reader/widgets/reading_page/pdf_reading_controls.dart';
import 'package:flutter/material.dart';
import 'package:anx_reader/widgets/reading_page/document_panel_widgets.dart';
import 'package:anx_reader/service/ocr/document_text_style.dart';
import 'document_text_style_dialog.dart';
import 'eink_refresh_controls.dart';

/// Quick controls for fixed-page documents, not the text-book style settings.
class DocumentStyleWidget extends StatefulWidget {
  const DocumentStyleWidget({super.key, required this.player, this.openReflow});
  final EpubPlayerState player;
  final void Function(bool forceOcr)? openReflow;

  @override
  State<DocumentStyleWidget> createState() => _DocumentStyleWidgetState();
}

class _DocumentStyleWidgetState extends State<DocumentStyleWidget> {
  bool _changingPdfMode = false;
  bool _watermarkAvailable = false;
  Listenable? _documentMode;
  @override
  void initState() {
    super.initState();
    final player = widget.player;
    _documentMode = player.documentReadingMode;
    _documentMode?.addListener(_documentModeChanged);
    if (player.isPdfDocument == true) {
      player.pdfRegionInfo(null).then((info) {
        if (mounted) {
          setState(() => _watermarkAvailable =
              (info['watermarks'] as List?)?.isNotEmpty == true);
        }
      }).catchError((_) {});
    }
  }

  void _documentModeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _documentMode?.removeListener(_documentModeChanged);
    super.dispose();
  }

  Future<void> _openPdfPreview({bool editLayout = false}) async {
    final player = widget.player;
    await showDialog<DocumentLayoutConfig>(
      animationStyle: AppMotion.style,
      context: context,
      builder: (_) => PdfRegionPreview(
        startWithLayoutEditor: editLayout,
        info: player.pdfRegionInfo,
        initialLayout:
            DocumentLayoutStore(Prefs().prefs).read(player.cssBookKey),
        saveLayout: player.savePdfLayout,
        render: player.renderPdfRegion,
        cancelRender: () => player.cancelPdfRegionRender(),
        close: () => player.cancelPdfRegionRender(close: true),
        initialEnhancement: player.pdfReadingView.enhancement,
        saveEnhancement: (value) => player.setPdfReadingView(
            player.pdfReadingView.copyWith(enhancement: value)),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openEpubImages({bool editLayout = false}) async {
    final player = widget.player;
    await showDialog<DocumentLayoutConfig>(
        animationStyle: AppMotion.style,
        context: context,
        builder: (_) => PdfRegionPreview(
              imageEpub: true,
              startWithLayoutEditor: editLayout,
              info: player.epubImageInfo,
              initialLayout:
                  DocumentLayoutStore(Prefs().prefs).read(player.cssBookKey),
              saveLayout: player.savePdfLayout,
              initialEnhancement: player.pdfReadingView.enhancement,
              saveEnhancement: (value) => player.setPdfReadingView(
                  player.pdfReadingView.copyWith(enhancement: value)),
              render: (request) =>
                  player.renderPdfRegion({...request, 'source': 'epub'}),
              cancelRender: () => player.cancelEpubImageRender(),
              close: () => player.cancelEpubImageRender(close: true),
            ));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final layoutControls = SwitchListTile(
      title: Text(ModuStrings.text(context, '按裁边与分格阅读', 'Read cropped panels')),
      subtitle: Text(ModuStrings.text(context, '按已保存的顺序翻区域，再翻原页；关闭恢复原版',
          'Follow saved panels before turning the original page; turn off for the original layout')),
      value: widget.player.pdfPanelReading,
      onChanged: _changingPdfMode
          ? null
          : (enabled) async {
              final player = widget.player;
              setState(() => _changingPdfMode = true);
              try {
                await player.setPdfPanelReading(enabled);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ModuStrings.text(context, '版式切换失败，请重试',
                          'Could not change layout. Please retry.'))));
                }
              } finally {
                if (mounted) setState(() => _changingPdfMode = false);
              }
            },
    );
    final cropControls = Wrap(spacing: 8, runSpacing: 4, children: [
      OutlinedButton.icon(
        icon: const Icon(Icons.crop),
        onPressed: widget.player.isImageEpub
            ? () => _openEpubImages(editLayout: true)
            : () => _openPdfPreview(editLayout: true),
        label: Text(ModuStrings.text(
            context,
            widget.player.isImageEpub ? '扫描图片裁边与分格' : 'PDF 裁边与分格',
            widget.player.isImageEpub
                ? 'Scanned image crop and panels'
                : 'PDF crop and panels')),
      ),
      Text(ModuStrings.text(context, '自动裁边、留白、漫画与论文分栏在独立预览中调整',
          'Auto crop, margins, comics and columns are adjusted in the separate preview')),
    ]);
    return DocumentPanelTheme(
        child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        child: Column(children: [
          Row(children: [
            Expanded(
                child: Text(
                    widget.player.isPdfDocument
                        ? ModuStrings.text(context, 'PDF 阅读', 'PDF reading')
                        : ModuStrings.text(
                            context, '扫描图片阅读', 'Scanned image reading'),
                    style: Theme.of(context).textTheme.headlineSmall)),
            IconButton(
              tooltip: ModuStrings.text(context, 'OCR 文字样式', 'OCR text style'),
              icon: const Icon(Icons.settings),
              onPressed: () {
                final store = DocumentTextStyleStore(Prefs().prefs);
                final book = widget.player.cssBookKey;
                showDialog<DocumentTextStyle>(
                    animationStyle: AppMotion.style,
                    context: context,
                    builder: (_) => DocumentTextStyleDialog(
                        initial: store.read(book),
                        save: (v) => store.save(book, v)));
              },
            ),
          ]),
          const Divider(),
          ListenableBuilder(
            listenable: Prefs(),
            builder: (context, _) =>
                Prefs().eInkMode && widget.player.supportsDocumentImages
                    ? EinkRefreshControls(
                        supported: widget.player.einkRefresh.supported,
                        refresh: widget.player.refreshEinkScreen)
                    : const SizedBox.shrink(),
          ),
          DocumentControlRow(
            label: ModuStrings.text(context, '文字模式', 'Text mode'),
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              Chip(label: Text(ModuStrings.text(context, '原版', 'Original'))),
              OutlinedButton(
                  onPressed: widget.openReflow == null
                      ? null
                      : () => widget.openReflow!(false),
                  child:
                      Text(ModuStrings.text(context, '文字重排', 'Reflow text'))),
              OutlinedButton(
                  onPressed: widget.openReflow == null
                      ? null
                      : () => widget.openReflow!(true),
                  child:
                      Text(ModuStrings.text(context, 'OCR 重排', 'OCR reflow'))),
            ]),
          ),
          if (!widget.player.pdfPanelReading) ...[
            cropControls,
            layoutControls,
          ],
          if (widget.player.supportsDocumentImages == true &&
              widget.player.pdfPanelReading)
            PdfReadingControls(
              key: ValueKey(widget.player.cssBookKey),
              initial: widget.player.pdfReadingView,
              cropControls: cropControls,
              layoutControls: layoutControls,
              watermarkAvailable: _watermarkAvailable,
              save: widget.player.setPdfReadingView,
              pan: widget.player.panPdfReadingView,
              preview: (request) async {
                final player = widget.player;
                final info = await (player.isImageEpub
                    ? player.epubImageInfo(null)
                    : player.pdfRegionInfo(null));
                return player.renderPdfRegion({
                  ...request,
                  'page': info['page'],
                  if (player.isImageEpub) 'source': 'epub'
                });
              },
              cancelPreview: () {
                final player = widget.player;
                if (player.isImageEpub == true) {
                  player.cancelEpubImageRender();
                } else {
                  player.cancelPdfRegionRender();
                }
              },
            ),
          if (widget.player.supportsDocumentImages == true)
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: Text(ModuStrings.text(
                  context, '文档类型检测', 'Document type inspection')),
              subtitle: Text(ModuStrings.text(
                  context,
                  '本机检测 PDF 文字层及 EPUB 正文图片',
                  'Inspect PDF text layers and EPUB body images locally')),
              onTap: () {
                final player = widget.player;
                final store = DocumentTypeStore(Prefs().prefs);
                final documentKey = player.cssBookKey;
                showDialog<void>(
                    animationStyle: AppMotion.style,
                    context: context,
                    builder: (_) => DocumentAnalysisPanel(
                        analyze: player.analyzeDocument,
                        initialOverride: store.read(documentKey),
                        saveOverride: (kind) => store.save(documentKey, kind),
                        previewPdf: _openPdfPreview,
                        previewImages: _openEpubImages,
                        cancel: player.cancelDocumentAnalysis));
              },
            ),
        ]),
      ),
    ));
  }
}
