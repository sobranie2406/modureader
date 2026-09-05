/// Only explicitly entered text and the displayed, optional environment summary
/// are included. Never read preferences, credentials, logs or library data here.
class BugReport {
  const BugReport({
    required this.title,
    required this.description,
    required this.steps,
    required this.expected,
    this.environment,
  });

  static const repository = 'https://github.com/sobranie2406/modureader';
  static final issuesUri = Uri.parse('$repository/issues');
  static final myIssuesUri = issuesUri.replace(
    queryParameters: {'q': 'is:issue author:@me'},
  );
  static final newIssueUri = Uri.parse('$repository/issues/new').replace(
    queryParameters: {'template': 'bug-report.yaml'},
  );

  final String title;
  final String description;
  final String steps;
  final String expected;
  final String? environment;

  String get markdown => '''# [Bug]: ${title.trim()}

## Describe the bug / 描述问题
${description.trim()}

## To reproduce / 重现步骤
${steps.trim()}

## Expected behavior / 预期行为
${expected.trim()}
${environment == null ? '' : '\n## Environment / 运行环境\n$environment\n'}''';

  /// Match the field IDs in .github/ISSUE_TEMPLATE/bug-report.yaml. A `body`
  /// query alone does not prefill a YAML issue form's custom fields.
  Uri get prefilledUri => newIssueUri.replace(queryParameters: {
        ...newIssueUri.queryParameters,
        'title': '[Bug]: ${title.trim()}',
        'bug_report_description': description.trim(),
        'bug_report_reproduce': steps.trim(),
        'bug_report_expected_behavior': expected.trim(),
        'bug_report_desktop': environment ?? '',
      });

  // Be conservative across desktop browsers and mobile URL handlers. Never
  // truncate a report to fit: offer explicit copy + open for longer reports.
  bool get needsClipboard => prefilledUri.toString().length > 1800;
}
