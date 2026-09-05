import 'package:anx_reader/service/feedback/bug_report.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:url_launcher/url_launcher.dart';

class BugReportSettings extends StatefulWidget {
  const BugReportSettings({super.key, this.openUrl, this.loadVersion});

  /// Injectable boundaries keep tests offline and never create real issues.
  final Future<bool> Function(Uri)? openUrl;
  final Future<String> Function()? loadVersion;

  @override
  State<BugReportSettings> createState() => _BugReportSettingsState();
}

class _BugReportSettingsState extends State<BugReportSettings> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _steps = TextEditingController();
  final _expected = TextEditingController();
  String _version = '…';
  String? _status;
  bool _includeEnvironment = true;
  bool _busy = false;

  String _tr(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    String version;
    try {
      version = await (widget.loadVersion?.call() ??
          rootBundle.loadString('pubspec.yaml').then(
                (source) =>
                    Pubspec.parse(source).version?.toString() ?? 'unknown',
              ));
    } catch (_) {
      version = 'unknown';
    }
    if (mounted) setState(() => _version = version);
  }

  @override
  void dispose() {
    for (final controller in [_title, _description, _steps, _expected]) {
      controller.dispose();
    }
    super.dispose();
  }

  String get _environment =>
      'Modu: $_version\nPlatform: ${kIsWeb ? 'web' : defaultTargetPlatform.name}'
      '\nLocale: ${Localizations.localeOf(context).toLanguageTag()}';

  BugReport get _report => BugReport(
        title: _title.text,
        description: _description.text,
        steps: _steps.text,
        expected: _expected.text,
        environment: _includeEnvironment ? _environment : null,
      );

  Future<void> _copy(String value) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (mounted) {
        setState(() => _status = _tr('报告已复制，请注意剪贴板隐私。',
            'Report copied. Please keep your clipboard private.'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _status = _tr('复制失败，请在预览中手动选择并复制。',
            'Copy failed. Select and copy the text in the preview.'));
      }
    }
  }

  Future<void> _open(Uri uri, {String? copyFirst}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      if (copyFirst != null) {
        // Do not navigate away if copying a long report fails.
        await Clipboard.setData(ClipboardData(text: copyFirst));
      }
      if (!mounted) return;
      final opened = await (widget.openUrl?.call(uri) ??
          launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!mounted) return;
      setState(() => _status = opened
          ? (copyFirst == null
              ? _tr('已打开 GitHub；报告尚未提交，请登录并确认提交。',
                  'GitHub opened. Nothing submitted yet; sign in and confirm there.')
              : _tr('完整报告已复制；请在 GitHub 粘贴到问题描述中，补全必填项后提交。',
                  'Full report copied. Paste into the GitHub description, complete required fields and submit.'))
          : _tr('无法打开浏览器。请复制报告，并使用下方网址手动提交。',
              'Could not open the browser. Copy the report and use the URL below.'));
    } catch (_) {
      if (mounted) {
        setState(() => _status = _tr('操作失败，内容仍保留。可预览并手动复制报告和下方网址。',
            'Action failed. Your draft is retained. Preview and manually copy the report and URL below.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview() async {
    if (!_form.currentState!.validate()) return;
    final report = _report;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_tr('预览 Bug 报告', 'Preview bug report')),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_tr('提交后内容将公开。请删除密钥、个人信息及私人书籍内容。',
                    'Submitted reports are public. Remove keys, personal information and private book content.')),
                const SizedBox(height: 16),
                SelectableText(report.markdown),
                if (report.needsClipboard) ...[
                  const SizedBox(height: 16),
                  Text(_tr('报告较长，将复制完整内容到剪贴板，再打开 GitHub。请手动粘贴，不会截断内容。',
                      'This report is long. Copy the full text to your clipboard and open GitHub, then paste it manually. Nothing will be truncated.')),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_tr('返回修改', 'Keep editing')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(report.needsClipboard
                ? _tr('复制并前往 GitHub', 'Copy and open GitHub')
                : _tr('前往 GitHub 提交', 'Continue on GitHub')),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    await _open(
      report.needsClipboard ? BugReport.newIssueUri : report.prefilledUri,
      copyFirst: report.needsClipboard ? report.markdown : null,
    );
  }

  Widget _field(TextEditingController controller, String label,
      {int lines = 1, int maxLength = 6000}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TextFormField(
        controller: controller,
        minLines: lines,
        maxLines: lines + 3,
        maxLength: maxLength,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        validator: (value) => value == null || value.trim().isEmpty
            ? _tr('请填写此项', 'This field is required')
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_tr('提交 Bug', 'Report a bug'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(_tr(
                  '填写问题并预览后，前往默读 GitHub 仓库确认提交（需要 GitHub 账号）。截图可在 GitHub 页面添加。',
                  'Describe and preview your report, then confirm it in the Modu GitHub repository (GitHub account required). Attach screenshots on GitHub.')),
              const SizedBox(height: 12),
              Text(_tr(
                  '不会自动收集日志、AI 配置、API Key 或书籍内容。你填写的内容会传给 GitHub，并可能留在浏览器历史中；提交后公开可见，请勿粘贴敏感信息。',
                  'Logs, AI settings, API keys and book content are not collected automatically. Your text is sent to GitHub and may remain in browser history; submitted reports are public. Do not paste sensitive information.')),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _busy ? null : () => _open(BugReport.issuesUri),
                    icon: const Icon(Icons.search),
                    label: Text(_tr('查看已有问题', 'Existing issues')),
                  ),
                  TextButton.icon(
                    onPressed:
                        _busy ? null : () => _open(BugReport.myIssuesUri),
                    icon: const Icon(Icons.forum_outlined),
                    label: Text(_tr('我的反馈（GitHub）', 'My reports (GitHub)')),
                  ),
                ],
              ),
              _field(_title, _tr('标题', 'Title'), maxLength: 100),
              _field(_description, _tr('问题描述', 'Description'), lines: 3),
              _field(_steps, _tr('重现步骤', 'Steps to reproduce'), lines: 3),
              _field(_expected, _tr('预期行为', 'Expected behavior'), lines: 2),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(_tr('附带基础运行信息', 'Include basic environment info')),
                subtitle: Text(_environment),
                value: _includeEnvironment,
                onChanged: (value) =>
                    setState(() => _includeEnvironment = value),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _copy(_report.markdown),
                    icon: const Icon(Icons.copy_outlined),
                    label: Text(_tr('复制报告', 'Copy report')),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _preview,
                    icon: const Icon(Icons.bug_report_outlined),
                    label: Text(_tr('预览并提交', 'Preview and submit')),
                  ),
                ],
              ),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child:
                      Text(_status!, key: const ValueKey('bug-report-status')),
                ),
              const SizedBox(height: 20),
              SelectableText(BugReport.newIssueUri.toString()),
            ],
          ),
        ),
      ),
    );
  }
}
