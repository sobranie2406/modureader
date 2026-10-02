enum FeedbackType { bug, feature }

/// Only user-entered text and explicitly selected, previewed diagnostics.
/// Preparing a report never submits it or reads preferences/library data.
abstract class FeedbackReport {
  const FeedbackReport();

  static const repository = 'https://github.com/sobranie2406/modureader';
  static final issuesUri = Uri.parse('$repository/issues');
  static final myIssuesUri = issuesUri.replace(
    queryParameters: {'q': 'is:issue author:@me'},
  );

  static Uri searchUri(String title) => title.trim().isEmpty
      ? issuesUri
      : issuesUri.replace(queryParameters: {'q': 'is:issue ${title.trim()}'});

  FeedbackType get type;
  String get markdown;
  Uri get templateUri;
  Uri get prefilledUri;
  String? get crashLog => null;

  // Be conservative across desktop/mobile URL handlers. Never truncate text.
  // Diagnostic text must not enter URLs/browser history, even when short.
  bool get needsClipboard =>
      crashLog != null || prefilledUri.toString().length > 1800;
}

class BugReport extends FeedbackReport {
  const BugReport({
    required this.title,
    required this.description,
    required this.steps,
    required this.expected,
    this.actual = '',
    this.additional = '',
    this.environment,
    this.crashLog,
  });

  static const repository = FeedbackReport.repository;
  static final issuesUri = FeedbackReport.issuesUri;
  static final myIssuesUri = FeedbackReport.myIssuesUri;
  static final newIssueUri = Uri.parse('$repository/issues/new').replace(
    queryParameters: {'template': 'bug-report.yaml'},
  );

  final String title;
  final String description;
  final String steps;
  final String expected;
  final String actual;
  final String additional;
  final String? environment;
  @override
  final String? crashLog;

  @override
  FeedbackType get type => FeedbackType.bug;

  @override
  Uri get templateUri => newIssueUri;

  /// Keep compatibility with the existing published YAML field IDs.
  String get issueDescription => '${description.trim()}'
      '${actual.trim().isEmpty ? '' : '\n\n### Actual behavior / 实际结果\n${actual.trim()}'}';

  @override
  String get markdown => '''# [Bug]: ${title.trim()}

## Describe the bug / 描述问题
${description.trim()}

## To reproduce / 重现步骤
${steps.trim()}

${actual.trim().isEmpty ? '' : '## Actual behavior / 实际结果\n${actual.trim()}\n\n'}## Expected behavior / 预期行为
${expected.trim()}
${environment == null ? '' : '\n## Environment / 运行环境\n$environment\n'}${additional.trim().isEmpty ? '' : '\n## Additional context / 补充信息\n${additional.trim()}\n'}${crashLog == null ? '' : '\n## Crash diagnostics / 崩溃诊断日志\n$crashLog\n'}''';

  /// Match the field IDs in .github/ISSUE_TEMPLATE/bug-report.yaml. A `body`
  /// query alone does not prefill a YAML issue form's custom fields.
  @override
  Uri get prefilledUri => newIssueUri.replace(queryParameters: {
        ...newIssueUri.queryParameters,
        'title': '[Bug]: ${title.trim()}',
        'bug_report_description': issueDescription,
        'bug_report_reproduce': steps.trim(),
        'bug_report_expected_behavior': expected.trim(),
        'bug_report_desktop': environment ?? '',
        if (additional.trim().isNotEmpty)
          'bug_report_additional_context': additional.trim(),
      });
}

class FeatureRequest extends FeedbackReport {
  const FeatureRequest({
    required this.title,
    required this.problem,
    required this.solution,
    this.alternatives = '',
    this.environment,
  });

  static final newIssueUri =
      Uri.parse('${FeedbackReport.repository}/issues/new')
          .replace(queryParameters: {'template': 'feature_request.md'});

  final String title;
  final String problem;
  final String solution;
  final String alternatives;
  final String? environment;

  @override
  FeedbackType get type => FeedbackType.feature;

  @override
  Uri get templateUri => newIssueUri;

  @override
  String get markdown => '''# [Feature]: ${title.trim()}

## Problem or use case / 使用场景与需求
${problem.trim()}

## Proposed solution / 希望实现的功能
${solution.trim()}
${alternatives.trim().isEmpty ? '' : '\n## Alternatives and additional context / 替代方案与补充信息\n${alternatives.trim()}\n'}${environment == null ? '' : '\n## Environment / 运行环境\n$environment\n'}''';

  // Markdown templates use `body`; YAML forms use their explicit field IDs.
  // Labels come from the repository template, not privileged URL parameters.
  @override
  Uri get prefilledUri => newIssueUri.replace(queryParameters: {
        ...newIssueUri.queryParameters,
        'title': '[Feature]: ${title.trim()}',
        'body': markdown,
      });
}
