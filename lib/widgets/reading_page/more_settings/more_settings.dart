import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/other_settings.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/reading_settings.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/style_settings.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/custom_css_editor.dart';
import 'package:flutter/material.dart';
import 'package:anx_reader/service/ocr/document_text_style.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import '../reader_settings_scroll_view.dart';
import '../reader_menu_group.dart';

enum ReadingSettings { theme, style }

void showMoreSettings(ReadingSettings settings) {
  final context = navigatorKey.currentContext!;
  readingPageKey.currentState!.showOrHideAppBarAndBottomBar(false);
  showReaderPopup(context,
      enableDrag: false,
      builder: (_) => ReaderMoreSettings(settings: settings));
}

class ReaderMoreSettings extends StatefulWidget {
  const ReaderMoreSettings(
      {super.key,
      required this.settings,
      this.documentStyle,
      this.saveDocumentStyle});
  final ReadingSettings settings;
  final DocumentTextStyle? documentStyle;
  final Future<void> Function(DocumentTextStyle)? saveDocumentStyle;

  @override
  State<ReaderMoreSettings> createState() => _ReaderMoreSettingsState();
}

class _ReaderMoreSettingsState extends State<ReaderMoreSettings> {
  late DocumentTextStyle? _documentStyle = widget.documentStyle;
  bool get _document => _documentStyle != null;
  bool _saving = false;

  Future<void> _save(DocumentTextStyle value) async {
    setState(() => _saving = true);
    try {
      await widget.saveDocumentStyle?.call(value);
      if (mounted) _documentStyle = value;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookKey = epubPlayerKey.currentState?.cssBookKey;
    return DefaultTabController(
      length: 4,
      initialIndex: widget.settings == ReadingSettings.theme ? 0 : 1,
      animationDuration: AppMotion.duration(const Duration(milliseconds: 300)),
      child: Column(children: [
        Row(children: [
          Expanded(
              child: TabBar(tabs: [
            Tab(text: L10n.of(context).readingPageReading),
            Tab(text: L10n.of(context).readingPageStyle),
            const Tab(text: 'CSS'),
            Tab(text: L10n.of(context).readingPageOther),
          ])),
          const CloseButton(),
        ]),
        const Divider(height: 0),
        Expanded(
            child: AbsorbPointer(
                absorbing: _saving,
                child: TabBarView(children: [
                  ReaderSettingsScrollView(
                      child: ReadingMoreSettings(
                          readerMenu: true, documentMode: _document)),
                  ReaderSettingsScrollView(
                      child: StyleSettings(
                          readerMenu: true,
                          documentStyle: _documentStyle,
                          saveDocumentStyle: _save)),
                  ReaderSettingsScrollView(
                      child: ReaderMenuGroup(
                    padding: const EdgeInsets.all(8),
                    child: Column(children: [
                      if (_document)
                        Text(ModuStrings.text(
                            context,
                            '重排支持文字过滤和字体、字号、颜色、行距、字距、对齐等文字样式。代码仅适配 html、body、p、*；复杂选择器、图片布局和正则高亮暂不适用。',
                            'Reflow supports text filters and basic text styles. CSS supports html, body, p and *. Complex selectors, image layout and regex highlights are not supported.')),
                      CustomCSSEditor(key: ValueKey(bookKey), bookKey: bookKey),
                    ]),
                  )),
                  ReaderSettingsScrollView(
                      child: OtherSettings(
                          readerMenu: true, documentMode: _document)),
                ]))),
      ]),
    );
  }
}
