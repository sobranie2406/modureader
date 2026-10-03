import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/book_player/document_type_store.dart';
import 'package:anx_reader/service/book_player/document_layout_store.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/widgets/reading_page/document_analysis_panel.dart';
import 'package:anx_reader/widgets/reading_page/pdf_region_preview.dart';
import 'package:anx_reader/widgets/reading_page/pdf_reading_controls.dart';
import 'package:anx_reader/enums/text_alignment.dart';
import 'package:anx_reader/enums/writing_mode.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book_style.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/widgets/icon_and_text.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/custom_css_editor.dart';
import 'package:flutter/material.dart';
import 'package:icons_plus/icons_plus.dart';

// Reusable style slider widget that can be disabled
class StyleSlider extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) labelFormatter;
  final bool enabled;

  const StyleSlider({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    required this.divisions,
    required this.labelFormatter,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconAndText(
          icon: Icon(icon),
          text: label,
        ),
        Expanded(
          child: Slider(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            value: value,
            onChanged: enabled ? onChanged : null,
            min: min,
            max: max,
            divisions: divisions,
            label: labelFormatter(value),
          ),
        ),
      ],
    );
  }
}

class StyleSettings extends StatefulWidget {
  const StyleSettings({super.key});

  @override
  State<StyleSettings> createState() => _StyleSettingsState();
}

