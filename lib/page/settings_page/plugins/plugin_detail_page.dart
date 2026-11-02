import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/plugin_manifest.dart';
import 'package:anx_reader/models/plugin_state.dart';
import 'package:anx_reader/models/selection_toolbar.dart';
import 'package:anx_reader/page/settings_page/plugins/plugin_labels.dart';
import 'package:anx_reader/page/settings_page/plugins/plugins_page.dart';
import 'package:anx_reader/service/config/config_item.dart';
import 'package:anx_reader/service/plugins/handlers/selection_action_handler.dart';
import 'package:anx_reader/service/plugins/plugin_config.dart';
import 'package:anx_reader/service/plugins/plugin_host.dart';
import 'package:anx_reader/widgets/settings/service_config_form.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';

class PluginDetailPage extends StatelessWidget {
  const PluginDetailPage({
    super.key,
    required this.pluginId,
    required this.host,
  });

  final String pluginId;
  final PluginHost host;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([host, Prefs()]),
      builder: (context, _) {
        final record = host.byId(pluginId);
        return Scaffold(
          appBar: AppBar(
            title: Text(record == null
                ? ModuStrings.text(context, '插件详情', 'Plugin details')
                : record.name
                    .resolve(Localizations.localeOf(context).toLanguageTag())),
          ),
          body: record == null
              ? Center(
                  child: Text(ModuStrings.text(context, '插件已被卸载。',
                      'This plugin is no longer installed.')),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    _basicSection(context, record),
                    _permissionSection(context),
                    _contributionSection(context, record),
                    if (host.manifestFor(pluginId)?.settings.isNotEmpty ??
                        false)
                      _settingsSection(context),
                    _readmeSection(context),
                    _diagnosticSection(context, record),
                  ],
                ),
        );
      },
    );
  }

  Widget _basicSection(BuildContext context, PluginRecord record) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return SettingsSection(
      title: Text(ModuStrings.text(context, '基本信息', 'Information')),
      tiles: [
        _valueTile(context, 'ID', record.id),
        _valueTile(context, ModuStrings.text(context, '版本', 'Version'),
            'v${record.version}'),
        _valueTile(context, ModuStrings.text(context, '许可证', 'License'),
            record.license),
        if (record.author != null)
          _valueTile(context, ModuStrings.text(context, '作者', 'Author'),
              record.author!),
        _valueTile(context, ModuStrings.text(context, '安装时间', 'Installed'),
            record.installedAt.toLocal().toString().split('.').first),
        _valueTile(context, 'SHA-256', record.sha256),
        _valueTile(context, ModuStrings.text(context, '包内名称', 'Package name'),
            record.name.resolve(locale)),
        _valueTile(context, ModuStrings.text(context, '状态', 'Status'),
            pluginStatusLabel(context, record.status)),
      ],
    );
  }

  Widget _permissionSection(BuildContext context) {
    final capabilities =
        host.manifestFor(pluginId)?.capabilities ?? const <String>{};
    return SettingsSection(
      title: Text(ModuStrings.text(context, '权限', 'Permissions')),
      tiles: [
        if (capabilities.isEmpty)
          CustomSettingsTile(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(ModuStrings.text(context, '没有声明额外权限，或插件包已不可用。',
                  'No additional permissions declared, or the package is unavailable.')),
            ),
          )
        else
          for (final capability in capabilities)
            _valueTile(
                context, pluginCapabilityLabel(context, capability), capability),
      ],
    );
  }

  Widget _contributionSection(BuildContext context, PluginRecord record) {
    final toolbarItems = Prefs().selectionToolbar.items;
    final usedSlots = toolbarItems
        .where((item) =>
            item.isCustom &&
            !SelectionToolbarConfig.templateItems
                .any((preset) => preset.id == item.id))
        .length;
    final hasActions = record.applied
        .any((entry) => entry.kind == kSelectionActionContributionKind);
    return SettingsSection(
      title: Text(ModuStrings.text(context, '贡献内容', 'Contributions')),
      tiles: [
        if (record.applied.isEmpty)
          CustomSettingsTile(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(ModuStrings.text(
                  context,
                  '当前没有已生效的贡献。启用插件后，它添加的提示词会出现在 AI 提示词列表中。',
                  'No active contributions. Enable the plugin to add its prompts to the AI prompt list.')),
            ),
          )
        else
          for (final applied in record.applied)
            CustomSettingsTile(
              child: ListTile(
                leading: Icon(applied.kind == kSelectionActionContributionKind
                    ? Icons.ads_click
                    : Icons.chat_bubble_outline),
                title: Text(_appliedLabel(applied, toolbarItems)),
                subtitle: Text('${applied.kind} · ${applied.id}'),
              ),
            ),
        if (hasActions)
          CustomSettingsTile(
            child: ListTile(
              leading: const Icon(Icons.space_dashboard_outlined),
              title: Text(ModuStrings.text(
                  context, '划词工具栏名额', 'Selection toolbar slots')),
              subtitle: Text(ModuStrings.text(
                  context,
                  '已用 $usedSlots / ${SelectionActionContributionHandler.maxToolbarSlots}，剩余 ${SelectionActionContributionHandler.maxToolbarSlots - usedSlots} 个',
                  '$usedSlots of ${SelectionActionContributionHandler.maxToolbarSlots} used, ${SelectionActionContributionHandler.maxToolbarSlots - usedSlots} free')),
            ),
          ),
      ],
    );
  }

  String _appliedLabel(
      AppliedContribution applied, List<SelectionToolbarItem> toolbarItems) {
    if (applied.kind == kSelectionActionContributionKind) {
      for (final item in toolbarItems) {
        if (item.id == applied.id) {
          return item.name.trim().isEmpty ? applied.id : item.name.trim();
        }
      }
      return applied.id;
    }
    for (final prompt in Prefs().userPrompts) {
      if (prompt.id == applied.id) return prompt.name;
    }
    return applied.id;
  }

  Widget _settingsSection(BuildContext context) {
    final manifest = host.manifestFor(pluginId);
    if (manifest == null || manifest.settings.isEmpty) {
      return const SizedBox.shrink();
    }
    return SettingsSection(
      title: Text(ModuStrings.text(context, '插件设置', 'Settings')),
      tiles: [
        CustomSettingsTile(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _PluginSettingsForm(
              key: ValueKey('plugin-settings-${manifest.id}'),
              pluginId: manifest.id,
              manifest: manifest,
            ),
          ),
        ),
      ],
    );
  }

  Widget _readmeSection(BuildContext context) {
    final record = host.byId(pluginId);
    if (record == null || !record.isUsable) return const SizedBox.shrink();
    return SettingsSection(
      title: Text(ModuStrings.text(context, '包内 README', 'Package README')),
      tiles: [
        CustomSettingsTile(
          child: FutureBuilder<String?>(
            future: host.readmeFor(pluginId),
            builder: (context, snapshot) {
              final readme = snapshot.data;
              if (readme == null || readme.trim().isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(ModuStrings.text(context,
                      '插件包没有提供 README。', 'This package has no README.')),
                );
              }
              return Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  readme,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _diagnosticSection(BuildContext context, PluginRecord record) {
    final raw = host.manifestTextFor(pluginId);
    return SettingsSection(
      title: Text(ModuStrings.text(context, '诊断', 'Diagnostics')),
      tiles: [
        if (record.lastError != null)
          _valueTile(context, ModuStrings.text(context, '最近错误', 'Last error'),
              record.lastError!),
        if (raw != null)
          CustomSettingsTile(
            child: ExpansionTile(
              title: Text(ModuStrings.text(
                  context, 'manifest.json 原文', 'manifest.json')),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    raw.length > 8192 ? '${raw.substring(0, 8192)}…' : raw,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  AbstractSettingsTile _valueTile(
      BuildContext context, String label, String value) {
    return CustomSettingsTile(
      child: ListTile(
        title: Text(label),
        subtitle: SelectableText(value),
      ),
    );
  }
}

class _PluginSettingsForm extends StatefulWidget {
  const _PluginSettingsForm({
    super.key,
    required this.pluginId,
    required this.manifest,
  });

  final String pluginId;
  final PluginManifest manifest;

  @override
  State<_PluginSettingsForm> createState() => _PluginSettingsFormState();
}

class _PluginSettingsFormState extends State<_PluginSettingsForm> {
  late Map<String, dynamic> _config;
  Timer? _saveTimer;
  bool _dirty = false;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    _config = PluginConfig.sanitize(
        widget.manifest, Prefs().pluginConfig(widget.pluginId));
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_saveTimer != null || _dirty) unawaited(_save());
    super.dispose();
  }

  void _onChanged(Map<String, dynamic> values) {
    _config = values;
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    _saveTimer = null;
    if (!_dirty) return;
    try {
      await Prefs().savePluginConfig(widget.pluginId, _config);
      _dirty = false;
      if (mounted && _saveFailed) setState(() => _saveFailed = false);
    } catch (_) {
      if (mounted) setState(() => _saveFailed = true);
    }
  }

  List<ConfigItem> _items(String locale) {
    return [
      for (final spec in widget.manifest.settings) _configItem(spec, locale),
    ];
  }

  ConfigItem _configItem(PluginSettingSpec spec, String locale) {
    final label = spec.label?.resolve(locale).trim();
    final description = spec.description?.resolve(locale).trim();
    final resolvedLabel = label == null || label.isEmpty ? spec.key : label;
    switch (spec.type) {
      case PluginSettingType.text:
        return ConfigItem(
          key: spec.key,
          label: resolvedLabel,
          description: description,
          type: ConfigItemType.text,
          defaultValue: spec.defaultValue,
          maxLength: PluginConfig.maxTextLength,
        );
      case PluginSettingType.number:
        return ConfigItem(
          key: spec.key,
          label: resolvedLabel,
          description: description,
          type: ConfigItemType.number,
          defaultValue: spec.defaultValue,
        );
      case PluginSettingType.toggle:
        return ConfigItem(
          key: spec.key,
          label: resolvedLabel,
          description: description,
          type: ConfigItemType.toggle,
          defaultValue: spec.defaultValue,
        );
      case PluginSettingType.select:
        return ConfigItem(
          key: spec.key,
          label: resolvedLabel,
          description: description,
          type: ConfigItemType.select,
          defaultValue: spec.defaultValue,
          options: [
            for (final option in spec.options)
              {'value': option, 'label': option},
          ],
        );
      case PluginSettingType.tip:
        return ConfigItem(
          key: spec.key,
          label: resolvedLabel,
          type: ConfigItemType.tip,
          defaultValue: description == null || description.isEmpty
              ? resolvedLabel
              : description,
        );
      case PluginSettingType.secret:
        // Secrets are never edited through the ordinary config form: that map
        // is exported and backed up. Until P3c adds the device-only entry field,
        // the row states what is required instead of pretending to store it.
        return ConfigItem(
          key: spec.key,
          label: resolvedLabel,
          type: ConfigItemType.tip,
          defaultValue: ModuStrings.text(
            context,
            '此插件需要填写密钥。密钥仅保存在本机，不会随设置或备份导出；填写功能将在网络插件正式启用时提供。',
            'This plugin needs a key. Keys stay on this device and are never '
                'exported with settings or backups; entry becomes available when '
                'network plugins are enabled.',
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ServiceConfigForm(
          configItems: _items(locale),
          initialConfig: _config,
          onConfigChanged: _onChanged,
        ),
        if (_saveFailed)
          Text(
            ModuStrings.text(
                context, '插件设置保存失败。', 'Could not save plugin settings.'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
