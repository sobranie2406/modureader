import 'package:modu_reader/widgets/settings/setting_help_title.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import '../reader_menu_group.dart';
import 'package:modu_reader/enums/text_alignment.dart';
import 'package:modu_reader/enums/writing_mode.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/models/book_style.dart';
import 'package:modu_reader/page/reading_page.dart';
import 'package:modu_reader/widgets/icon_and_text.dart';
import 'package:flutter/material.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:modu_reader/service/ocr/document_text_style.dart';
import 'reader_setting_availability.dart';

// Reusable style slider widget that can be disabled
class StyleSlider extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
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
    this.onChangeEnd,
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
            onChangeEnd: enabled ? onChangeEnd : null,
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
  const StyleSettings(
      {super.key,
      this.documentStyle,
      this.saveDocumentStyle,
      this.readerMenu = false});
  final DocumentTextStyle? documentStyle;
  final Future<void> Function(DocumentTextStyle)? saveDocumentStyle;
  final bool readerMenu;

  @override
  State<StyleSettings> createState() => _StyleSettingsState();
}

class _StyleSettingsState extends State<StyleSettings> {
  bool get _document => widget.documentStyle != null;
  double get _readerWidth => MediaQuery.sizeOf(context).width;
  int _alignmentRevision = 0;

