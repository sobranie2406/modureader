import 'package:modu_reader/widgets/settings/setting_help_title.dart';
import 'dart:convert';

import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/utils/save_file_to_download.dart';
import 'package:modu_reader/service/feedback/bug_report.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/service/feedback/crash_diagnostics.dart';
import 'package:modu_reader/service/feedback/runtime_diagnostics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:modu_reader/widgets/settings/settings_section.dart';
import 'package:flutter/services.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:url_launcher/url_launcher.dart';

class BugReportSettings extends StatefulWidget {
  const BugReportSettings(
      {super.key,
      this.openUrl,
      this.loadVersion,
      this.loadCrashLog,
      this.loadRuntimeLog,
      this.exportRuntimeLog,
      this.loadEnvironment});

  /// Injectable boundaries keep tests offline and never create real issues.
  final Future<bool> Function(Uri)? openUrl;
  final Future<String> Function()? loadVersion;
  final Future<String> Function()? loadCrashLog;
  final String Function()? loadRuntimeLog;
  final Future<String?> Function(String)? exportRuntimeLog;
  final Future<String> Function()? loadEnvironment;

  @override
  State<BugReportSettings> createState() => _BugReportSettingsState();
}

class _BugReportSettingsState extends State<BugReportSettings> {
  final _forms = {
    for (final type in FeedbackType.values) type: GlobalKey<FormState>()
  };
  final _drafts = {
    FeedbackType.bug: _FeedbackDraft(includeEnvironment: true),
    FeedbackType.feature: _FeedbackDraft(includeEnvironment: false),
  };
  FeedbackType _type = FeedbackType.bug;
  _FeedbackDraft get _draft => _drafts[_type]!;
  GlobalKey<FormState> get _form => _forms[_type]!;
  TextEditingController get _title => _draft.title;
  TextEditingController get _description => _draft.description;
  TextEditingController get _steps => _draft.steps;
  TextEditingController get _actual => _draft.actual;
  TextEditingController get _expected => _draft.expected;
  TextEditingController get _additional => _draft.additional;
  String _version = '…';
  String? _status;
  bool _busy = false;
  bool _includeCrashLog = false;
  bool _loadingCrashLog = false;
  String? _crashLog;
  bool _includeRuntimeLog = true;
  String? _runtimeLog;
  bool _exportingLog = false;
  String _deviceEnvironment = '';
  int _logRequest = 0;

  String _tr(String zh, String en) => ModuStrings.text(context, zh, en);

