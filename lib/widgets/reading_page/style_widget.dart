import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book_style.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/page/settings_page/subpage/fonts.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/service/book_player/reading_appearance.dart';
import 'package:anx_reader/service/font.dart';
import 'package:anx_reader/utils/font_parser.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/icon_and_text.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/more_settings.dart';
import 'package:anx_reader/widgets/reading_page/widget_title.dart';
import 'package:anx_reader/dao/theme.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/widgets/reading_page/widgets/bgimg_selector.dart';
import 'package:flutter/material.dart';
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
    required this.epubPlayerKey,
    required this.setCurrentPage,
    required this.hideAppBarAndBottomBar,
  });

  final List<ReadTheme> themes;
  final GlobalKey<EpubPlayerState> epubPlayerKey;
  final Function setCurrentPage;
  final Function hideAppBarAndBottomBar;

  @override
  StyleWidgetState createState() => StyleWidgetState();
}

class StyleWidgetState extends State<StyleWidget> {
  BookStyle bookStyle = Prefs().bookStyle;
  int? currentThemeId = Prefs().readTheme.id;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          widgetTitle(L10n.of(context).readingPageStyle, ReadingSettings.theme),
          sliders(),
          const SizedBox(height: 10),
          fontAndPageTurn(),
          const Divider(),
          Row(
            children: [
              Expanded(child: themeSelector()),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: () {
                  widget.setCurrentPage(const BgimgSelector());
                },
                icon: const Icon(Icons.arrow_forward_ios),
                iconAlignment: IconAlignment.end,
                label: Text(L10n.of(context).readingPageStyleBackground),
              )
            ],
          ),
        ],
      ),
    );
  }

  List<FontModel> fonts() {
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
    // fontDir.listSync().forEach((element) {
    //   if (element is File) {
    //     fontList.add(FontModel(
    //       label: getFontNameFromFile(element),
    //       name: 'customFont' + ,
    //       path:
    //           'http://127.0.0.1:${Server().port}/fonts/${element.path.split('/').last}',
    //     ));
    //   }
    // });
    // name = 'customFont' + index
    for (int i = 0; i < fontDir.listSync().length; i++) {
      File element = fontDir.listSync()[i] as File;
      fontList.add(FontModel(
        label: getFontNameFromFile(element),
        name: 'customFont$i',
        path:
            'http://127.0.0.1:${Server().port}/fonts/${element.path.split(Platform.pathSeparator).last}',
      ));
    }

    return fontList;
  }

  Widget fontAndPageTurn() {
    FontModel? font = fonts().firstWhere(
        (element) => element.path == Prefs().font.path,
        orElse: () => FontModel(
            label: L10n.of(context).followBook, name: 'book', path: 'book'));

    Widget? leadingIcon(String name) {
      if (name == 'download') {
        return const Icon(Icons.download);
      } else if (name == 'newFont') {
        return const Icon(Icons.add);
      }
      return null;
    }

    return Row(children: [
      Expanded(
        child: DropdownMenu<PageTurn>(
          label: Text(L10n.of(context).readingPagePageTurningMethod),
          initialSelection: Prefs().pageTurnStyle,
          expandedInsets: const EdgeInsets.only(right: 5),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(50),
            ),
          ),
          onSelected: (PageTurn? value) {
            if (value != null) {
              Prefs().pageTurnStyle = value;
              epubPlayerKey.currentState!.changePageTurnStyle(value);
            }
          },
          dropdownMenuEntries: PageTurn.values
              .map((e) => DropdownMenuEntry(
                    value: e,
                    label: e.getLabel(context),
                  ))
              .toList(),
        ),
      ),
      Expanded(
        child: DropdownMenu<FontModel>(
          label: Text(L10n.of(context).font),
          expandedInsets: const EdgeInsets.only(left: 5),
          initialSelection: font,
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(50),
            ),
          ),
          onSelected: (FontModel? font) async {
            if (font == null) return;
            if (font.name == 'newFont') {
              widget.hideAppBarAndBottomBar(false);
              await importFont();
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
              epubPlayerKey.currentState!.changeFont(font);
              Prefs().font = font;
            }
          },
          dropdownMenuEntries: fonts()
              .map((font) => DropdownMenuEntry(
                    value: font,
                    label: font.label,
                    leadingIcon: leadingIcon(font.name),
                  ))
              .toList(),
        ),
      ),
    ]);
  }

  Padding sliders() {
    return Padding(
      padding: const EdgeInsets.all(3.0),
      child: Column(
        children: [
          fontSizeSlider(),
          lineHeightAndParagraphSpacingSlider(),
        ],
      ),
    );
  }

  Row lineHeightAndParagraphSpacingSlider() {
    bool enabled = !Prefs().useBookStyles;
    return Row(
      children: [
        IconAndText(
          icon: const Icon(Icons.line_weight),
          text: L10n.of(context).readingPageLineSpacing,
        ),
        Expanded(
          child: Slider(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              value: bookStyle.lineHeight,
              onChanged: enabled
                  ? (double value) {
                      setState(() {
                        bookStyle.lineHeight = value;
                        widget.epubPlayerKey.currentState!
                            .changeStyle(bookStyle);
                        Prefs().saveBookStyleToPrefs(bookStyle);
                      });
                    }
                  : null,
              min: 0,
              max: 3,
              divisions: 10,
              label: (bookStyle.lineHeight / 3 * 10).round().toString()),
        ),
        IconAndText(
          icon: const Icon(Icons.height),
          text: L10n.of(context).readingPageParagraphSpacing,
        ),
        Expanded(
          child: Slider(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            value: bookStyle.paragraphSpacing,
            onChanged: enabled
                ? (double value) {
                    setState(() {
                      bookStyle.paragraphSpacing = value;
                      widget.epubPlayerKey.currentState!.changeStyle(bookStyle);
                      Prefs().saveBookStyleToPrefs(bookStyle);
                    });
                  }
                : null,
            min: 0,
            max: 5,
            divisions: 10,
            label: (bookStyle.paragraphSpacing / 5 * 10).round().toString(),
          ),
        ),
      ],
    );
  }

  Row fontSizeSlider() {
    bool enabled = !Prefs().useBookStyles;
    return Row(
      children: [
        IconAndText(
          icon: const Icon(Icons.format_size),
          text: L10n.of(context).readingPageFontSize,
        ),
        Expanded(
          child: Slider(
            value: bookStyle.fontSize,
            onChanged: enabled
                ? (double value) {
                    setState(() {
                      bookStyle.fontSize = value;
                      widget.epubPlayerKey.currentState!.changeStyle(bookStyle);
                      Prefs().saveBookStyleToPrefs(bookStyle);
                    });
                  }
                : null,
            min: 0.5,
            max: 3.0,
            divisions: 25,
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
                    widget.epubPlayerKey.currentState?.changeTheme(theme);
                    widget.epubPlayerKey.currentState?.changeBgimgEffect();
                  });
                  setState(() {
                    currentThemeId = widget.themes[index].id;
                  });
                },
                onSecondaryTap: () {
                  setState(() {
                    widget.setCurrentPage(ThemeChangeWidget(
                      readTheme: widget.themes[index],
                      setCurrentPage: widget.setCurrentPage,
                    ));
                  });
                },
                onLongPress: () {
                  setState(() {
                    widget.setCurrentPage(ThemeChangeWidget(
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
  });

  final ReadTheme readTheme;
  final Function setCurrentPage;
  final Future<void> Function(ReadTheme)? saveTheme;
  final void Function(ReadTheme)? applyTheme;

  @override
  State<ThemeChangeWidget> createState() => _ThemeChangeWidgetState();
}

class _ThemeChangeWidgetState extends State<ThemeChangeWidget> {
  late ReadTheme readTheme;
  bool _saving = false;

  Future<void> _editColor({required bool background}) async {
    final color = await showColorPickerDialog(
        background ? readTheme.backgroundColor : readTheme.textColor);
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
          content: Text(Localizations.localeOf(context).languageCode == 'zh'
              ? '保存主题失败，请重试。'
              : 'Could not save the theme. Please try again.'),
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
    return Row(children: [
      IconButton(
        onPressed: _saving ? null : () => _editColor(background: true),
        icon: Icon(Icons.circle,
            size: 80,
            color: Color(int.parse('0x${readTheme.backgroundColor}'))),
      ),
      IconButton(
          onPressed: _saving ? null : () => _editColor(background: false),
          icon: Icon(Icons.text_fields,
              size: 60, color: Color(int.parse('0x${readTheme.textColor}')))),
      const Expanded(
        child: SizedBox(),
      ),
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
    ]);
  }

  Future<String?> showColorPickerDialog(String currColor) async {
    Color pickedColor = Color(int.parse('0x$currColor'));

    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
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
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop(
                    pickedColor.toARGB32().toRadixString(16).padLeft(8, '0'));
              },
            ),
          ],
        );
      },
    );
  }
}
