import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'reader_menu_appearance.dart';
import 'document_text_menu.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'widget_title.dart';
import 'document_saved_text_actions.dart';
import 'package:anx_reader/service/ocr/document_reflow_store.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/book_player/document_layout_store.dart';
import 'package:anx_reader/models/document_page_layout.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'reader_menu_group.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/widgets/reading_page/pdf_region_preview.dart';
import 'package:anx_reader/widgets/reading_page/pdf_reading_controls.dart';
import 'package:flutter/material.dart';
import 'package:anx_reader/widgets/reading_page/document_panel_widgets.dart';
import 'eink_refresh_controls.dart';
import 'reader_settings_scroll_view.dart';

/// Quick controls for fixed-page documents, not the text-book style settings.
class DocumentStyleWidget extends StatefulWidget {
  const DocumentStyleWidget(
      {super.key,
      required this.player,
      this.openReflow,
      this.comparison = false,
      this.onComparisonChanged,
      this.textOnly = false,
      this.openExtraction});
  final EpubPlayerState player;
  final void Function(bool forceOcr)? openReflow;
  final bool comparison;
  final ValueChanged<bool>? onComparisonChanged;
  final bool textOnly;
  final VoidCallback? openExtraction;

  @override
  State<DocumentStyleWidget> createState() => _DocumentStyleWidgetState();
}

class _DocumentStyleWidgetState extends State<DocumentStyleWidget> {
  bool _watermarkAvailable = false;
  Listenable? _documentMode;
  bool _savedTextBusy = false, _savingOcrMode = false;

  Future<void> _setForceOcr(bool enabled) async {
    setState(() => _savingOcrMode = true);
    try {
      await readingPageKey.currentState?.setDocumentForceOcr(enabled);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ModuStrings.text(
                context, '保存失败，请重试', 'Could not save. Please retry.'))));
      }
    } finally {
      if (mounted) setState(() => _savingOcrMode = false);
    }
  }

  Future<void> _exportSavedText() async {
    if (_savedTextBusy) return;
    setState(() => _savedTextBusy = true);
    try {
      final store = DocumentReflowStore(widget.player.cssBookKey);
      await exportSavedDocumentText(context, store);
    } finally {
      if (mounted) setState(() => _savedTextBusy = false);
    }
  }

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
    await player.pauseDocumentOcrCache();
    if (!mounted) {
      player.resumeDocumentOcrCache();
      return;
    }
    try {
      await showReaderDialog<DocumentLayoutConfig>(
        animationStyle: AppMotion.style,
        context: context,
        builder: (_) => PdfRegionPreview(
          startWithLayoutEditor: editLayout,
          panelReading: player.pdfPanelReading,
          setPanelReading: player.setPdfPanelReading,
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
    } finally {
      player.resumeDocumentOcrCache();
    }
    if (mounted) setState(() {});
  }

  Future<void> _openEpubImages({bool editLayout = false}) async {
    final player = widget.player;
    await player.pauseDocumentOcrCache();
    if (!mounted) {
      player.resumeDocumentOcrCache();
      return;
    }
    try {
      await showReaderDialog<DocumentLayoutConfig>(
          animationStyle: AppMotion.style,
          context: context,
          builder: (_) => PdfRegionPreview(
                imageEpub: true,
                startWithLayoutEditor: editLayout,
                panelReading: player.pdfPanelReading,
                setPanelReading: player.setPdfPanelReading,
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
    } finally {
      player.resumeDocumentOcrCache();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.textOnly) {
      return DocumentTextMenu(
        openReflow:
            widget.openReflow == null ? null : () => widget.openReflow!(false),
        forceOcr: widget.player.documentForceOcr,
        onForceOcrChanged: _savingOcrMode ? null : _setForceOcr,
        openExtraction: widget.openExtraction,
        comparison: widget.comparison,
        onComparisonChanged: widget.onComparisonChanged,
        cache: widget.player.ocrPrecache,
        exportText: _savedTextBusy ? null : _exportSavedText,
      );
    }
    final cropControls = ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.crop),
      trailing: const Icon(Icons.chevron_right),
      onTap: widget.player.isImageEpub
          ? () => _openEpubImages(editLayout: true)
          : () => _openPdfPreview(editLayout: true),
      title: SettingHelp(
          title: Text(ModuStrings.text(
              context,
              widget.player.isImageEpub ? '扫描图片裁边与分格' : 'PDF 裁边与分格',
              widget.player.isImageEpub
                  ? 'Scanned image crop and panels'
                  : 'PDF crop and panels')),
          description: Text(ModuStrings.text(context, '自动裁边、留白、漫画与论文分栏在独立预览中调整',
              'Auto crop, margins, comics and columns are adjusted in the separate preview'))),
    );
    return DocumentPanelTheme(
      child: ReaderSettingsScrollView(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          widgetTitle(ModuStrings.text(context, '页面', 'Page'), null),
          ListenableBuilder(
            listenable: Prefs(),
            builder: (context, _) =>
                Prefs().eInkMode && widget.player.supportsDocumentImages
                    ? ReaderMenuGroup(
                        padding: const EdgeInsets.all(12),
                        child: EinkRefreshControls(
                            supported: widget.player.einkRefresh.supported,
                            refresh: widget.player.refreshEinkScreen))
                    : const SizedBox.shrink(),
          ),
          if (widget.player.supportsDocumentImages == true)
            PdfReadingControls(
              key: ValueKey(widget.player.cssBookKey),
              initial: widget.player.pdfReadingView,
              cropControls: cropControls,
              watermarkAvailable: _watermarkAvailable,
              save: widget.player.setPdfReadingView,
              preview: (request) async {
                final player = widget.player;
                await player.pauseDocumentOcrCache();
                try {
                  final info = await (player.isImageEpub
                      ? player.epubImageInfo(null)
                      : player.pdfRegionInfo(null));
                  return await player.renderPdfRegion({
                    ...request,
                    'page': info['page'],
                    if (player.isImageEpub) 'source': 'epub'
                  });
                } finally {
                  player.resumeDocumentOcrCache();
                }
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
        ]),
      ),
    );
  }
}
