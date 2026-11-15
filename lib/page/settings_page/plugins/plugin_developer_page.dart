import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/page/settings_page/plugins/plugin_detail_page.dart';
import 'package:modu_reader/page/settings_page/plugins/plugin_install_preview.dart';
import 'package:modu_reader/service/plugins/plugin_developer_session.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/widgets/plugins/plugin_script_action.dart';

class PluginDeveloperPage extends StatefulWidget {
  const PluginDeveloperPage({super.key, this.session, this.pickPackage});
  final PluginDeveloperSession? session;
  final Future<File?> Function()? pickPackage;

  @override
  State<PluginDeveloperPage> createState() => _PluginDeveloperPageState();
}

class _PluginDeveloperPageState extends State<PluginDeveloperPage> {
  final _sources = <String, File>{};
  bool _busy = false;
  PluginDeveloperSession get _session =>
      widget.session ?? PluginDeveloperSession.instance;
  bool get _available => _session.enabled && Prefs().experimentalPluginsEnabled;
  bool get _working => _busy || _session.busy;
  String t(String zh, String en) => ModuStrings.text(context, zh, en);

  Future<File?> _pick() async {
    if (widget.pickPackage != null) return widget.pickPackage!();
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['moduplugin', 'zip'],
        allowMultiple: false,
        withData: false);
    final path = result?.files.single.path;
    return path == null ? null : File(path);
  }

  Future<void> _import({String? reloadId}) async {
    if (_working || !_available) return;
    setState(() => _busy = true);
    try {
      final file = reloadId == null
          ? await _pick()
          : _sources[reloadId] ?? await _pick();
      if (file == null || !mounted || !_available) return;
      final preview = await _session.preview(file);
      if (reloadId != null && preview.manifest.id != reloadId) {
        throw const PluginInstallError(PluginErrorCode.invalidPackage,
            'Choose the package for this plugin.');
      }
      if (!mounted || !_available) return;
      final confirmed = await PluginInstallPreviewPage.show(context, preview,
          temporary: true);
      if (!confirmed || !mounted || !_available) return;
      if (reloadId == null) {
        await _session.install(file, expectedSha256: preview.sha256);
      } else {
        await _session.reload(file, expectedSha256: preview.sha256);
      }
      _sources[preview.manifest.id] = file;
    } catch (error) {
      if (mounted) await _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String id) async {
    if (_working || !_available) return;
    setState(() => _busy = true);
    try {
      await _session.uninstall(id);
      _sources.remove(id);
    } catch (error) {
      if (mounted) await _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (_working || !_available) return;
    setState(() => _busy = true);
    try {
      await _session.setEnabled(false);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) await _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(String id, ScriptActionContribution action) async {
    if (_working || !_available) return;
    final runtime = _session.runtime;
    if (runtime == null) return;
    final manifest = runtime.host.manifestFor(id);
    final navigator = Navigator.of(context, rootNavigator: true);
    ModalRoute<dynamic>? transientRoute;
    bool current() =>
        mounted &&
        _available &&
        identical(runtime, _session.runtime) &&
        identical(manifest, runtime.host.manifestFor(id));
    void discardStale() {
      final route = transientRoute;
      if (current() || route == null || !route.isActive || !navigator.mounted) {
        return;
      }
      try {
        navigator.removeRoute(route);
      } catch (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => discardStale());
      }
    }

    _session.addListener(discardStale);
    runtime.host.addListener(discardStale);
    try {
      Map<String, String>? input;
      if (action.surface != PluginScriptSurface.library) {
        final route = DialogRoute<Map<String, String>>(
            context: context,
            builder: (_) => _TestInputDialog(
                withContext: action.scope == PluginSelectionScope.context));
        transientRoute = route;
        input = await navigator.push(route);
        transientRoute = null;
        if (input == null || !current()) return;
      }
      if (!mounted || !current()) return;
      setState(() => _busy = true);
      if (action.surface == PluginScriptSurface.dictionary) {
        final result = await runtime.run(
            pluginId: id,
            action: action,
            input: {'selection': input!['selection'] ?? ''});
        if (!mounted || !current()) return;
        final route = DialogRoute<void>(
            context: context,
            builder: (dialog) {
              return AlertDialog(
                title: Text(t('候选词', 'Candidates')),
                content: SingleChildScrollView(
                    child: SelectableText(
                        (result['candidates'] as List).join('\n'))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: Text(t('关闭', 'Close')))
                ],
              );
            });
        transientRoute = route;
        await navigator.push(route);
        transientRoute = null;
      } else {
        await runPluginAction(context,
            pluginId: id,
            action: action,
            selection: input?['selection'] ?? '',
            contextText: input?['context'] ?? '',
            scriptRuntime: runtime);
      }
    } catch (error) {
      if (current()) await _error(error);
    } finally {
      _session.removeListener(discardStale);
      runtime.host.removeListener(discardStale);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _error(Object error) {
    final unsupportedContributions = error is PluginInstallError &&
        error.code == PluginErrorCode.capabilityUnavailable &&
        error.message ==
            'Development mode supports scriptAction and bookAction only; aiSkill and selectionAction are not supported.';
    return showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
              title: Text(t('调试操作失败', 'Debug action failed')),
              content: Text(unsupportedContributions
                  ? t('本机调试仅支持 scriptAction 和 bookAction，请移除 aiSkill、selectionAction 后重新打包。',
                      'Local debugging supports scriptAction and bookAction only. Remove aiSkill and selectionAction, then package it again.')
                  : PluginHost.describeError(error)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: Text(t('关闭', 'Close')))
              ],
            ));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([_session, Prefs()]),
        builder: (context, _) {
          final host = _session.host;
          return Scaffold(
            appBar: AppBar(
                title: Text(t('本机插件调试', 'Local plugin debugging')),
                actions: [
                  IconButton(
                      key: const ValueKey('plugin-developer-close'),
                      tooltip: t('关闭调试并清除', 'Disable debugging and clear'),
                      onPressed: _working || !_available ? null : _close,
                      icon: const Icon(Icons.stop_circle_outlined))
                ]),
            body: !_available || host == null
                ? Center(
                    child:
                        Text(t('开发者调试已关闭', 'Developer debugging is disabled')))
                : ListView(
                    key: const ValueKey('plugin-developer-scroll'),
                    padding: const EdgeInsets.all(16),
                    children: [
                        FilledButton.icon(
                            key: const ValueKey('plugin-developer-import'),
                            onPressed: _working ? null : () => _import(),
                            icon: const Icon(Icons.add_box_outlined),
                            label:
                                Text(t('导入临时插件…', 'Import temporary plugin…'))),
                        if (host.plugins.isEmpty)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Text(t('导入本机的 .moduplugin 或 ZIP 包。',
                                  'Import a local .moduplugin or ZIP package.'))),
                        for (final plugin in host.plugins)
                          _pluginCard(host, plugin),
                        const SizedBox(height: 16),
                        ExpansionTile(
                            key: const ValueKey('plugin-developer-logs'),
                            title: Text(t('调试日志', 'Debug logs')),
                            subtitle: Text(t('仅记录插件、动作和执行状态',
                                'Plugin, action and execution status only')),
                            children: [
                              Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                      key: const ValueKey(
                                          'plugin-developer-clear-logs'),
                                      onPressed: _session.logs.isEmpty
                                          ? null
                                          : _session.clearLogs,
                                      child: Text(t('清空', 'Clear')))),
                              for (final log in _session.logs.reversed)
                                ListTile(
                                    dense: true,
                                    title: Text('${log.id} · ${log.action}'),
                                    subtitle: Text(
                                        '${log.time.toLocal().toIso8601String().substring(11, 19)}'
                                        ' · ${log.stage} · ${log.code} · ${log.elapsedMs}ms')),
                            ]),
                      ]),
          );
        },
      );

  Widget _pluginCard(PluginHost host, PluginRecord plugin) {
    final manifest = host.manifestFor(plugin.id);
    return Card(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListTile(
          leading: const Icon(Icons.extension_outlined),
          title: Text(plugin.name
              .resolve(Localizations.localeOf(context).toLanguageTag())),
          subtitle: Text('${plugin.id} · v${plugin.version}'),
          onTap: _working
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          PluginDetailPage(pluginId: plugin.id, host: host))),
          trailing: const Icon(Icons.chevron_right)),
      for (final action
          in manifest?.contributions.whereType<ScriptActionContribution>() ??
              const <ScriptActionContribution>[])
        ListTile(
            key: ValueKey('plugin-developer-run-${plugin.id}-${action.id}'),
            leading: const Icon(Icons.play_arrow_outlined),
            title: Text(action.name
                .resolve(Localizations.localeOf(context).toLanguageTag())),
            onTap: _working || plugin.status != PluginStatus.enabled
                ? null
                : () => _run(plugin.id, action)),
      for (final action
          in manifest?.contributions.whereType<BookActionContribution>() ??
              const <BookActionContribution>[])
        ListTile(
            title: Text(action.name
                .resolve(Localizations.localeOf(context).toLanguageTag())),
            subtitle:
                Text(t('在书籍长按操作菜单中使用', 'Use from the book actions menu'))),
      Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Wrap(spacing: 8, children: [
            TextButton.icon(
                key: ValueKey('plugin-developer-reload-${plugin.id}'),
                onPressed: _working ? null : () => _import(reloadId: plugin.id),
                icon: const Icon(Icons.refresh),
                label: Text(t('重新加载…', 'Reload…'))),
            TextButton.icon(
                key: ValueKey('plugin-developer-remove-${plugin.id}'),
                onPressed: _working ? null : () => _remove(plugin.id),
                icon: const Icon(Icons.delete_outline),
                label: Text(t('移除', 'Remove'))),
          ])),
    ]));
  }
}

