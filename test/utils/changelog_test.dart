import 'dart:io';
import 'package:modu_reader/utils/changelog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final history = File('assets/CHANGELOG.md').readAsStringSync();
  test('1.3.0 to 1.3.5 contains every missed stable release in Chinese', () {
    final text = changelogSince(history,
        previous: '1.3.0+10152', current: '1.3.5+10167', chinese: true);
    expect(
        RegExp(r'^## (.+)$', multiLine: true)
            .allMatches(text)
            .map((m) => m.group(1))
            .toList(),
        ['1.3.5', '1.3.4', '1.3.3', '1.3.2', '1.3.1']);
    expect(text, contains('移除 Windows'));
    expect(text, isNot(contains('Remove the permission')));
  });
  test('language blocks with unequal lengths keep paragraphs and every bullet',
      () {
    const fixture =
        '## 1.3.5\n### English\nIntro\n- A\n- B\n### 简体中文\n说明\n- 甲\n';
    expect(
        changelogSince(fixture,
            previous: '1.3.4', current: '1.3.5', chinese: false),
        '## 1.3.5\n\nIntro\n- A\n- B');
    expect(
        changelogSince(fixture,
            previous: '1.3.4', current: '1.3.5', chinese: true),
        '## 1.3.5\n\n说明\n- 甲');
  });
  test(
      'same version, build-only update and downgrade show current release only',
      () {
    for (final previous in ['1.3.4+1', '1.3.5', 'unknown']) {
      final text = changelogSince(history,
          previous: previous, current: '1.3.4+2', chinese: false);
      expect(RegExp(r'^## ', multiLine: true).allMatches(text).length, 1);
      expect(text, startsWith('## 1.3.4\n'));
    }
  });
  test('semantic order and preview boundaries do not include future releases',
      () {
    const fixture = '## 1.3.10\n### English\n- ten\n'
        '## 1.3.9\n### English\n- nine\n'
        '## 1.3.9-beta.2\n### English\n- beta two\n'
        '## 1.3.9-beta.1\n### English\n- beta one\n';
    expect(
        changelogSince(fixture,
            previous: '1.3.9', current: '1.3.10', chinese: false),
        '## 1.3.10\n\n- ten');
    expect(
        changelogSince(fixture,
            previous: '1.3.9-beta.1', current: '1.3.9-beta.2', chinese: false),
        '## 1.3.9-beta.2\n\n- beta two');
    expect(
        changelogSince(fixture,
            previous: '1.3.9-beta.2', current: '1.3.9', chinese: false),
        '## 1.3.9\n\n- nine');
  });
  test('legacy bilingual history is selected within each version', () {
    final text = changelogSince(history,
        previous: '1.1.10', current: '1.1.11', chinese: true);
    expect(text, contains('修复 AI 回答末尾丢字'));
    expect(text, isNot(contains('Fix missing final')));
  });
  test('missing notes or invalid current version return empty content', () {
    for (final current in ['invalid', '9.0.0']) {
      expect(
          changelogSince(history,
              previous: current, current: current, chinese: true),
          isEmpty);
    }
  });
}
