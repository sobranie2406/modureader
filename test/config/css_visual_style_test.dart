import 'dart:convert';
import 'package:anx_reader/models/css_visual_style.dart';
import 'package:anx_reader/models/custom_css_profile.dart';
import 'package:anx_reader/service/config_transfer/custom_css_transfer.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('modules generate scoped CSS, advanced code comes last', () {
    const visual = CssVisualStyle({
      'color': '#112233',
      'weight': 600,
      'decoration': 'wavy',
      'offset': 3,
      'italic': true
    });
    const profile = CustomCssProfile(
        name: 'Title',
        css: 'h1 {color:red !important;}',
        scope: 'title',
        visual: visual);
    expect(profile.compiledCss, contains('h1, h2, h3'));
    expect(profile.compiledCss, contains('font-weight: 600 !important;'));
    expect(profile.compiledCss, contains('text-underline-offset: 3px'));
    expect(profile.compiledCss, endsWith(profile.css));
    expect(visual.withValue('color', null).values, isNot(contains('color')));
    expect(visual.values['color'], '#112233');
  });

  test('regex highlights exclude layout changes and keep safe paint styles',
      () {
    const visual = CssVisualStyle({
      'color': '#112233',
      'background': '#abcdef',
      'decoration': 'dashed',
      'weight': 600,
      'font': 'serif',
      'offset': 3
    });
    final css = visual.css(scope: 'body', highlight: true);
    expect(css, contains('text-decoration-style: dashed'));
    expect(css, contains('background-color: #abcdef'));
    expect(css, isNot(contains('font-')));
    expect(css, isNot(contains('offset')));
    expect(css, isNot(contains('!important')));
  });

  test('portable templates round-trip local font names and visual parameters',
      () {
    const profile = CustomCssProfile(
        name: '字体',
        visual: CssVisualStyle(
            {'fontFile': '宋体 test.ttf', 'weight': 500, 'lineHeight': 1.8}));
    final encoded = CustomCssTransfer.encode([profile]);
    final restored =
        CustomCssTransfer.decode(encoded, fileName: 'test.json').single;
    expect(restored.toJson(), profile.toJson());
    expect(restored.compiledCss,
        contains('/fonts/${Uri.encodeComponent('宋体 test.ttf')}'));
    expect(restored.compiledCss, contains('@font-face'));
  });

  test('malformed graphical settings rejected before either import writes', () {
    for (final values in [
      {'color': 'red;display:none'},
      {'weight': 2000},
      {'italic': 'yes'},
      {'fontFile': '../secret.ttf'},
      {'backgroundImage': 'https://example.com/x.png'},
      {'unknown': true},
      {'decoration': 'invalid'},
    ]) {
      final profile = {'name': 'Bad', 'css': '', 'visual': jsonEncode(values)};
      expect(
          () => CustomCssTransfer.decode(
              jsonEncode({
                'kind': CustomCssTransfer.kind,
                'version': 1,
                'profiles': [profile],
              }),
              fileName: 'test.json'),
          throwsFormatException);
      expect(
          () => GlobalSettingsTransfer.validate({
                'customCssProfiles': {
                  'type': 'string',
                  'value': jsonEncode([profile])
                },
              }),
          throwsFormatException);
    }
  });

  test('all named presets compile and round-trip without code loss', () {
    expect(customCssTemplates, hasLength(13));
    for (final profile in customCssTemplates) {
      expect(profile.compiledCss, isNotEmpty, reason: profile.name);
      final restored = CustomCssProfile.fromJson(profile.toJson());
      expect(restored.compiledCss, profile.compiledCss);
    }
    expect(const CssVisualStyle().css(scope: 'all', highlight: false), isEmpty);
  });
}