  Future<void> _saveBookStyle(BookStyle value, {String? field}) async {
    if (!_document) {
      epubPlayerKey.currentState?.changeStyle(value);
      Prefs().saveBookStyleToPrefs(value);
      return;
    }
    try {
      final values = {
        'margin': value.sideMargin * _readerWidth / 100,
        'topMargin': value.topMargin,
        'bottomMargin': value.bottomMargin,
        'spacing': value.letterSpacing,
      };
      await widget.saveDocumentStyle
          ?.call(widget.documentStyle!.withValue(field!, values[field]!));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(L10n.of(context).commonFailed)));
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget useBookStylesSwitch() {
      return SwitchListTile(
        title: SettingHelpTitle(
            title: L10n.of(context).useBookStyles,
            description: L10n.of(context).useBookStylesDescription),
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
      bool enabled = !_document && !Prefs().useBookStyles;
      return StyleSlider(
        icon: Icons.format_indent_increase,
        label: L10n.of(context).readingPageIndent,
        value: bookStyle.indent,
        onChanged: (double value) {
          setState(() {
            bookStyle.indent = value;
            _saveBookStyle(bookStyle);
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
        icon: !_document && Prefs().writingMode == WritingModeEnum.verticalRl
            ? Bootstrap.arrows_vertical
            : Bootstrap.arrows,
        label: !_document && Prefs().writingMode == WritingModeEnum.verticalRl
            ? L10n.of(context).readingPageVerticleMargin
            : L10n.of(context).readingPageSideMargin,
        value: bookStyle.sideMargin,
        onChanged: (double value) {
          setState(() {
            bookStyle.sideMargin = value;
            if (!_document) _saveBookStyle(bookStyle);
          });
        },
        onChangeEnd: _document
            ? (_) => _saveBookStyle(bookStyle, field: 'margin')
            : null,
        min: 0,
        max: 20,
        divisions: 20,
        labelFormatter: (value) => value.toStringAsFixed(1),
        enabled: true, // Side margin is always enabled
      );
    }

    Widget letterSpacingSlider(BookStyle bookStyle, StateSetter setState) {
      bool enabled = _document || !Prefs().useBookStyles;
      return StyleSlider(
        icon: Icons.compare_arrows,
        label: L10n.of(context).readingPageLetterSpacing,
        value: bookStyle.letterSpacing,
        onChanged: (double value) {
          setState(() {
            bookStyle.letterSpacing = value;
            if (!_document) _saveBookStyle(bookStyle);
          });
        },
        onChangeEnd: _document
            ? (_) => _saveBookStyle(bookStyle, field: 'spacing')
            : null,
        min: -3,
        max: 7,
        divisions: 10,
        labelFormatter: (value) => value.toString(),
        enabled: enabled,
      );
    }

    Row topBottomMarginSlider(BookStyle bookStyle, StateSetter setState) {
      return Row(children: [
        !_document && Prefs().writingMode == WritingModeEnum.verticalRl
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
                if (!_document) _saveBookStyle(bookStyle);
              });
            },
            onChangeEnd: _document
                ? (_) => _saveBookStyle(bookStyle, field: 'topMargin')
                : null,
            min: 0,
            max: 200,
            divisions: 10,
            label: (bookStyle.topMargin / 20).toStringAsFixed(0),
          ),
        ),
        !_document && Prefs().writingMode == WritingModeEnum.verticalRl
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
                if (!_document) _saveBookStyle(bookStyle);
              });
            },
            onChangeEnd: _document
                ? (_) => _saveBookStyle(bookStyle, field: 'bottomMargin')
                : null,
            min: 0,
            max: 200,
            divisions: 10,
            label: (bookStyle.bottomMargin / 20).toStringAsFixed(0),
          ),
        ),
      ]);
    }

    Widget headingFontSizeSlider(BookStyle bookStyle, StateSetter setState) {
      bool enabled = !_document && !Prefs().useBookStyles;
      return StyleSlider(
        icon: Icons.title,
        label: L10n.of(context).headingFontSize,
        value: bookStyle.headingFontSize,
        onChanged: (double value) {
          setState(() {
            bookStyle.headingFontSize = value;
            _saveBookStyle(bookStyle);
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
              key: ValueKey(_document
                  ? (
                      widget.documentStyle!.textAlignment,
                      widget.documentStyle!.justify,
                      _alignmentRevision
                    )
                  : Prefs().textAlignment),
              initialSelection: _document
                  ? TextAlignmentEnum.fromCode(
                      widget.documentStyle!.textAlignment ??
                          (widget.documentStyle!.justify ? 'justify' : 'left'))
                  : Prefs().textAlignment,
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
                  if (_document) {
                    final old = widget.documentStyle!;
                    widget.saveDocumentStyle
                        ?.call(old.withValue('textAlignment', value.code))
                        .catchError((Object error) {
                      if (context.mounted) {
                        this.setState(() => _alignmentRevision++);
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            SnackBar(
                                content: Text(L10n.of(context).commonFailed)));
                      }
                    });
                    return;
                  }
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
      final document = widget.documentStyle;
      BookStyle bookStyle = document == null
          ? Prefs().bookStyle
          : BookStyle(
              sideMargin: (document.margin / _readerWidth * 100).clamp(0, 20),
              topMargin: document.padding.top,
              bottomMargin: document.padding.bottom,
              letterSpacing: document.spacing);
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => Column(
          children: [
            ReaderSettingAvailability(
                enabled: !_document, child: textIndent(bookStyle, setState)),
            sideMarginSlider(bookStyle, setState),
            topBottomMarginSlider(bookStyle, setState),
            letterSpacingSlider(bookStyle, setState),
            ReaderSettingAvailability(
                enabled: !_document,
                child: headingFontSizeSlider(bookStyle, setState)),
          ],
        ),
      );
    }

    if (!widget.readerMenu) {
      return Container(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          ReaderSettingAvailability(
              enabled: !_document, child: useBookStylesSwitch()),
          const Divider(),
          sliders(),
          const SizedBox(height: 16),
          const Divider(),
          textAlignment(),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReaderMenuGroup(
              padding: const EdgeInsets.all(12),
              child: ReaderSettingAvailability(
                  enabled: !_document, child: useBookStylesSwitch())),
          ReaderMenuGroup(padding: const EdgeInsets.all(12), child: sliders()),
          ReaderMenuGroup(
              padding: const EdgeInsets.all(12), child: textAlignment()),
        ],
      ),
    );
  }
}