class _TestInputDialog extends StatefulWidget {
  const _TestInputDialog({required this.withContext});
  final bool withContext;
  @override
  State<_TestInputDialog> createState() => _TestInputDialogState();
}

class _TestInputDialogState extends State<_TestInputDialog> {
  final _selection = TextEditingController();
  final _context = TextEditingController();
  @override
  void dispose() {
    _selection.dispose();
    _context.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(ModuStrings.text(context, '测试输入', 'Test input')),
        scrollable: true,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              key: const ValueKey('plugin-developer-selection'),
              controller: _selection,
              maxLength: 8000,
              maxLines: 3,
              decoration: InputDecoration(
                  labelText:
                      ModuStrings.text(context, '划词文字', 'Selected text'))),
          if (widget.withContext)
            TextField(
                key: const ValueKey('plugin-developer-context'),
                controller: _context,
                maxLength: 8000,
                maxLines: 3,
                decoration: InputDecoration(
                    labelText: ModuStrings.text(context, '上下文', 'Context'))),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
          FilledButton(
              key: const ValueKey('plugin-developer-test-confirm'),
              onPressed: () => Navigator.pop(context,
                  {'selection': _selection.text, 'context': _context.text}),
              child: Text(ModuStrings.text(context, '运行', 'Run'))),
        ],
      );
}
