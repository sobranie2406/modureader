import 'dart:convert';
import 'package:anx_reader/models/custom_css_profile.dart';
import 'package:anx_reader/service/config_transfer/custom_css_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all layout and highlight presets round trip in portable files', () {
    for (final p in customCssTemplates) {
      final text = CustomCssTransfer.encode([p]);
      expect(
          CustomCssTransfer.decode(text, fileName: 'rules.json')
              .single
              .toJson(),
          p.toJson());
    }
  });
  test('plain CSS import preserves source and strips BOM', () {
    final p =
        CustomCssTransfer.decode('\uFEFFp { color: red; }', fileName: '小说.css')
            .single;
    expect(p.name, '小说');
    expect(p.css, 'p { color: red; }');
    expect(p.isHighlight, false);
  });
  test('import never overwrites existing or reserved named slots', () {
    final existing = List.generate(8,
        (i) => i < 2 ? CustomCssProfile(name: '$i') : const CustomCssProfile());
    final result =
        CustomCssTransfer.append(existing, [customCssTemplates.last]);
    expect(result[0].name, '0');
    expect(result[1].name, '1');
    expect(result[2].pattern, customCssTemplates.last.pattern);
    expect(existing[2].isEmpty, true);
    expect(() => CustomCssTransfer.append(existing, customCssTemplates),
        throwsFormatException);
  });
  test('reject oversized and malformed bundles and empty exports', () {
    expect(
        () => CustomCssTransfer.decode('x' * (CustomCssTransfer.maxBytes + 1),
            fileName: 'a.css'),
        throwsFormatException);
    expect(() => CustomCssTransfer.encode([const CustomCssProfile()]),
        throwsFormatException);
    for (final profile in [
      {'name': 'x', 'css': '', 'pattern': 2},
      {'name': 'x', 'css': '', 'scope': 'script'},
      {'name': 'x', 'css': '', 'pattern': 'x' * 513},
    ]) {
      final text = jsonEncode({
        'kind': CustomCssTransfer.kind,
        'version': 1,
        'profiles': [profile]
      });
      expect(() => CustomCssTransfer.decode(text, fileName: 'a.json'),
          throwsFormatException);
    }
  });
}
