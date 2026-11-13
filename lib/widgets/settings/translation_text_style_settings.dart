import 'dart:io';
import 'package:modu_reader/enums/lang_list.dart';
import 'package:modu_reader/widgets/icon_and_text.dart';
import 'package:modu_reader/widgets/settings/translation_preview_text.dart';
import 'package:flutter/material.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/translation_text_style.dart';
import 'package:modu_reader/utils/get_path/get_base_path.dart';
import 'package:modu_reader/widgets/settings/settings_section.dart';
import 'package:modu_reader/widgets/settings/settings_tile.dart';
import 'package:modu_reader/widgets/settings/text_color_setting.dart';

class TranslationTextStyleSettings extends StatefulWidget {
  const TranslationTextStyleSettings({super.key, this.classical = true});
  final bool classical;
  @override
  State<TranslationTextStyleSettings> createState() =>
      _TranslationTextStyleSettingsState();
}

class _TranslationTextStyleSettingsState
    extends State<TranslationTextStyleSettings> {
  late var style = TranslationTextStyle.decode(widget.classical
      ? Prefs().classicalTranslationTextStyle
      : Prefs().languageTranslationTextStyle);
  String get prefix => widget.classical ? 'classical' : 'language';
  final fonts = <String>[];
  @override
  void initState() {
    super.initState();
    try {
      fonts.addAll(getFontDir()
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((name) =>
              RegExp(r'\.(ttf|otf)$', caseSensitive: false).hasMatch(name)));
      fonts.sort();
    } catch (_) {/* Font directory can be empty on a new installation. */}
    loadFont();
  }

  Future<void> loadFont() async {
    try {
      await style.loadFont();
    } catch (_) {/* Use platform fallback for unavailable fonts. */}
    if (mounted) setState(() {});
  }

  void change(String key, Object value) {
    setState(() => style = style.withValue(key, value));
    if (widget.classical) {
      Prefs().classicalTranslationTextStyle = style.encode();
    } else {
      Prefs().languageTranslationTextStyle = style.encode();
    }
    if (key == 'font') loadFont();
  }

  String t(String zh, String en) => ModuStrings.text(context, zh, en);
  Future<void> pick<T>(
      String title, T current, Map<T, String> options, String key) async {
    final value = await showDialog<T>(
        context: context,
        builder: (context) => SimpleDialog(title: Text(title), children: [
              for (final entry in options.entries)
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, entry.key),
                    child: Row(children: [
                      Expanded(child: Text(entry.value)),
                      if (entry.key == current) const Icon(Icons.check)
                    ]))
            ]));
    if (value != null && mounted) change(key, value as Object);
  }

  @override
  Widget build(BuildContext context) {
    // Body reading uses a 16 px base with a 0.5–3.0 multiplier. Keep the
    // persisted pixel value so existing translation styles retain their size.
    final sliderSize =
        style.size == 0 ? 1.0 : (style.size / 16).clamp(0.5, 3.0);
    final sizeLabel = sliderSize.toStringAsFixed(1);
    final choices = {
      '': t('跟随原文', 'Follow original'),
      'system': t('系统字体', 'System font'),
      'serif': t('衬线字体', 'Serif'),
      'sans-serif': t('无衬线字体', 'Sans serif'),
      'monospace': t('等宽字体', 'Monospace'),
      for (final font in fonts) font: font,
      if (style.imported && !fonts.contains(style.font))
        style.font: '${style.font} (${t('未安装', 'not installed')})'
    };
    return SettingsSection(
        title: Text(t('译文外观', 'Translation appearance')),
        tiles: [
          SettingsTile.navigation(
              key: ValueKey('$prefix-style-font'),
              leading: const Icon(Icons.font_download_outlined),
              title: Text(t('字体', 'Font')),
              value: Text(choices[style.font]!),
              onPressed: (_) => pick(
                  t('译文字体', 'Translation font'), style.font, choices, 'font')),
          CustomSettingsTile(
              child: TextColorSetting(
                  key: ValueKey('$prefix-style-color'),
                  value: style.color,
                  defaultLabel: t('跟随原文', 'Follow original'),
                  onChanged: (value) => change('color', value))),
          CustomSettingsTile(
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(children: [
                    Row(children: [
                      IconAndText(
                          flexibleHeight: true,
                          icon: const Icon(Icons.format_size),
                          text: t('字号', 'Font size')),
                      Expanded(
                          child: Slider(
                              key: ValueKey('$prefix-style-size'),
                              value: sliderSize,
                              min: 0.5,
                              max: 3.0,
                              divisions: 25,
                              label: sizeLabel,
                              semanticFormatterCallback: (value) =>
                                  value.toStringAsFixed(1),
                              onChanged: (value) => change(
                                  'size', (value * 10).round() / 10 * 16))),
                    ]),
                    Row(children: [
                      Expanded(child: Text(sizeLabel)),
                      TextButton(
                          key: ValueKey('$prefix-style-size-reset'),
                          onPressed: style.size == 0
                              ? null
                              : () => change('size', 0.0),
                          child: Text(t('跟随原文', 'Follow original'))),
                    ]),
                  ]))),
          SettingsTile.switchTile(
              key: ValueKey('$prefix-style-bold'),
              leading: const Icon(Icons.format_bold),
              title: Text(t('粗体', 'Bold')),
              initialValue: style.bold,
              onToggle: (value) => change('bold', value)),
          SettingsTile.switchTile(
              key: ValueKey('$prefix-style-italic'),
              leading: const Icon(Icons.format_italic),
              title: Text(t('斜体', 'Italic')),
              initialValue: style.italic,
              onToggle: (value) => change('italic', value)),
          CustomSettingsTile(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            widget.classical
                                ? t("调整文言文译文的字体和颜色。",
                                    "Set the font and colors for classical Chinese translations.")
                                : t("调整译文的字体和颜色。",
                                    "Set the font and colors for translations."),
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 12),
                        Text(t('译文预览', 'Translation preview'),
                            style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(height: 8),
                        ListenableBuilder(
                            listenable: Prefs(),
                            builder: (context, _) {
                              final target = Prefs().fullTextTranslateTo;
                              return Text(
                                  widget.classical
                                      ? t('学习并时常温习，不也是一件愉快的事吗？',
                                          'Is it not a pleasure to learn and practise?')
                                      : translationPreviewText(target),
                                  key: ValueKey('$prefix-style-preview'),
                                  textDirection: widget.classical
                                      ? null
                                      : target == LangListEnum.arabic
                                          ? TextDirection.rtl
                                          : TextDirection.ltr,
                                  style: style.textStyle);
                            }),
                      ]))),
        ]);
  }
}
