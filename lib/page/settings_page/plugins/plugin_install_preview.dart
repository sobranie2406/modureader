import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/plugin_manifest.dart';
import 'package:anx_reader/page/settings_page/plugins/plugin_labels.dart';
import 'package:anx_reader/service/plugins/plugin_host.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';

/// Confirmation shown before a package writes anything.
///
/// The package is already validated (trust, schema, compatibility); this page
/// answers "what will this add and what does it get access to" so the user can
/// cancel without leaving state behind.
class PluginInstallPreviewPage extends StatelessWidget {
  const PluginInstallPreviewPage({super.key, required this.preview});

  final PluginPreview preview;

  static Future<bool> show(BuildContext context, PluginPreview preview) async {
    final confirmed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => PluginInstallPreviewPage(preview: preview),
    ));
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final manifest = preview.manifest;
    final description = manifest.description.resolve(locale).trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(ModuStrings.text(context, '安装插件', 'Install plugin')),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SettingsSection(
            title: Text(ModuStrings.text(context, '基本信息', 'Package')),
            tiles: [
              CustomSettingsTile(
                child: ListTile(
                  title: Text(manifest.name.resolve(locale)),
                  subtitle: description.isEmpty ? null : Text(description),
                ),
              ),
              _valueTile(context, 'ID', manifest.id),
              _valueTile(context, ModuStrings.text(context, '版本', 'Version'),
                  manifest.version),
              _valueTile(context, ModuStrings.text(context, '许可证', 'License'),
                  manifest.license),
              if (manifest.author != null)
                _valueTile(context, ModuStrings.text(context, '作者', 'Author'),
                    manifest.author!.name),
              _valueTile(context, ModuStrings.text(context, '包大小', 'Package size'),
                  _formatBytes(preview.compressedBytes)),
              _valueTile(context, 'SHA-256', preview.sha256),
              if (preview.installedVersion != null)
                _valueTile(context, ModuStrings.text(context, '将替换', 'Replaces'),
                    'v${preview.installedVersion}'),
            ],
          ),
          SettingsSection(
            title: Text(ModuStrings.text(context, '权限', 'Permissions')),
            tiles: [
              if (manifest.capabilities.isEmpty)
                _notice(
                    context,
                    ModuStrings.text(
                        context, '没有声明额外权限。', 'No extra permissions declared.')),
              for (final capability in manifest.capabilities)
                _valueTile(
                    context, pluginCapabilityLabel(context, capability), capability),
            ],
          ),
          SettingsSection(
            title:
                Text(ModuStrings.text(context, '将添加的内容', 'What will be added')),
            tiles: _contributionTiles(context, manifest),
          ),
          if (preview.warnings.isNotEmpty)
            SettingsSection(
              title: Text(ModuStrings.text(context, '将被跳过', 'Skipped items')),
              tiles: [
                for (final warning in preview.warnings) _notice(context, warning),
              ],
            ),
          if (preview.readme != null)
            SettingsSection(
              title: const Text('README'),
              tiles: [
                CustomSettingsTile(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      preview.readme!,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('plugin-install-cancel'),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(ModuStrings.text(context, '取消', 'Cancel')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('plugin-install-confirm'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(ModuStrings.text(context, '安装', 'Install')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<AbstractSettingsTile> _contributionTiles(
      BuildContext context, PluginManifest manifest) {
    final prompts =
        manifest.contributions.whereType<AiSkillContribution>().length;
    final actions =
        manifest.contributions.whereType<SelectionActionContribution>().length;
    final skipped =
        manifest.contributions.whereType<UnknownContribution>().length;
    return [
      if (prompts > 0)
        _valueTile(context, ModuStrings.text(context, 'AI 提示词', 'AI prompts'),
            '$prompts'),
      if (actions > 0)
        _valueTile(
            context,
            ModuStrings.text(context, '划词工具栏动作', 'Selection toolbar actions'),
            '$actions'),
      if (manifest.settings.isNotEmpty)
        _valueTile(
            context,
            ModuStrings.text(context, '插件设置', 'Plugin settings'),
            '${manifest.settings.length}'),
      if (skipped > 0)
        _notice(
            context,
            ModuStrings.text(context, '未知的贡献类型会被跳过，不影响其余内容。',
                'Unknown contribution kinds are skipped; the rest still installs.')),
      if (prompts == 0 && actions == 0 && skipped == 0)
        _notice(context,
            ModuStrings.text(context, '这个包不添加任何内容。', 'This package adds nothing.')),
    ];
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
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

AbstractSettingsTile _notice(BuildContext context, String text) {
  return CustomSettingsTile(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    ),
  );
}
