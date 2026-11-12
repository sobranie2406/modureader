import 'package:anx_reader/widgets/settings/font_name_preview.dart';
import 'reader_menu_appearance.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'reader_menu_group.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/document_reading_mode.dart';
import 'package:anx_reader/widgets/reading_page/document_style_widget.dart';
import 'package:anx_reader/widgets/reading_page/chinese_conversion_button.dart';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book_style.dart';
import 'package:anx_reader/service/ocr/document_text_style.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/page/settings_page/subpage/fonts.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/service/book_player/reader_font_response.dart';
import 'package:anx_reader/service/book_player/reading_appearance.dart';
import 'package:anx_reader/service/font.dart';
import 'package:anx_reader/utils/font_parser.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/icon_and_text.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/more_settings.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/scroll_page_percent_tile.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/scroll_auto_align_tile.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/continuous_scroll_tile.dart';
import 'package:anx_reader/widgets/reading_page/widget_title.dart';
import 'reader_settings_scroll_view.dart';
import 'package:anx_reader/dao/theme.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/widgets/reading_page/widgets/bgimg_selector.dart';
import 'package:flutter/material.dart';
import 'package:anx_reader/widgets/common/app_scroll_behavior.dart';
import 'package:anx_reader/widgets/common/color_picker_sheet.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

enum PageTurn {
  noAnimation,
  slide,
  scroll;

  String getLabel(BuildContext context) {
    switch (this) {
      case PageTurn.noAnimation:
        return L10n.of(context).noAnimation;
      case PageTurn.slide:
        return L10n.of(context).slide;
      case PageTurn.scroll:
        return L10n.of(context).scroll;
    }
  }
}

class StyleWidget extends StatefulWidget {
  const StyleWidget({
    super.key,
    required this.themes,
    this.epubPlayerKey,
    required this.setCurrentPage,
    required this.hideAppBarAndBottomBar,
    this.documentStyle,
    this.saveDocumentStyle,
    this.documentSaving = false,
    this.onDocumentSettings,
  });

  final List<ReadTheme> themes;
  final GlobalKey<EpubPlayerState>? epubPlayerKey;
  final DocumentTextStyle? documentStyle;
  final Future<void> Function(DocumentTextStyle)? saveDocumentStyle;
  final bool documentSaving;
  final VoidCallback? onDocumentSettings;
  final Function setCurrentPage;
  final Function hideAppBarAndBottomBar;

  @override
  StyleWidgetState createState() => StyleWidgetState();
}

class StyleWidgetState extends State<StyleWidget> {
  late BookStyle bookStyle = _initialStyle();
  int? currentThemeId = Prefs().readTheme.id;
  bool get _document => widget.documentStyle != null;
  bool get _enabled =>
      _document ? !widget.documentSaving : !Prefs().useBookStyles;

  BookStyle _initialStyle() {
    final document = widget.documentStyle;
    return document == null
        ? Prefs().bookStyle
        : BookStyle(
            fontSize: document.size,
            fontWeight: document.weight * 400,
            lineHeight: document.height,
            paragraphSpacing: document.paragraphSpacing);
  }

