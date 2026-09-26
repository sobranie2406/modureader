import 'dart:convert';
import 'dart:io';
import 'package:anx_reader/models/css_visual_style.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/common/color_picker_sheet.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class CssVisualControls extends StatelessWidget {
  const CssVisualControls(
      {super.key,
      required this.style,
      required this.highlight,
      required this.onChanged});
  final CssVisualStyle style;
  final bool highlight;
  final ValueChanged<CssVisualStyle> onChanged;
  void change(String key, Object? value) =>
      onChanged(style.withValue(key, value));

  @override
  Widget build(BuildContext context) {
    String t(String zh, String en) =>
        Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
    Widget toggle(String key, String label, Object initial, {Widget? child}) =>
        Column(children: [
          Row(children: [
            Expanded(child: Text(label)),
            Switch(
                key: ValueKey('css-option-$key'),
                value: style.values.containsKey(key),
                onChanged: (v) => change(key, v ? initial : null))
          ]),
          if (style.values.containsKey(key) && child != null) child,
        ]);
    Widget number(String key, String label, double initial, String unit,
        {int? divisions}) {
      final range = CssVisualStyle.ranges[key]!;
      final value = (style.values[key] as num?)?.toDouble() ?? initial;
      return toggle(
          key,
          '$label (${value.toStringAsFixed(key == 'weight' || key == 'size' ? 0 : 2)} $unit)',
          initial,
          child: Slider(
              key: ValueKey('css-slider-$key'),
              value: value,
              min: range.$1,
              max: range.$2,
              divisions: divisions ??
                  ((range.$2 - range.$1) * (key == 'spacing' ? 100 : 10))
                      .round(),
              onChanged: (v) => change(key, v)));
    }

    Widget color(String key, String label, String initial) {
      final hex = style.values[key] as String? ?? initial;
      return Row(children: [
        Expanded(child: Text(label)),
        IconButton(
            key: ValueKey('css-color-$key'),
            tooltip: t('选择颜色', 'Choose color'),
            icon: Icon(Icons.circle,
                color:
                    Color(int.parse(hex.substring(1), radix: 16) | 0xff000000)),
            onPressed: !style.values.containsKey(key)
                ? null
                : () async {
                    final picked = await showRgbColorPicker(
                        context: context,
                        initialColor: Color(
                            int.parse(hex.substring(1), radix: 16) |
                                0xff000000),
                        allowAlpha: false);
                    if (picked != null && context.mounted) {
                      change(key,
                          '#${(picked.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}');
                    }
                  }),
        Switch(
            key: ValueKey('css-option-$key'),
            value: style.values.containsKey(key),
            onChanged: (v) => change(key, v ? initial : null)),
      ]);
    }

    Widget group(String label, List<Widget> children) => ExpansionTile(
        title: Text(label),
        initiallyExpanded: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        children: children);
    Widget choices(String key, Map<String, String> options) =>
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final entry in options.entries)
            ChoiceChip(
                key: ValueKey('css-choice-$key-${entry.key}'),
                label: Text(entry.value),
                selected: style.values[key] == entry.key,
                onSelected: (v) => change(key, v ? entry.key : null))
        ]);
    Widget image(String key, bool svg) => Row(children: [
          Expanded(
              child: Text(svg
                  ? t('自定义 SVG', 'Custom SVG')
                  : t('规则背景图片', 'Background image'))),
          TextButton(
              onPressed: () async {
                try {
                  final picked = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions:
                          svg ? ['svg'] : ['png', 'jpg', 'jpeg', 'webp']);
                  if (picked == null || !context.mounted) return;
                  final file = File(picked.files.single.path!);
                  if (await file.length() > 256 * 1024) {
                    throw const FormatException('Image too large');
                  }
                  final bytes = await file.readAsBytes();
                  final ext =
                      picked.files.single.name.split('.').last.toLowerCase();
                  if (svg) {
                    final source = utf8.decode(bytes);
                    // Embedded SVG is only used as an image, never as live markup.
                    if (!source.contains('<svg') ||
                        RegExp(r'<script|<foreignObject|<!DOCTYPE|<!ENTITY|\bon\w+\s*=|(?:href|url)\s*[:=(]',
                                caseSensitive: false)
                            .hasMatch(source)) {
                      throw const FormatException(
                          'Use a self-contained static SVG');
                    }
                  }
                  final mime = svg
                      ? 'svg+xml'
                      : ext == 'jpg'
                          ? 'jpeg'
                          : ext;
                  if (context.mounted) {
                    change(
                        key, 'data:image/$mime;base64,${base64Encode(bytes)}');
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(t('请选择不超过 256 KiB 的有效图片；SVG 仅支持静态图形。',
                            'Use an image up to 256 KiB; SVG must be a static drawing.'))));
                  }
                }
              },
              child: Text(style.values.containsKey(key)
                  ? t('更换', 'Replace')
                  : t('选择', 'Choose'))),
          if (style.values.containsKey(key))
            IconButton(
                onPressed: () => change(key, null),
                icon: const Icon(Icons.clear)),
        ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('关闭模块即跟随书籍原样式；自定义代码在图形参数之后叠加。',
          'Disabled modules inherit book styles. Custom code follows the visual settings.')),
      group(t('文字与背景', 'Text and background'), [
        color('color', t('自定义文字颜色', 'Text color'), '#a05000'),
        color('background', t('背景颜色', 'Background color'), '#fff4cc'),
        if (!highlight) image('backgroundImage', false),
      ]),
      group(t('下划线', 'Underline'), [
        choices('decoration', {
          'none': t('关闭', 'Off'),
          'solid': t('实线', 'Solid'),
          'dashed': t('虚线', 'Dashed'),
          'wavy': t('波浪线', 'Wavy'),
          'emphasis': t('强调条', 'Emphasis'),
          if (!highlight) 'svg': t('自定义 SVG', 'Custom SVG')
        }),
        if (style.values['decoration'] == 'svg' && !highlight) ...[
          image('underlineImage', true),
          Text(t('SVG 下划线与背景图使用同一背景层；启用时优先显示 SVG。',
              'SVG underline takes precedence over the background image.')),
        ],
        color('decorationColor', t('自定义下划线颜色', 'Underline color'), '#c0392b'),
        number('thickness', t('线条宽度', 'Thickness'), 1, 'px'),
        if (!highlight) number('offset', t('垂直偏移', 'Offset'), 2, 'px'),
      ]),
      if (!highlight) ...[
        group(t('字体', 'Font'), [
          choices('font', {
            'serif': t('衬线字体', 'Serif'),
            'sans-serif': t('无衬线字体', 'Sans serif'),
            'monospace': t('等宽字体', 'Monospace')
          }),
          Row(children: [
            Expanded(
                child: Text(style.values['fontFile']?.toString() ??
                    t('自定义字体（未设置）', 'Custom font (not set)'))),
            TextButton(
                onPressed: () async {
                  try {
                    final dir = getFontDir();
                    final files = await dir.exists()
                        ? await dir
                            .list()
                            .where((f) =>
                                f is File &&
                                RegExp(r'\.(ttf|otf)$', caseSensitive: false)
                                    .hasMatch(f.path))
                            .toList()
                        : <FileSystemEntity>[];
                    if (!context.mounted) return;
                    final selected = await showDialog<String>(
                        context: context,
                        builder: (c) => SimpleDialog(
                                title: Text(
                                    t('选择已导入字体', 'Choose an imported font')),
                                children: [
                                  if (files.isEmpty)
                                    Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Text(t('请先在字体设置中导入字体。',
                                            'Import fonts in font settings first.'))),
                                  for (final f in files)
                                    SimpleDialogOption(
                                        onPressed: () => Navigator.pop(
                                            c,
                                            f.path
                                                .split(Platform.pathSeparator)
                                                .last),
                                        child: Text(f.path
                                            .split(Platform.pathSeparator)
                                            .last))
                                ]));
                    if (selected != null && context.mounted) {
                      change('fontFile', selected);
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content:
                              Text(t('无法读取字体目录', 'Could not read fonts'))));
                    }
                  }
                },
                child: Text(t('选择', 'Choose'))),
            if (style.values.containsKey('fontFile'))
              IconButton(
                  onPressed: () => change('fontFile', null),
                  icon: const Icon(Icons.clear)),
          ]),
          Text(t('自定义字体优先于通用字体。导出仅包含文件名，其他设备需另行导入同名字体。',
              'Custom fonts take precedence. Exports include filenames only; import matching fonts on other devices.')),
          number('weight', t('字重', 'Weight'), 400, '', divisions: 8),
          number('size', t('字号', 'Size'), 20, 'px', divisions: 56),
          toggle('italic', t('斜体', 'Italic'), true),
        ]),
        group(t('段落排版', 'Paragraph layout'), [
          choices('align', {
            'start': t('起始对齐', 'Start'),
            'center': t('居中', 'Center'),
            'end': t('末尾对齐', 'End'),
            'justify': t('两端对齐', 'Justify')
          }),
          number('lineHeight', t('行距', 'Line height'), 1.8, ''),
          number('spacing', t('字间距', 'Letter spacing'), 0.08, 'em'),
          number('indent', t('首行缩进', 'Indent'), 2, 'em'),
          number('paragraphGap', t('段落间距', 'Paragraph gap'), 0.6, 'em'),
        ]),
      ] else
        Text(t('局部正则高亮仅支持颜色、背景色与下划线，不更改正文节点；字体、图片、SVG 和偏移仅用于排版模板。',
            'Regex highlights preserve text nodes and support colors and underlines only. Fonts, images, SVG and offset require a layout template.')),
    ]);
  }
}