class _StyleSettingsState extends State<StyleSettings> {
  bool _changingPdfMode = false;
  bool _watermarkAvailable = false;
  Listenable? _documentMode;
  @override
  void initState() {
    super.initState();
    final player = epubPlayerKey.currentState;
    _documentMode = player?.documentReadingMode;
    _documentMode?.addListener(_documentModeChanged);
    if (player?.isPdfDocument == true) {
      player!.pdfRegionInfo(null).then((info) {
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

  Future<void> _openPdfPreview() async {
    final player = epubPlayerKey.currentState;
    if (player == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => PdfRegionPreview(
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
  }

  Future<void> _openEpubImages() async {
    final player = epubPlayerKey.currentState;
    if (player == null) return;
    await showDialog<void>(
        context: context,
        builder: (_) => PdfRegionPreview(
              imageEpub: true,
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
  }

  @override
  Widget build(BuildContext context) {
    Widget useBookStylesSwitch() {
      return SwitchListTile(
        title: Text(L10n.of(context).useBookStyles),
        subtitle: Text(
          L10n.of(context).useBookStylesDescription,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        value: Prefs().useBookStyles,
        onChanged: (bool value) {
          setState(() {
            Prefs().useBookStyles = value;
            epubPlayerKey.currentState?.changeStyle(Prefs().bookStyle);
          });
        },
      );
    }

    Widget textIndent(BookStyle bookStyle, StateSetter setState) {
      bool enabled = !Prefs().useBookStyles;
      return StyleSlider(
        icon: Icons.format_indent_increase,
        label: L10n.of(context).readingPageIndent,
        value: bookStyle.indent,
        onChanged: (double value) {
          setState(() {
            bookStyle.indent = value;
            epubPlayerKey.currentState?.changeStyle(bookStyle);
            Prefs().saveBookStyleToPrefs(bookStyle);
          });
        },
        min: -0.5,
        max: 8,
        divisions: 17,
        labelFormatter: (value) => value < 0
            ? L10n.of(context).readingPageIndentNoChange
            : value.toStringAsFixed(1),
        enabled: enabled,
      );
    }

    Widget sideMarginSlider(BookStyle bookStyle, StateSetter setState) {
      return StyleSlider(
        icon: Prefs().writingMode == WritingModeEnum.verticalRl
            ? Bootstrap.arrows_vertical
            : Bootstrap.arrows,
        label: Prefs().writingMode == WritingModeEnum.verticalRl
            ? L10n.of(context).readingPageVerticleMargin
            : L10n.of(context).readingPageSideMargin,
        value: bookStyle.sideMargin,
        onChanged: (double value) {
          setState(() {
            bookStyle.sideMargin = value;
            epubPlayerKey.currentState?.changeStyle(bookStyle);
            Prefs().saveBookStyleToPrefs(bookStyle);
          });
        },
        min: 0,
        max: 20,
        divisions: 20,
        labelFormatter: (value) => value.toStringAsFixed(1),
        enabled: true, // Side margin is always enabled
      );
    }

    Widget letterSpacingSlider(BookStyle bookStyle, StateSetter setState) {
      bool enabled = !Prefs().useBookStyles;
      return StyleSlider(
        icon: Icons.compare_arrows,
        label: L10n.of(context).readingPageLetterSpacing,
        value: bookStyle.letterSpacing,
        onChanged: (double value) {
          setState(() {
            bookStyle.letterSpacing = value;
            epubPlayerKey.currentState?.changeStyle(bookStyle);
            Prefs().saveBookStyleToPrefs(bookStyle);
          });
        },
        min: -3,
        max: 7,
        divisions: 10,
        labelFormatter: (value) => value.toString(),
        enabled: enabled,
      );
    }

    Row topBottomMarginSlider(BookStyle bookStyle, StateSetter setState) {
      return Row(children: [
        Prefs().writingMode == WritingModeEnum.verticalRl
            ? IconAndText(
                icon: const Icon(Bootstrap.chevron_bar_right),
                text: L10n.of(context).readingPageRightMargin,
              )
            : IconAndText(
                icon: const Icon(Bootstrap.chevron_bar_up),
                text: L10n.of(context).readingPageTopMargin,
              ),
        Expanded(
          child: Slider(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            value: bookStyle.topMargin,
            onChanged: (double value) {
              setState(() {
                bookStyle.topMargin = value;
                epubPlayerKey.currentState?.changeStyle(bookStyle);
                Prefs().saveBookStyleToPrefs(bookStyle);
              });
            },
            min: 0,
            max: 200,
            divisions: 10,
            label: (bookStyle.topMargin / 20).toStringAsFixed(0),
          ),
        ),
        Prefs().writingMode == WritingModeEnum.verticalRl
            ? IconAndText(
                icon: const Icon(Bootstrap.chevron_bar_left),
                text: L10n.of(context).readingPageLeftMargin,
              )
            : IconAndText(
                icon: const Icon(Bootstrap.chevron_bar_down),
                text: L10n.of(context).readingPageBottomMargin,
              ),
        Expanded(
          child: Slider(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            value: bookStyle.bottomMargin,
            onChanged: (double value) {
              setState(() {
                bookStyle.bottomMargin = value;
                epubPlayerKey.currentState?.changeStyle(bookStyle);
                Prefs().saveBookStyleToPrefs(bookStyle);
              });
            },
            min: 0,
            max: 200,
            divisions: 10,
            label: (bookStyle.bottomMargin / 20).toStringAsFixed(0),
          ),
        ),
      ]);
    }

    Widget headingFontSizeSlider(BookStyle bookStyle, StateSetter setState) {
      bool enabled = !Prefs().useBookStyles;
      return StyleSlider(
        icon: Icons.title,
        label: L10n.of(context).headingFontSize,
        value: bookStyle.headingFontSize,
        onChanged: (double value) {
          setState(() {
            bookStyle.headingFontSize = value;
            epubPlayerKey.currentState?.changeStyle(bookStyle);
            Prefs().saveBookStyleToPrefs(bookStyle);
          });
        },
        min: 0.5,
        max: 2.0,
        divisions: 15,
        labelFormatter: (value) => value.toStringAsFixed(1),
        enabled: enabled,
      );
    }

    Widget textAlignment() {
      final items = [
        {
          "icon": Icons.auto_awesome,
          "text": L10n.of(context).textAlignmentAuto,
          "value": TextAlignmentEnum.auto
        },
        {
          "icon": Icons.format_align_left,
          "text": L10n.of(context).textAlignmentLeft,
          "value": TextAlignmentEnum.left
        },
        {
          "icon": Icons.format_align_center,
          "text": L10n.of(context).textAlignmentCenter,
          "value": TextAlignmentEnum.center
        },
        {
          "icon": Icons.format_align_right,
          "text": L10n.of(context).textAlignmentRight,
          "value": TextAlignmentEnum.right
        },
        {
          "icon": Icons.format_align_justify,
          "text": L10n.of(context).textAlignmentJustify,
          "value": TextAlignmentEnum.justify
        },
      ];

      return StatefulBuilder(
        builder: (context, setState) => Row(
          children: [
            Icon(Icons.format_align_left,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(L10n.of(context).textAlignment),
            const Spacer(),
            DropdownMenu<TextAlignmentEnum>(
              width: 140,
              initialSelection: Prefs().textAlignment,
              inputDecorationTheme: InputDecorationTheme(
                isDense: false,
                border: InputBorder.none,
              ),
              dropdownMenuEntries: items.map((item) {
                return DropdownMenuEntry<TextAlignmentEnum>(
                  value: item["value"] as TextAlignmentEnum,
                  label: item["text"] as String,
                  leadingIcon: Icon(item["icon"] as IconData),
                );
              }).toList(),
              onSelected: (value) {
                if (value != null) {
                  setState(() {
                    Prefs().textAlignment = value;
                    epubPlayerKey.currentState?.changeStyle(Prefs().bookStyle);
                  });
                }
              },
            ),
          ],
        ),
      );
    }

    Widget sliders() {
      BookStyle bookStyle = Prefs().bookStyle;
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => Column(
          children: [
            textIndent(bookStyle, setState),
            sideMarginSlider(bookStyle, setState),
            topBottomMarginSlider(bookStyle, setState),
            letterSpacingSlider(bookStyle, setState),
            headingFontSizeSlider(bookStyle, setState),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          useBookStylesSwitch(),
          if (epubPlayerKey.currentState?.supportsDocumentImages == true)
            SwitchListTile(
              title: Text(
                  ModuStrings.text(context, '按裁边与分格阅读', 'Read cropped panels')),
              subtitle: Text(ModuStrings.text(context, '按已保存的顺序翻区域，再翻原页；关闭恢复原版',
                  'Follow saved panels before turning the original page; turn off for the original layout')),
              value: epubPlayerKey.currentState!.pdfPanelReading,
              onChanged: _changingPdfMode
                  ? null
                  : (enabled) async {
                      final player = epubPlayerKey.currentState;
                      if (player == null) return;
                      setState(() => _changingPdfMode = true);
                      try {
                        await player.setPdfPanelReading(enabled);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(ModuStrings.text(
                                  context,
                                  '版式切换失败，请重试',
                                  'Could not change layout. Please retry.'))));
                        }
                      } finally {
                        if (mounted) setState(() => _changingPdfMode = false);
                      }
                    },
            ),
          if (epubPlayerKey.currentState?.supportsDocumentImages == true &&
              epubPlayerKey.currentState!.pdfPanelReading)
            PdfReadingControls(
              key: ValueKey(epubPlayerKey.currentState!.cssBookKey),
              initial: epubPlayerKey.currentState!.pdfReadingView,
              watermarkAvailable: _watermarkAvailable,
              save: epubPlayerKey.currentState!.setPdfReadingView,
              pan: epubPlayerKey.currentState!.panPdfReadingView,
              preview: (request) async {
                final player = epubPlayerKey.currentState!;
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
                final player = epubPlayerKey.currentState;
                if (player?.isImageEpub == true) {
                  player?.cancelEpubImageRender();
                } else {
                  player?.cancelPdfRegionRender();
                }
              },
            ),
          if (epubPlayerKey.currentState?.supportsDocumentImages == true &&
              epubPlayerKey.currentState?.isPdfDocument == true)
            ListTile(
              leading: const Icon(Icons.crop),
              title: Text(ModuStrings.text(
                  context, 'PDF 裁边与分格', 'PDF crop and panels')),
              subtitle: Text(ModuStrings.text(context, '预览、编辑并保存本书版式',
                  'Preview, edit and save this book’s layout')),
              onTap: _openPdfPreview,
            ),
          if (epubPlayerKey.currentState?.isImageEpub == true)
            ListTile(
                leading: const Icon(Icons.image_outlined),
                title: Text(ModuStrings.text(
                    context, '图片 EPUB 原图', 'EPUB image pages')),
                subtitle: Text(ModuStrings.text(
                    context,
                    '按正文顺序查看图片页，支持裁边、分格与增强；文字章节保留原阅读方式',
                    'Browse image pages in spine order with crop, panels and enhancement; text sections keep the original reader')),
                onTap: _openEpubImages),
          if (epubPlayerKey.currentState?.supportsDocumentImages == true)
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: Text(ModuStrings.text(
                  context, '文档类型检测', 'Document type inspection')),
              subtitle: Text(ModuStrings.text(
                  context,
                  '本机检测 PDF 文字层及 EPUB 正文图片',
                  'Inspect PDF text layers and EPUB body images locally')),
              onTap: () {
                final player = epubPlayerKey.currentState;
                if (player == null) return;
                final store = DocumentTypeStore(Prefs().prefs);
                final documentKey = player.cssBookKey;
                showDialog<void>(
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
          const Divider(),
          sliders(),
          const SizedBox(height: 16),
          const Divider(),
          textAlignment(),
          CustomCSSEditor(
            key: ValueKey(epubPlayerKey.currentState?.cssBookKey),
            bookKey: epubPlayerKey.currentState?.cssBookKey,
          ),
        ],
      ),
    );
  }
}
