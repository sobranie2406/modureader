import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/models/custom_css_profile.dart';
import 'package:modu_reader/service/reading/text_filter.dart';
import 'package:modu_reader/service/reading/reflow_css.dart';
import 'package:modu_reader/service/tts/tts_page_source.dart';

void main() {
  for (final mode in ['text', 'paragraph']) {
    test('$mode filters speech while preserving original offsets', () {
      const text = '前文关注公众号后文。\n下一段。';
      final rules = [CustomCssProfile(pattern: '关注公众号', filterMode: mode)];
      final ranges = filteredTextRanges(text, rules);
      final masked = maskFilteredText(text, ranges);
      expect(masked.length, text.length);
      expect(masked, isNot(contains('关注')));
      expect(masked.contains('后文'), mode == 'text');
      TextRange? highlight;
      final source = TtsPageSource(text,
          chapter: 'test',
          excludedRanges: (value) => filteredTextRanges(value, rules),
          onHighlight: (value) => highlight = value);
      final spoken = source.currentText();
      expect(spoken, isNot(contains('关注')));
      expect(text.substring(highlight!.start, highlight!.end), isNotEmpty);
      if (mode == 'paragraph') expect(highlight!.start, text.indexOf('下一段'));
      expect(filteredTextRanges(text, []), isEmpty);
    });
  }
  test('continuous narration skips pages containing only filtered text',
      () async {
    var page = 0;
    final source = TtsPageSource('开始。',
        chapter: '0',
        excludedRanges: (text) => filteredTextRanges(text,
            [const CustomCssProfile(pattern: '广告', filterMode: 'paragraph')]),
        onNextPage: (source, current) async {
          page++;
          source.replacePage(page == 1 ? '广告' : '下一页正文。', chapter: '$page');
          return true;
        });
    expect(source.currentText(), '开始。');
    expect(await source.nextTextContinuous(), '下一页正文。');
    expect(page, 2);
  });

  test('starting on an entirely filtered page advances to readable text',
      () async {
    final source = TtsPageSource('广告',
        chapter: '0',
        excludedRanges: (text) => filteredTextRanges(text,
            [const CustomCssProfile(pattern: '广告', filterMode: 'paragraph')]),
        onNextPage: (source, current) async {
          source.replacePage('正文。', chapter: '1');
          return true;
        });
    expect(await source.currentTextContinuous(), '正文。');
  });

  test('filter mode round trips independently from regex highlight', () {
    const rule = CustomCssProfile(pattern: 'a.b\n[x]', filterMode: 'text');
    final restored = CustomCssProfile.fromJson(rule.toJson());
    expect(restored.isFilter, true);
    expect(restored.isHighlight, false);
    expect(filteredTextRanges('aXb a.b [x]', [restored]), [
      const TextRange(start: 4, end: 7),
      const TextRange(start: 8, end: 11)
    ]);
  });
  test('reflow applies basic CSS but ignores unrelated selectors', () {
    final style = ReflowCss([
      const CustomCssProfile(
          css:
              'p { font-size: 24px; color: #123456; line-height: 1.8; text-align: center; } img { font-size: 60px; }')
    ], const TextStyle(fontSize: 20));
    expect(style.textStyle.fontSize, 24);
    expect(style.textStyle.color, const Color(0xff123456));
    expect(style.textStyle.height, 1.8);
    expect(style.alignment, TextAlign.center);
  });
}
