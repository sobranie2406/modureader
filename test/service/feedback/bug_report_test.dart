import 'dart:io';

import 'package:anx_reader/service/feedback/bug_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const report = BugReport(
    title: ' PDF & 阅读? #1 ',
    description: '无法打开\n第二行 + %',
    steps: '1. 导入\n2. 点击',
    expected: '显示内容',
    environment: 'Modu: 0.1.0-beta.1+6326\nPlatform: macOS',
  );

  test('prefills the Modu YAML form with lossless encoded text', () {
    final uri = Uri.parse(report.prefilledUri.toString());
    expect(uri.scheme, 'https');
    expect(uri.host, 'github.com');
    expect(uri.path, '/sobranie2406/modureader/issues/new');
    expect(uri.fragment, isEmpty);
    expect(uri.queryParameters['template'], 'bug-report.yaml');
    expect(uri.queryParameters['title'], '[Bug]: PDF & 阅读? #1');
    expect(uri.queryParameters['bug_report_description'], report.description);
    expect(uri.queryParameters['bug_report_reproduce'], report.steps);
    expect(
        uri.queryParameters['bug_report_expected_behavior'], report.expected);
    expect(uri.queryParameters['bug_report_desktop'], report.environment);
    final template =
        File('.github/ISSUE_TEMPLATE/bug-report.yaml').readAsStringSync();
    for (final key
        in uri.queryParameters.keys.where((k) => k.startsWith('bug_report_'))) {
      expect(template, contains('id: $key'));
    }
    expect(uri.queryParameters, isNot(contains('labels')));
    expect(report.needsClipboard, isFalse);
  });

  test('environment opt-out removes all metadata from report and link', () {
    const private =
        BugReport(title: 'a', description: 'b', steps: 'c', expected: 'd');
    expect(private.markdown, isNot(contains('Environment')));
    expect(private.prefilledUri.queryParameters['bug_report_desktop'], isEmpty);
    expect(private.prefilledUri.toString(), isNot(contains('6326')));
  });

  test('long Unicode reports use copy fallback without truncation', () {
    final long = BugReport(
        title: 'PDF', description: '书' * 6000, steps: '1', expected: '2');
    expect(long.needsClipboard, isTrue);
    expect(long.markdown, contains('书' * 6000));
    expect(BugReport.newIssueUri.queryParameters.keys, ['template']);
    expect(BugReport.myIssuesUri.queryParameters['q'], 'is:issue author:@me');
  });
}