  @override
  void didUpdateWidget(covariant StyleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.documentStyle != oldWidget.documentStyle) {
      bookStyle = _initialStyle();
    }
  }

  Future<void> _saveStyle() async {
    final document = widget.documentStyle;
    if (document != null) {
      await widget.saveDocumentStyle?.call(DocumentTextStyle.fromJson({
        ...document.toJson(),
        'size': bookStyle.fontSize,
        'weight': bookStyle.fontWeight / 400,
        'height': bookStyle.lineHeight,
        'paragraphSpacing': bookStyle.paragraphSpacing,
      }));
    } else {
      widget.epubPlayerKey?.currentState?.changeStyle(bookStyle);
      Prefs().saveBookStyleToPrefs(bookStyle);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_document) return _textBookStyle(context);
    final player = widget.epubPlayerKey?.currentState;
    if (player == null) return _textBookStyle(context);
    return ValueListenableBuilder<DocumentReadingMode>(
      valueListenable: player.documentReadingMode,
      builder: (context, mode, _) => mode.hasDocumentMenu
          ? DocumentStyleWidget(
              key: ValueKey(player.cssBookKey),
              player: player,
              openReflow: (forceOcr) => readingPageKey.currentState
                  ?.openDocumentExtraction(reflow: true, forceOcr: forceOcr))
          : _textBookStyle(context),
    );
  }

  Widget _textBookStyle(BuildContext context) {
    return ReaderSettingsScrollView(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widgetTitle(L10n.of(context).readingPageStyle,
            _document ? null : ReadingSettings.theme,
            onSettings: _document ? widget.onDocumentSettings : null),
        ReaderMenuGroup(padding: const EdgeInsets.all(12), child: sliders()),
        ReaderMenuGroup(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            fontAndPageTurn(),
            if (!_document && Prefs().pageTurnStyle == PageTurn.scroll) ...[
              const SizedBox(height: 16),
              ContinuousScrollTile(onChanged: (value) {
                widget.epubPlayerKey?.currentState
                    ?.changeContinuousScroll(value);
              }),
              const SizedBox(height: 12),
              ScrollPagePercentTile(onChanged: (value) {
                widget.epubPlayerKey?.currentState
                    ?.changeScrollPagePercent(value);
              }),
              ScrollAutoAlignTile(onChanged: (value) {
                widget.epubPlayerKey?.currentState
                    ?.changeScrollAutoAlign(value);
              }),
            ],
            if (!_document) ...[
              const SizedBox(height: 20),
              englishFontSelector(),
            ],
          ]),
        ),
        ReaderMenuGroup(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(child: themeSelector()),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: () {
                    widget.setCurrentPage(
                        BgimgSelector(onChanged: _document ? () {} : null));
                  },
                  icon: const Icon(Icons.arrow_forward_ios),
                  iconAlignment: IconAlignment.end,
                  label: Text(L10n.of(context).readingPageStyleBackground),
                )
              ],
            )),
      ],
    ));
  }

  List<FontModel> fonts() {
    if (_document) {
      final choices = [
        FontModel(
            label: L10n.of(context).systemFont, name: 'system', path: 'system'),
        FontModel(
            label: ModuStrings.text(context, '思源宋体', 'Source Han Serif'),
            name: 'serif',
            path: 'serif'),
      ];
      try {
        for (final file in getFontDir().listSync().whereType<File>()) {
          final name = file.uri.pathSegments.last;
          if (RegExp(r'\.(ttf|otf)$', caseSensitive: false).hasMatch(name)) {
            choices.add(FontModel(
                label: getFontNameFromFile(file), name: name, path: name));
          }
        }
      } catch (_) {/* No imported fonts yet. */}
      return choices;
    }
    Directory fontDir = getFontDir();
    List<FontModel> fontList = [
      FontModel(
        label: L10n.of(context).downloadFonts,
        name: 'download',
        path: 'download',
      ),
      FontModel(
        label: L10n.of(context).addNewFont,
        name: 'newFont',
        path: 'newFount',
      ),
      FontModel(
        label: L10n.of(context).followBook,
        name: 'book',
        path: 'book',
      ),
      FontModel(
        label: L10n.of(context).systemFont,
        name: 'system',
        path: 'system',
      ),
    ];
    final files = fontDir
        .listSync()
        .whereType<File>()
        .where((file) =>
            RegExp(r'\.(ttf|otf)$', caseSensitive: false).hasMatch(file.path))
        .toList();
    for (int i = 0; i < files.length; i++) {
      final element = files[i];
      fontList.add(FontModel(
        label: getFontNameFromFile(element),
        name: 'customFont$i',
        path: readerFontUrl(
            element.path.split(Platform.pathSeparator).last, Server().port),
      ));
    }

    return fontList;
  }

  Widget fontAndPageTurn() {
    final document = widget.documentStyle;
    final selectedPath = document == null
        ? Prefs().font.path
        : document.font.isNotEmpty
            ? document.font
            : document.serif
                ? 'serif'
                : 'system';
    FontModel? font = fonts().firstWhere(
        (element) => element.path == selectedPath,
        orElse: () => _document
            ? fonts().first
            : FontModel(
                label: L10n.of(context).followBook,
                name: 'book',
                path: 'book'));

    Widget? leadingIcon(String name) {
      if (name == 'download') {
        return const Icon(Icons.download);
      } else if (name == 'newFont') {
        return const Icon(Icons.add);
      }
      return null;
    }

    final pageTurn = DropdownMenu<PageTurn>(
      key: const ValueKey('reader-page-turn'),
      label: Text(L10n.of(context).readingPagePageTurningMethod),
      initialSelection: _document ? PageTurn.scroll : Prefs().pageTurnStyle,
      enabled: !_document,
      expandedInsets: const EdgeInsets.only(right: 5),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
        ),
      ),
      onSelected: (PageTurn? value) {
        if (value != null) {
          setState(() => Prefs().pageTurnStyle = value);
          widget.epubPlayerKey?.currentState?.changePageTurnStyle(value);
        }
      },
      dropdownMenuEntries: PageTurn.values
          .map((e) => DropdownMenuEntry(
                value: e,
                label: e.getLabel(context),
              ))
          .toList(),
    );
    final bodyFont = fontPreviewBuilder(
        font.litePath,
        (family) => DropdownMenu<FontModel>(
              textStyle: family == null ? null : TextStyle(fontFamily: family),
              key: ValueKey('reader-body-font-$selectedPath'),
              enabled: !_document || _enabled,
              label: Text(
                  ModuStrings.text(context, '中文／正文字体', 'Chinese / body font')),
              expandedInsets: const EdgeInsets.only(left: 5),
              initialSelection: font,
              inputDecorationTheme: InputDecorationTheme(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(50),
                ),
              ),
              onSelected: (FontModel? font) async {
                if (font == null) return;
                if (document != null) {
                  await widget.saveDocumentStyle?.call(document
                      .withValue('serif', font.name == 'serif')
                      .withValue(
                          'font',
                          ['system', 'serif'].contains(font.name)
                              ? ''
                              : font.path));
                  return;
                }
                if (font.name == 'newFont') {
                  // Hiding the toolbar disposes this StyleWidget. Keep the reader
                  // key, and apply even when this settings panel is no longer mounted.
                  final readerKey = widget.epubPlayerKey;
                  widget.hideAppBarAndBottomBar(false);
                  await importFont(onApplied: (imported) {
                    readerKey?.currentState?.changeFont(imported);
                  });
                  if (mounted) setState(() {});
                  return;
                } else if (font.name == 'download') {
                  widget.hideAppBarAndBottomBar(false);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const FontsSettingPage()),
                  );
                  return;
                } else {
                  widget.epubPlayerKey?.currentState?.changeFont(font);
                  Prefs().font = font;
                }
              },
              dropdownMenuEntries: fonts()
                  .map((font) => DropdownMenuEntry(
                        value: font,
                        label: font.label,
                        labelWidget: FontNamePreview(font.label,
                            filename:
                                RegExp(r'\.(ttf|otf)$', caseSensitive: false)
                                        .hasMatch(font.litePath)
                                    ? font.litePath
                                    : null),
                        leadingIcon: leadingIcon(font.name),
                      ))
                  .toList(),
            ));
    final fontAndConversion = Row(children: [
      Expanded(child: bodyFont),
      if (!_document)
        ChineseConversionButton(onChanged: (rules) {
          widget.epubPlayerKey?.currentState?.changeReadingRules(rules);
        }),
    ]);
    // Keep the font name usable on phones instead of squeezing three controls
    // into the original two-column row.
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 600) {
        return Column(children: [
          pageTurn,
          const SizedBox(height: 20),
          fontAndConversion,
        ]);
      }
      return Row(children: [
        Expanded(child: pageTurn),
        Expanded(flex: 2, child: fontAndConversion),
      ]);
    });
  }

  Widget englishFontSelector() {
    final follow = FontModel(
        label: ModuStrings.text(context, '跟随正文字体', 'Follow body font'),
        name: 'follow',
        path: 'follow');
    final choices = [follow, ...fonts().where((font) => font.name != 'book')];
    final selected = Prefs().englishFont;
    final current = choices.firstWhere(
        (font) => selected != null && font.litePath == selected.litePath,
        orElse: () => follow);
    return fontPreviewBuilder(
        current.litePath,
        (family) => DropdownMenu<FontModel>(
              textStyle: family == null ? null : TextStyle(fontFamily: family),
              key: ValueKey('english-font-${current.litePath}'),
              label: Text(ModuStrings.text(
                  context, '英文字体（字母、数字）', 'English font (letters, numbers)')),
              expandedInsets: EdgeInsets.zero,
              initialSelection: current,
              inputDecorationTheme: InputDecorationTheme(
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(50))),
              dropdownMenuEntries: choices
                  .map((font) => DropdownMenuEntry(
                      value: font,
                      label: font.label,
                      labelWidget: FontNamePreview(font.label,
                          filename:
                              RegExp(r'\.(ttf|otf)$', caseSensitive: false)
                                      .hasMatch(font.litePath)
                                  ? font.litePath
                                  : null)))
                  .toList(),
              onSelected: (font) async {
                if (font == null) return;
                final readerKey = widget.epubPlayerKey;
                if (font.name == 'newFont') {
                  widget.hideAppBarAndBottomBar(false);
                  await importFont(
                      target: FontTarget.english,
                      onApplied: (imported) {
                        readerKey?.currentState?.changeEnglishFont(imported);
                      });
                } else if (font.name == 'download') {
                  widget.hideAppBarAndBottomBar(false);
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const FontsSettingPage()));
                } else {
                  final selected = font.name == 'follow' ? null : font;
                  Prefs().englishFont = selected;
                  readerKey?.currentState?.changeEnglishFont(selected);
                }
                if (mounted) setState(() {});
              },
            ));
  }

  Padding sliders() {
    return Padding(
      padding: const EdgeInsets.all(3.0),
      child: Column(
        children: [
          fontSizeSlider(),
          fontWeightSlider(),
          lineHeightAndParagraphSpacingSlider(),
        ],
      ),
    );
  }

  Row fontWeightSlider() {
    final colors = Theme.of(context).colorScheme;
    final enabled = _enabled;
    final selected = bookStyle.simulateBold;
    return Row(
      children: [
        IconAndText(
          flexibleHeight: true,
          icon: const Icon(Icons.format_bold),
          text: ModuStrings.text(context, '字体粗细', 'Font thickness'),
        ),
        Expanded(
          child: Slider(
            key: ValueKey(
                _document ? 'ocr-style-weight' : 'reading-font-weight-slider'),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            value: (bookStyle.fontWeight / 400).clamp(0.5, 2.0).toDouble(),
            onChanged: !enabled
                ? null
                : (double value) {
                    setState(() =>
                        bookStyle.fontWeight = (value * 400).roundToDouble());
                    if (!_document) _saveStyle();
                  },
            onChangeEnd: _document && enabled ? (_) => _saveStyle() : null,
            min: 0.5,
            max: 2.0,
            divisions: 15,
            label:
                (bookStyle.fontWeight / 400).clamp(0.5, 2.0).toStringAsFixed(1),
          ),
        ),
        if (!_document)
          Tooltip(
            message: ModuStrings.text(context, "1.0 为原字重，调高可加粗文字。",
                "1.0 keeps the original weight. Increase it for bolder text."),
            child: Semantics(
              key: const ValueKey('reading-simulated-bold-toggle'),
              button: true,
              toggled: bookStyle.simulateBold,
              enabled: !Prefs().useBookStyles,
              child: SizedBox(
                width: 108,
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    side: BorderSide(
                      color: !enabled
                          ? colors.onSurface.withValues(alpha: 0.12)
                          : selected
                              ? colors.primary
                              : colors.outlineVariant,
                      width: selected && enabled ? 1.5 : 1,
                    ),
                    backgroundColor: Prefs().eInkMode
                        ? Colors.transparent
                        : selected
                            ? colors.primaryContainer
                            : null,
                    foregroundColor: selected
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                    disabledBackgroundColor: Prefs().eInkMode
                        ? Colors.transparent
                        : colors.onSurface.withValues(alpha: 0.04),
                    disabledForegroundColor:
                        colors.onSurface.withValues(alpha: 0.38),
                  ),
                  onPressed: Prefs().useBookStyles
                      ? null
                      : () {
                          setState(() =>
                              bookStyle.simulateBold = !bookStyle.simulateBold);
                          widget.epubPlayerKey?.currentState
                              ?.changeStyle(bookStyle);
                          Prefs().saveBookStyleToPrefs(bookStyle);
                        },
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          ModuStrings.text(context, '模拟加粗', 'Simulated bold'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Row lineHeightAndParagraphSpacingSlider() {
    bool enabled = _enabled;
    return Row(
      children: [
        IconAndText(
          flexibleHeight: true,
          icon: const Icon(Icons.line_weight),
          text: L10n.of(context).readingPageLineSpacing,
        ),
        Expanded(
          child: Slider(
              key: ValueKey(_document
                  ? 'ocr-style-height'
                  : 'reading-line-height-slider'),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              value: _document
                  ? bookStyle.lineHeight
                  : bookStyle.lineHeight.clamp(1.0, 3.0),
              onChanged: enabled
                  ? (double value) {
                      setState(() {
                        bookStyle.lineHeight = value;
                        if (!_document) _saveStyle();
                      });
                    }
                  : null,
              onChangeEnd: _document && enabled ? (_) => _saveStyle() : null,
              min: _document ? 1.2 : 1,
              max: _document ? 2.4 : 3,
              divisions: _document ? 12 : 10,
              label: _document
                  ? bookStyle.lineHeight.toStringAsFixed(1)
                  : ((bookStyle.lineHeight.clamp(1.0, 3.0) - 1) / 2 * 10)
                      .round()
                      .toString()),
        ),
        IconAndText(
          flexibleHeight: true,
          icon: const Icon(Icons.height),
          text: L10n.of(context).readingPageParagraphSpacing,
        ),
        Expanded(
          child: Slider(
            key: ValueKey(_document
                ? 'ocr-style-paragraphSpacing'
                : 'reading-paragraph-spacing-slider'),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            value: bookStyle.paragraphSpacing,
            onChanged: enabled
                ? (double value) {
                    setState(() {
                      bookStyle.paragraphSpacing = value;
                      if (!_document) _saveStyle();
                    });
                  }
                : null,
            min: 0,
            onChangeEnd: _document && enabled ? (_) => _saveStyle() : null,
            max: _document ? 3 : 5,
            divisions: _document ? 12 : 10,
            label: _document
                ? bookStyle.paragraphSpacing.toStringAsFixed(2)
                : (bookStyle.paragraphSpacing / 5 * 10).round().toString(),
          ),
        ),
      ],
    );
  }

  Row fontSizeSlider() {
    bool enabled = _enabled;
    return Row(
      children: [
        IconAndText(
          flexibleHeight: true,
          icon: const Icon(Icons.format_size),
          text: L10n.of(context).readingPageFontSize,
        ),
        Expanded(
          child: Slider(
            key: ValueKey(
                _document ? 'ocr-style-size' : 'reading-font-size-slider'),
            value: bookStyle.fontSize,
            onChanged: enabled
                ? (double value) {
                    setState(() {
                      bookStyle.fontSize = value;
                      if (!_document) _saveStyle();
                    });
                  }
                : null,
            onChangeEnd: _document && enabled ? (_) => _saveStyle() : null,
            min: _document ? 14 : 0.5,
            max: _document ? 40 : 3.0,
            divisions: _document ? 26 : 25,
            label: bookStyle.fontSize.toStringAsFixed(2),
          ),
        ),
      ],
    );
  }

  SizedBox themeSelector() {
    const size = 40.0;
    const paddingSize = 5.0;
    EdgeInsetsGeometry padding = const EdgeInsets.all(paddingSize);
    return SizedBox(
      height: size + paddingSize * 2,
      child: ListView.builder(
        itemCount: widget.themes.length + 1,
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          if (index == widget.themes.length) {
            // add a new theme
            return Padding(
              padding: padding,
              child: Container(
                  padding: padding,
                  width: size,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(
                      color: Colors.black45,
                      width: 1,
                    ),
                  ),
                  child: InkWell(
                    onTap: () async {
                      int currId = await themeDao.insertTheme(ReadTheme(
                          backgroundColor: 'ff121212',
                          textColor: 'ffcccccc',
                          backgroundImagePath: ''));
                      widget.setCurrentPage(ThemeChangeWidget(
                        applyTheme: _document ? (_) {} : null,
                        readTheme: ReadTheme(
                            id: currId,
                            backgroundColor: 'ff121212',
                            textColor: 'ffcccccc',
                            backgroundImagePath: ''),
                        setCurrentPage: widget.setCurrentPage,
                      ));
                    },
                    child: Icon(Icons.add,
                        size: size / 2,
                        color: Color(int.parse('0x${'ffcccccc'}'))),
                  )),
            );
          }
          // theme list
          return Padding(
            padding: padding,
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: Color(
                    int.parse('0x${widget.themes[index].backgroundColor}')),
                borderRadius: BorderRadius.circular(50),
                border: Border.all(
                  color: widget.themes[index].id == currentThemeId
                      ? Theme.of(context).primaryColor
                      : Colors.black45,
                  width: widget.themes[index].id == currentThemeId ? 3 : 1,
                ),
              ),
              height: size,
              width: size,
              child: InkWell(
                onTap: () {
                  selectReadingColorTheme(widget.themes[index], prefs: Prefs(),
                      apply: (theme) {
                    if (!_document) {
                      widget.epubPlayerKey?.currentState?.changeTheme(theme);
                      widget.epubPlayerKey?.currentState?.changeBgimgEffect();
                    }
                  });
                  setState(() {
                    currentThemeId = widget.themes[index].id;
                  });
                },
                onSecondaryTap: () {
                  setState(() {
                    widget.setCurrentPage(ThemeChangeWidget(
                      applyTheme: _document ? (_) {} : null,
                      readTheme: widget.themes[index],
                      setCurrentPage: widget.setCurrentPage,
                    ));
                  });
                },
                onLongPress: () {
                  setState(() {
                    widget.setCurrentPage(ThemeChangeWidget(
                      applyTheme: _document ? (_) {} : null,
                      readTheme: widget.themes[index],
                      setCurrentPage: widget.setCurrentPage,
                    ));
                  });
                },
                child: Center(
                  child: Text(
                    "A",
                    style: TextStyle(
                      color: Color(
                          int.parse('0x${widget.themes[index].textColor}')),
                      fontSize: size / 3,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ThemeChangeWidget extends StatefulWidget {
  const ThemeChangeWidget({
    super.key,
    required this.readTheme,
    required this.setCurrentPage,
    this.saveTheme,
    this.applyTheme,
    this.allowDelete = true,
  });

  final ReadTheme readTheme;
  final Function setCurrentPage;
  final Future<void> Function(ReadTheme)? saveTheme;
  final void Function(ReadTheme)? applyTheme;
  final bool allowDelete;

  @override
  State<ThemeChangeWidget> createState() => _ThemeChangeWidgetState();
}

class _ThemeChangeWidgetState extends State<ThemeChangeWidget> {
  late ReadTheme readTheme;
  bool _saving = false;

  Future<void> _editColor({required bool background}) async {
    final color = await showColorPickerDialog(
        background ? readTheme.backgroundColor : readTheme.textColor,
        background: background);
    if (!mounted || color == null) return;
    final updated = ReadTheme(
      id: readTheme.id,
      backgroundColor: background ? color : readTheme.backgroundColor,
      textColor: background ? readTheme.textColor : color,
      backgroundImagePath: readTheme.backgroundImagePath,
    );
    setState(() => _saving = true);
    try {
      await (widget.saveTheme?.call(updated) ?? themeDao.updateTheme(updated));
      if (!mounted) return;
      // Update the shared theme entry only after persistence succeeded.
      setState(() {
        readTheme.backgroundColor = updated.backgroundColor;
        readTheme.textColor = updated.textColor;
      });
      selectReadingColorTheme(updated,
          prefs: Prefs(), clearBackgroundImage: background, apply: (theme) {
        if (widget.applyTheme != null) {
          widget.applyTheme!(theme);
        } else {
          epubPlayerKey.currentState?.changeTheme(theme);
          epubPlayerKey.currentState?.changeBgimgEffect();
        }
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(ModuStrings.text(context, '保存主题失败，请重试。',
              'Could not save the theme. Please try again.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void initState() {
    super.initState();
    readTheme = widget.readTheme;
  }

  @override
  Widget build(BuildContext context) {
    return ReaderMenuGroup(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.all(8),
        child: Wrap(spacing: 12, runSpacing: 12, children: [
          OutlinedButton.icon(
            key: const ValueKey('reading-background-color'),
            onPressed: _saving ? null : () => _editColor(background: true),
            label: Text(ModuStrings.text(context, '背景颜色', 'Background colour')),
            icon: Icon(Icons.circle,
                size: 32,
                color: Color(int.parse('0x${readTheme.backgroundColor}'))),
          ),
          OutlinedButton.icon(
              key: const ValueKey('reading-text-color'),
              onPressed: _saving ? null : () => _editColor(background: false),
              label: Text(ModuStrings.text(context, '文字颜色', 'Text colour')),
              icon: Icon(Icons.text_fields,
                  size: 32,
                  color: Color(int.parse('0x${readTheme.textColor}')))),
          if (widget.allowDelete)
            IconButton(
              onPressed: () {
                themeDao.deleteTheme(readTheme.id!);
                widget.setCurrentPage(const SizedBox(height: 1));
                // setState(() {});
              },
              icon: const Icon(
                Icons.delete,
                size: 40,
              ),
            ),
        ]));
  }

  Future<String?> showColorPickerDialog(String currColor,
      {required bool background}) async {
    Color pickedColor = Color(int.parse('0x$currColor'));

    return showReaderDialog<String>(
      animationStyle: AppMotion.style,
      context: context,
      builder: (BuildContext context) {
        return ScrollConfiguration(
            behavior: const AppScrollBehavior(symmetricGutter: true),
            child: AlertDialog(
              title: Text(background
                  ? ModuStrings.text(context, '背景颜色', 'Background colour')
                  : ModuStrings.text(context, '文字颜色', 'Text colour')),
              content: SingleChildScrollView(
                child: ColorPicker(
                  hexInputBar: true,
                  pickerColor: pickedColor,
                  onColorChanged: (Color color) {
                    pickedColor = color;
                  },
                  pickerAreaHeightPercent: 0.8,
                ),
              ),
              actions: <Widget>[
                TextButton.icon(
                  key: const ValueKey('reset-reading-color'),
                  icon: const Icon(Icons.restore),
                  label: Text(
                      ModuStrings.text(context, '恢复默认', 'Restore default')),
                  onPressed: () async {
                    final confirmed = await confirmColorReset(
                        context,
                        background
                            ? ModuStrings.text(context, '恢复默认背景颜色？文字颜色保持不变。',
                                'Restore the default background colour? Text colour will not change.')
                            : ModuStrings.text(context, '恢复默认文字颜色？背景颜色保持不变。',
                                'Restore the default text colour? Background colour will not change.'));
                    if (confirmed && context.mounted) {
                      Navigator.of(context).pop(background
                          ? ReadTheme.defaultBackgroundColor
                          : ReadTheme.defaultTextColor);
                    }
                  },
                ),
                TextButton(
                  child: Text(ModuStrings.text(context, '取消', 'Cancel')),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: Text(ModuStrings.text(context, '确定', 'OK')),
                  onPressed: () {
                    Navigator.of(context).pop(pickedColor
                        .toARGB32()
                        .toRadixString(16)
                        .padLeft(8, '0'));
                  },
                ),
              ],
            ));
      },
    );
  }
}
