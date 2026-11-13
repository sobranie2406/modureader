import 'package:flutter/material.dart';
import 'package:modu_reader/models/custom_css_profile.dart';

/// Native reflow has paragraphs, but no publication HTML elements/selectors.
class ReflowCss {
  ReflowCss(List<CustomCssProfile> profiles, TextStyle base)
      : textStyle = base {
    for (final profile in profiles) {
      if (profile.isFilter || profile.isHighlight || profile.scope == 'title') {
        continue;
      }
      final v = profile.visual?.values ?? const <String, Object>{};
      apply('font-size', v['size']?.toString());
      apply('font-weight', v['weight']?.toString());
      apply('line-height', v['lineHeight']?.toString());
      apply(
          'letter-spacing', v['spacing'] == null ? null : '${v['spacing']}em');
      apply('color', v['color']?.toString());
      apply('background-color', v['background']?.toString());
      apply('font-style', v['italic'] == true ? 'italic' : null);
      apply('text-align', v['align']?.toString());
      apply('font-family', v['font']?.toString());
      if (v['paragraphGap'] is num) {
        paragraphGap = (v['paragraphGap'] as num).toDouble();
      }
      final css = profile.css.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
      for (final rule in RegExp(r'([^{}]+)\{([^{}]*)\}').allMatches(css)) {
        if (!rule[1]!
            .split(',')
            .any((s) => const ['*', 'html', 'body', 'p'].contains(s.trim()))) {
          continue;
        }
        for (final declaration in rule[2]!.split(';')) {
          final colon = declaration.indexOf(':');
          if (colon < 0) continue;
          apply(
              declaration.substring(0, colon).trim(),
              declaration
                  .substring(colon + 1)
                  .replaceAll('!important', '')
                  .trim());
        }
      }
    }
  }
  TextStyle textStyle;
  TextAlign? alignment;
  double? paragraphGap;
  void apply(String property, String? value) {
    if (value == null) return;
    final match = RegExp(r'^(-?\d+(?:\.\d+)?)(px|em)?$').firstMatch(value);
    final n = match == null ? null : double.tryParse(match[1]!);
    final pixels = n == null
        ? null
        : n * (match![2] == 'em' ? (textStyle.fontSize ?? 20) : 1);
    Color? color() {
      if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) return null;
      return Color(0xff000000 | int.parse(value.substring(1), radix: 16));
    }

    switch (property) {
      case 'font-size':
        if (pixels != null) {
          textStyle = textStyle.copyWith(fontSize: pixels.clamp(8, 64));
        }
      case 'font-weight':
        if (n != null) {
          textStyle = textStyle.copyWith(
              fontWeight:
                  FontWeight.values[((n / 100).round() - 1).clamp(0, 8)]);
        }
      case 'line-height':
        if (n != null) {
          textStyle = textStyle.copyWith(
              height: (match![2] == 'px' ? n / (textStyle.fontSize ?? 20) : n)
                  .clamp(0.5, 4));
        }
      case 'letter-spacing':
        if (pixels != null) {
          textStyle = textStyle.copyWith(letterSpacing: pixels.clamp(-5, 20));
        }
      case 'color':
        textStyle = textStyle.copyWith(color: color());
      case 'background-color':
        textStyle = textStyle.copyWith(backgroundColor: color());
      case 'font-style':
        if (value == 'italic' || value == 'normal') {
          textStyle = textStyle.copyWith(
              fontStyle:
                  value == 'italic' ? FontStyle.italic : FontStyle.normal);
        }
      case 'font-family':
        if (const ['serif', 'sans-serif', 'monospace'].contains(value)) {
          textStyle = textStyle.copyWith(
              fontFamily: value == 'serif' ? 'SourceHanSerif' : value);
        }
      case 'text-align':
        alignment = switch (value) {
          'center' => TextAlign.center,
          'left' || 'start' => TextAlign.start,
          'right' || 'end' => TextAlign.end,
          'justify' => TextAlign.justify,
          _ => alignment
        };
    }
  }
}