  void _selectType(FeedbackType type) {
    if (_busy || type == _type) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _type = type;
      _status = null;
      // Invalidate outstanding reads when leaving Bug reports.
      ++_logRequest;
      _includeCrashLog = false;
      _loadingCrashLog = false;
      _crashLog = null;
      _includeRuntimeLog = type == FeedbackType.bug;
      _runtimeLog = type == FeedbackType.bug ? _readRuntimeLog() : null;
    });
    if (type == FeedbackType.bug) _toggleCrashLog(true);
  }

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadDeviceEnvironment();
    _runtimeLog = _readRuntimeLog();
    _toggleCrashLog(true);
  }

  String _readRuntimeLog() =>
      widget.loadRuntimeLog?.call() ?? RuntimeDiagnostics.preview();

  Future<void> _loadDeviceEnvironment() async {
    String info;
    try {
      info = await (widget.loadEnvironment?.call() ??
          CrashDiagnostics.loadEnvironment());
    } catch (_) {
      info = 'Device environment unavailable / 设备环境读取失败';
    }
    if (mounted) setState(() => _deviceEnvironment = info);
  }

  Future<void> _toggleCrashLog(bool enabled) async {
    final request = ++_logRequest;
    setState(() {
      _includeCrashLog = enabled;
      _loadingCrashLog = enabled;
      _crashLog = null;
    });
    if (!enabled) return;
    try {
      final log =
          await (widget.loadCrashLog?.call() ?? CrashDiagnostics.load());
      if (!mounted || request != _logRequest) return;
      setState(() {
        _crashLog = log;
        _loadingCrashLog = false;
      });
    } catch (_) {
      if (!mounted || request != _logRequest) return;
      setState(() {
        _includeCrashLog = false;
        _loadingCrashLog = false;
        _status = _tr('崩溃日志读取失败，可重新勾选重试；仍可提交普通报告。',
            'Could not load crash diagnostics. Select again to retry, or submit without logs.');
      });
    }
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
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    super.dispose();
  }

  String get _environment =>
      'Modu: $_version\nPlatform: ${kIsWeb ? 'web' : defaultTargetPlatform.name}'
      '\nLocale: ${Localizations.localeOf(context).toLanguageTag()}'
      '${_deviceEnvironment.isEmpty ? '' : '\n$_deviceEnvironment'}';

  FeedbackReport get _report => _type == FeedbackType.feature
      ? FeatureRequest(
          title: _title.text,
          problem: _description.text,
          solution: _expected.text,
          alternatives: _additional.text,
          environment: _draft.includeEnvironment ? _environment : null,
        )
      : BugReport(
          title: _title.text,
          description: _description.text,
          steps: _steps.text,
          expected: _expected.text,
          actual: _actual.text,
          additional: _additional.text,
          environment: _draft.includeEnvironment ? _environment : null,
          crashLog: _includeCrashLog ? _crashLog : null,
          runtimeLog: _includeRuntimeLog ? _runtimeLog : null,
        );

  Future<void> _copy(String value) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (mounted) {
        setState(() => _status = _tr('报告已复制。', 'Report copied.'));
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
    if (_loadingCrashLog || _exportingLog) return;
    if (!_form.currentState!.validate()) return;
    setState(() {
      _status = null;
      if (_includeRuntimeLog && _type == FeedbackType.bug) {
        _runtimeLog = _readRuntimeLog();
      }
    });
    final report = _report;
    final proceed = await showDialog<bool>(
      animationStyle: AppMotion.style,
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, updateDialog) => AlertDialog(
                title: Text(report.type == FeedbackType.bug
                    ? _tr('预览 Bug 报告', 'Preview bug report')
                    : _tr('预览功能建议', 'Preview feature request')),
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
                        if (report.runtimeLog != null) ...[
                          if (report.runtimeLogNeedsAttachment) ...[
                            const SizedBox(height: 12),
                            Text(_tr("请导出日志 TXT，并在 GitHub 附加文件。",
                                "Export the log as TXT and attach it on GitHub.")),
                            ExpansionTile(
                              title: Text(
                                  _tr('预览完整运行日志', 'Preview full runtime log')),
                              children: [SelectableText(report.runtimeLog!)],
                            ),
                          ],
                          OutlinedButton.icon(
                            key: const ValueKey('export-feedback-log'),
                            onPressed: _exportingLog
                                ? null
                                : () async {
                                    updateDialog(() => _exportingLog = true);
                                    await _exportLog(report.runtimeLog!);
                                    if (dialogContext.mounted) {
                                      updateDialog(() => _exportingLog = false);
                                    } else {
                                      _exportingLog = false;
                                    }
                                  },
                            icon: const Icon(Icons.file_download_outlined),
                            label: Text(_tr('导出脱敏运行日志 TXT',
                                'Export sanitized runtime log TXT')),
                          ),
                          if (_status != null)
                            Text(_status!,
                                key: const ValueKey(
                                    'feedback-log-export-status')),
                        ],
                        const SizedBox(height: 16),
                        Text(_tr("可在 GitHub 添加截图。",
                            "You can add screenshots on GitHub.")),
                        if (report.needsClipboard) ...[
                          const SizedBox(height: 16),
                          Text(_tr("报告将复制到剪贴板，请在 GitHub 粘贴后提交。",
                              "Paste the copied report on GitHub to submit it.")),
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
                    onPressed: _exportingLog
                        ? null
                        : () => Navigator.pop(dialogContext, true),
                    child: Text(report.needsClipboard
                        ? _tr('复制并前往 GitHub', 'Copy and open GitHub')
                        : _tr('前往 GitHub 提交', 'Continue on GitHub')),
                  ),
                ],
              )),
    );
    if (proceed != true || !mounted) return;
    await _open(
      report.needsClipboard ? report.templateUri : report.prefilledUri,
      copyFirst: report.needsClipboard ? report.markdown : null,
    );
  }

  Future<void> _exportLog(String snapshot) async {
    try {
      final path = widget.exportRuntimeLog != null
          ? await widget.exportRuntimeLog!(snapshot)
          : await saveFileToDownload(
              bytes: Uint8List.fromList(utf8.encode(snapshot)),
              fileName:
                  'Modu-Diagnostics-${DateTime.now().millisecondsSinceEpoch}.txt',
              mimeType: 'text/plain');
      if (!mounted) return;
      setState(() => _status = path == null || path.isEmpty
          ? _tr('已取消导出。', 'Export cancelled.')
          : _tr("日志已导出，请在 GitHub 附加 TXT 文件。",
              "Log exported. Attach the TXT file on GitHub."));
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _tr('日志导出失败，可重试；预览内容仍保留。',
          'Log export failed. Retry; the preview is retained.'));
    }
  }

  Widget _field(TextEditingController controller, String label,
      {int lines = 1,
      int maxLength = 6000,
      bool required = true,
      String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TextFormField(
        key: ValueKey(controller),
        controller: controller,
        enabled: !_busy,
        minLines: lines,
        maxLines: lines + 3,
        maxLength: maxLength,
        decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder()),
        validator: (value) =>
            required && (value == null || value.trim().isEmpty)
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
        padding: const EdgeInsets.only(bottom: 20),
        child: SettingsSection.content(
          title: Text(_tr('反馈内容', 'Feedback details')),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingHelp(
                    title: Text(
                        ModuStrings.text(context, "提交反馈", "Submit feedback")),
                    description: Text(_tr("预览报告后，前往 GitHub 提交。",
                        "Preview your report, then submit it on GitHub."))),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('feedback-type-bug'),
                      avatar: const Icon(Icons.bug_report_outlined, size: 18),
                      label: Text(_tr('提交 Bug', 'Report a bug')),
                      selected: _type == FeedbackType.bug,
                      onSelected:
                          _busy ? null : (_) => _selectType(FeedbackType.bug),
                    ),
                    ChoiceChip(
                      key: const ValueKey('feedback-type-feature'),
                      avatar: const Icon(Icons.lightbulb_outline, size: 18),
                      label: Text(_tr('功能建议', 'Feature request')),
                      selected: _type == FeedbackType.feature,
                      onSelected: _busy
                          ? null
                          : (_) => _selectType(FeedbackType.feature),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_type == FeedbackType.bug
                    ? _tr("功能出错选 Bug，新增或改进选功能建议。",
                        "Choose Bug for errors or Feature request for improvements.")
                    : _tr("描述使用场景和希望实现的效果。",
                        "Describe how you would use the feature.")),
                if (_type == FeedbackType.bug)
                  SettingHelp(
                      title: Text(
                          ModuStrings.text(context, "报告内容", "Report contents")),
                      description: Text(_tr("提交前可预览报告，并选择附带的日志。",
                          "Preview your report and choose which logs to include."))),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _open(FeedbackReport.searchUri(_title.text)),
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
                if (_type == FeedbackType.bug) ...[
                  _field(_description, _tr('问题描述', 'Description'), lines: 3),
                  _field(_steps, _tr('重现步骤', 'Steps to reproduce'),
                      lines: 3,
                      hint: _tr('按顺序列出操作；无法稳定复现时，说明出错前的操作与发生频率。',
                          'List the steps in order. If intermittent, describe what happened before the error and how often it occurs.')),
                  _field(_actual, _tr('实际结果', 'Actual behavior'), lines: 2),
                  _field(_expected, _tr('预期行为', 'Expected behavior'), lines: 2),
                  _field(_additional,
                      _tr('补充信息（可选）', 'Additional context (optional)'),
                      lines: 2, required: false),
                ] else ...[
                  _field(_description, _tr('使用场景与需求', 'Problem or use case'),
                      lines: 3),
                  _field(_expected, _tr('希望实现的功能', 'Proposed solution'),
                      lines: 3),
                  _field(
                      _additional,
                      _tr('替代方案与补充信息（可选）',
                          'Alternatives and additional context (optional)'),
                      lines: 2,
                      required: false),
                ],
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      _tr('附带设备与运行环境', 'Include device and environment info')),
                  subtitle: Text(_environment),
                  value: _draft.includeEnvironment,
                  onChanged: _busy
                      ? null
                      : (value) =>
                          setState(() => _draft.includeEnvironment = value),
                ),
                if (_type == FeedbackType.bug)
                  CheckboxListTile(
                    key: const ValueKey('include-crash-log'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(_tr(
                        '附带崩溃日志（可选）', 'Include crash diagnostics (optional)')),
                    subtitle:
                        Text(_tr("附带崩溃时的诊断信息。", "Include crash diagnostics.")),
                    value: _includeCrashLog,
                    onChanged: _busy
                        ? null
                        : (value) => _toggleCrashLog(value ?? false),
                  ),
                if (_loadingCrashLog)
                  const EinkStaticIndicator(child: LinearProgressIndicator()),
                if (_includeCrashLog && _crashLog != null)
                  ExpansionTile(
                    title: Text(_tr(
                        '查看将附带的崩溃日志', 'Preview attached crash diagnostics')),
                    children: [
                      Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(_crashLog!))
                    ],
                  ),
                if (_type == FeedbackType.bug)
                  CheckboxListTile(
                    key: const ValueKey('include-runtime-log'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(_tr('附带运行日志（可选）',
                        'Include runtime diagnostics (optional)')),
                    subtitle: Text(_tr("附带本次运行的日志，可在预览中导出 TXT。",
                        "Include this session’s log. Export it as TXT from the preview.")),
                    value: _includeRuntimeLog,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                              _includeRuntimeLog = value ?? false;
                              _runtimeLog =
                                  _includeRuntimeLog ? _readRuntimeLog() : null;
                            }),
                  ),
                if (_includeRuntimeLog && _runtimeLog != null)
                  ExpansionTile(
                    title: Text(_tr(
                        '查看将附带的运行日志', 'Preview attached runtime diagnostics')),
                    children: [
                      Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(_runtimeLog!))
                    ],
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy || _loadingCrashLog
                          ? null
                          : () => _copy(_report.markdown),
                      icon: const Icon(Icons.copy_outlined),
                      label: Text(_tr('复制报告', 'Copy report')),
                    ),
                    FilledButton.icon(
                      onPressed: _busy || _loadingCrashLog ? null : _preview,
                      icon: Icon(_type == FeedbackType.bug
                          ? Icons.bug_report_outlined
                          : Icons.lightbulb_outline),
                      label: Text(_tr('预览并提交', 'Preview and submit')),
                    ),
                  ],
                ),
                if (_status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_status!,
                        key: const ValueKey('bug-report-status')),
                  ),
                const SizedBox(height: 20),
                SelectableText(_report.templateUri.toString()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Controllers live for the entire settings session, not individual rebuilds.
/// Switching report type preserves text/selection and does not persist private
/// drafts in global settings or cloud sync.
class _FeedbackDraft {
  _FeedbackDraft({required this.includeEnvironment});

  final title = TextEditingController();
  final description = TextEditingController();
  final steps = TextEditingController();
  final actual = TextEditingController();
  final expected = TextEditingController();
  final additional = TextEditingController();
  bool includeEnvironment;

  void dispose() {
    for (final controller in [
      title,
      description,
      steps,
      actual,
      expected,
      additional
    ]) {
      controller.dispose();
    }
  }
}
