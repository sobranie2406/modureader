/// Only user-entered text and explicitly selected, previewed diagnostics.
/// This model never reads preferences, credentials, logs or library data.
class BugReport {
  const BugReport({
    required this.title,
    required this.description,
    required this.steps,
    required this.expected,
    this.environment,
    this.crashLog,
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
  final String? crashLog;

  String get markdown => '''# [Bug]: ${title.trim()}

## Describe the bug / 描述问题
${description.trim()}

## To reproduce / 重现步骤
${steps.trim()}

## Expected behavior / 预期行为
${expected.trim()}
${environment == null ? '' : '\n## Environment / 运行环境\n$environment\n'}${crashLog == null ? '' : '\n## Crash diagnostics / 崩溃诊断日志\n$crashLog\n'}''';

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
  // Diagnostic text must not be embedded in URLs/browser history, even if short.
  bool get needsClipboard =>
      crashLog != null || prefilledUri.toString().length > 1800;
}
