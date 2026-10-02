import 'dart:io';

import 'package:anx_reader/service/feedback/bug_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'optional crash diagnostics require clipboard and never enter report URL',
      () {
    const report = BugReport(
        title: 'Crash',
        description: 'Exit',
        steps: '1',
        expected: '2',
        crashLog: 'NATIVE_CRASH');
    expect(report.markdown, contains('NATIVE_CRASH'));
    expect(report.needsClipboard, isTrue);
    expect(report.prefilledUri.toString(), isNot(contains('NATIVE_CRASH')));
  });
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

  test('actual result and extra details use compatible bug form fields', () {
    const detailed = BugReport(
      title: 'Scrolling stops',
      description: 'Cannot scroll',
      steps: '1. Open\n2. Scroll',
      actual: 'The cover remains',
      expected: 'Read the next page',
      additional: 'Only in landscape',
    );
    expect(detailed.type, FeedbackType.bug);
    expect(detailed.templateUri, BugReport.newIssueUri);
    expect(detailed.prefilledUri.queryParameters['bug_report_description'],
        'Cannot scroll\n\n### Actual behavior / 实际结果\nThe cover remains');
    expect(
        detailed.prefilledUri.queryParameters['bug_report_additional_context'],
        'Only in landscape');
    expect(detailed.markdown,
        contains('## Actual behavior / 实际结果\nThe cover remains'));
    expect(detailed.markdown,
        contains('## Additional context / 补充信息\nOnly in landscape'));
  });

  test('feature request prefills the markdown template, not bug YAML fields',
      () {
    const idea = FeatureRequest(
      title: ' New feature & 阅读? #1 ',
      problem: 'A workflow\nwith + and %',
      solution: 'An improvement',
      alternatives: 'A workaround',
    );
    final uri = Uri.parse(idea.prefilledUri.toString());
    expect(idea.type, FeedbackType.feature);
    expect(uri.host, 'github.com');
    expect(uri.path, '/sobranie2406/modureader/issues/new');
    expect(uri.fragment, isEmpty);
    expect(uri.queryParameters['template'], 'feature_request.md');
    expect(uri.queryParameters['title'], '[Feature]: New feature & 阅读? #1');
    expect(uri.queryParameters['body'], idea.markdown);
    expect(uri.queryParameters.keys.any((key) => key.startsWith('bug_report_')),
        isFalse);
    expect(uri.queryParameters, isNot(contains('labels')));
    expect(idea.markdown, contains(idea.problem));
    expect(idea.markdown, contains(idea.solution));
    expect(idea.markdown, contains(idea.alternatives));
    expect(idea.markdown, isNot(contains('To reproduce')));
    expect(idea.markdown, isNot(contains('Crash diagnostics')));
    expect(idea.markdown, isNot(contains('Environment')));
  });

  test('feature context is optional; environment requires explicit inclusion',
      () {
    const simple =
        FeatureRequest(title: 'Idea', problem: 'Need', solution: 'Change');
    expect(simple.markdown, isNot(contains('Alternatives')));
    expect(simple.needsClipboard, isFalse);
    const specific = FeatureRequest(
        title: 'Idea',
        problem: 'Need',
        solution: 'Change',
        environment: 'Modu 1.1.9 / macOS');
    expect(specific.markdown, contains('Modu 1.1.9 / macOS'));
    expect(specific.prefilledUri.queryParameters['body'],
        contains(specific.environment!));
  });

  test(
      'long feature requests keep the full content with the right fallback template',
      () {
    final idea = FeatureRequest(
        title: 'Idea', problem: '需' * 6000, solution: 'New feature');
    expect(idea.needsClipboard, isTrue);
    expect(idea.markdown, contains('需' * 6000));
    expect(idea.templateUri, FeatureRequest.newIssueUri);
    expect(idea.templateUri.queryParameters.keys, ['template']);
  });

  test('each template supplies its own category label without URL permissions',
      () {
    final bug =
        File('.github/ISSUE_TEMPLATE/bug-report.yaml').readAsStringSync();
    final feature =
        File('.github/ISSUE_TEMPLATE/feature_request.md').readAsStringSync();
    expect(bug, contains('labels: ["bug"]'));
    expect(feature, contains('labels: enhancement'));
    expect(feature, contains("title: '[Feature]: '"));
    expect(feature, contains('## Problem or use case'));
    expect(feature, contains('## Proposed solution'));
    expect(bug, contains('removed private information'));
    expect(bug, isNot(contains('troubleshooting guide')));
  });

  test(
      'duplicate search retains punctuation and never leaves the Modu repository',
      () {
    expect(FeedbackReport.searchUri('  '), BugReport.issuesUri);
    final search =
        Uri.parse(FeedbackReport.searchUri(' 阅读 & ? #1 ').toString());
    expect(search.host, 'github.com');
    expect(search.path, '/sobranie2406/modureader/issues');
    expect(search.queryParameters['q'], 'is:issue 阅读 & ? #1');
    expect(search.fragment, isEmpty);
  });
}
