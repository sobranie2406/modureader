import 'dart:io';

import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/page/settings_page/plugins/plugin_detail_page.dart';
import 'package:modu_reader/page/settings_page/plugins/plugin_install_preview.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/widgets/settings/settings_section.dart';
import 'package:modu_reader/widgets/settings/settings_tile.dart';
import 'package:modu_reader/widgets/settings/settings_title.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class PluginSettings extends StatefulWidget {
  const PluginSettings({super.key, this.host, this.pickPackage});

  /// Injectable for tests; defaults to the app-wide singleton.
  final PluginHost? host;
  final Future<File?> Function()? pickPackage;

  @override
  State<PluginSettings> createState() => _PluginSettingsState();
}

class _PluginSettingsState extends State<PluginSettings> {
  bool _busy = false;

  PluginHost get _host => widget.host ?? PluginHost.instance;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _host,
      builder: (context, _) {
        final plugins = _host.plugins;
        final enabled = plugins
            .where((plugin) => plugin.status == PluginStatus.enabled)
            .length;
        return settingsSections(sections: [
          SettingsSection(
            title:
                Text(ModuStrings.text(context, '已安装插件', 'Installed plugins')),
            tiles: [
              SettingsTile.navigation(
                key: const ValueKey('plugin-install'),
                leading: const Icon(Icons.add_box_outlined),
                title:
                    Text(ModuStrings.text(context, '安装插件…', 'Install plugin…')),
                description: Text(ModuStrings.text(context, "安装项目提供的提示词包和划词动作。",
                    "Install prompt packs and selection actions provided by the project.")),
                enabled: !_busy,
                onPressed: _busy ? null : (_) => _install(),
              ),
              if (plugins.isEmpty)
                CustomSettingsTile(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      ModuStrings.text(
                          context, "还没有安装插件。", "No plugins installed yet."),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              for (final plugin in plugins)
                CustomSettingsTile(
                  child: _PluginTile(
                    plugin: plugin,
                    onOpen: () => _openDetail(plugin.id),
                    onInstall: () => _install(replaceId: plugin.id),
                    onUninstall: () => _confirmUninstall(plugin),
                    onToggle: (value) => _toggle(plugin, value),
                  ),
                ),
            ],
          ),
          if (plugins.isNotEmpty)
            SettingsSection(
              title: Text(ModuStrings.text(context, '插件摘要', 'Plugin summary')),
              tiles: [
                CustomSettingsTile(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      ModuStrings.text(
                          context,
                          '已安装 $enabled 个，共 ${plugins.length} 个。停用插件会移除它添加的提示词和划词动作；卸载会删除插件文件。',
                          '$enabled of ${plugins.length} enabled. Disabling removes the prompts and toolbar actions it added; uninstalling deletes its files.'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
          SettingsSection(
            title: Text(ModuStrings.text(context, '关于插件包', 'About packages')),
            tiles: [
              CustomSettingsTile(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    ModuStrings.text(context, "选择下载的 .moduplugin 或 ZIP 插件包。",
                        "Choose a downloaded .moduplugin or ZIP package."),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ),
        ]);
      },
    );
  }

  Future<void> _toggle(PluginRecord plugin, bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (value) {
        await _host.enable(plugin.id);
      } else {
        await _host.disable(plugin.id);
      }
    } catch (error) {
      if (mounted) await _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _install({String? replaceId}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await (widget.pickPackage?.call() ?? _pickPackage());
      if (file == null) return;
      // Inspect first: trust, compatibility and version conflicts surface here,
      // and the user sees permissions/README before anything is written.
      final preview =
          await _host.preview(file, allowSameVersion: replaceId != null);
      if (!mounted) return;
      final confirmed = await PluginInstallPreviewPage.show(context, preview);
      if (!confirmed || !mounted) return;
      final result = await _host.install(file,
          allowSameVersion: replaceId != null, expectedSha256: preview.sha256);
      if (!mounted) return;
      final warnings = result.warnings;
      if (warnings.isNotEmpty) {
        await _showWarnings(warnings);
      }
    } catch (error) {
      if (mounted) await _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<File?> _pickPackage() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['moduplugin', 'zip'],
      allowMultiple: false,
      withData: false,
    );
    final path = picked?.files.single.path;
    return path == null ? null : File(path);
  }

  Future<void> _openDetail(String id) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PluginDetailPage(pluginId: id, host: _host),
    ));
  }

  Future<void> _confirmUninstall(PluginRecord plugin) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(ModuStrings.text(context, '卸载插件？', 'Uninstall plugin?')),
        content: Text(ModuStrings.text(context, "卸载插件及其添加的内容？已编辑的条目会保留。",
            "Uninstall the plugin and its additions? Edited entries will be kept.")),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(ModuStrings.text(context, '取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(ModuStrings.text(context, '卸载', 'Uninstall')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _host.uninstall(plugin.id);
    } catch (error) {
      if (mounted) await _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showWarnings(List<String> warnings) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(ModuStrings.text(
            context, '插件已安装，部分内容被跳过', 'Plugin installed with skipped items')),
        content: Text(warnings.join('\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(ModuStrings.text(context, '知道了', 'OK')),
          ),
        ],
      ),
    );
  }

  Future<void> _showError(Object error) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title:
            Text(ModuStrings.text(context, '插件操作失败', 'Plugin action failed')),
        content: Text(pluginErrorText(context, error)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(ModuStrings.text(context, '知道了', 'OK')),
          ),
        ],
      ),
    );
  }
}

class _PluginTile extends StatelessWidget {
  const _PluginTile({
    required this.plugin,
    required this.onOpen,
    required this.onInstall,
    required this.onUninstall,
    required this.onToggle,
  });

  final PluginRecord plugin;
  final VoidCallback onOpen;
  final VoidCallback onInstall;
  final VoidCallback onUninstall;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final name = plugin.name.resolve(locale);
    final status = pluginStatusLabel(context, plugin.status);
    final usable = plugin.isUsable;
    return ListTile(
      key: ValueKey('plugin-tile-${plugin.id}'),
      leading: Icon(
          usable ? Icons.extension_outlined : Icons.extension_off_outlined),
      title: Text(name.isEmpty ? plugin.id : name,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          'v${plugin.version} · $status'
          '${plugin.author == null ? '' : ' · ${plugin.author}'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: plugin.status == PluginStatus.enabled,
            onChanged: usable ? onToggle : null,
          ),
          PopupMenuButton<String>(
            key: ValueKey('plugin-menu-${plugin.id}'),
            onSelected: (value) {
              switch (value) {
                case 'detail':
                  onOpen();
                  break;
                case 'reinstall':
                  onInstall();
                  break;
                case 'uninstall':
                  onUninstall();
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'detail',
                child: Text(ModuStrings.text(context, '详情', 'Details')),
              ),
              PopupMenuItem(
                value: 'reinstall',
                child: Text(ModuStrings.text(context, '重新安装…', 'Reinstall…')),
              ),
              PopupMenuItem(
                value: 'uninstall',
                child: Text(ModuStrings.text(context, '卸载', 'Uninstall')),
              ),
            ],
          ),
        ],
      ),
      onTap: onOpen,
    );
  }
}

String pluginStatusLabel(BuildContext context, PluginStatus status) {
  switch (status) {
    case PluginStatus.enabled:
      return ModuStrings.text(context, '已启用', 'Enabled');
    case PluginStatus.disabled:
      return ModuStrings.text(context, '已停用', 'Disabled');
    case PluginStatus.broken:
      return ModuStrings.text(context, '已损坏', 'Broken');
    case PluginStatus.missing:
      return ModuStrings.text(context, '缺失', 'Missing');
  }
}

/// Localised, actionable text for install failures. Unknown errors fall back
/// to the underlying message so diagnostics stay visible.
String pluginErrorText(BuildContext context, Object error) {
  if (error is! PluginInstallError) return error.toString();
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  final reason = switch (error.code) {
    PluginErrorCode.untrustedPackage =>
      zh ? '插件不在 Modu 项目审核清单中，或文件已被修改。请使用项目提供的已审核版本，不支持第三方包。' : error.message,
    PluginErrorCode.invalidPackage => zh ? '文件不是有效的插件包（zip）。' : error.message,
    PluginErrorCode.packageTooLarge => zh ? '插件包超过大小限制。' : error.message,
    PluginErrorCode.tooManyEntries => zh ? '插件包内文件过多。' : error.message,
    PluginErrorCode.suspiciousCompressionRatio =>
      zh ? '插件包压缩比异常，已拒绝以防压缩炸弹。' : error.message,
    PluginErrorCode.invalidPath ||
    PluginErrorCode.duplicateEntry =>
      zh ? '插件包包含不安全的文件路径。' : error.message,
    PluginErrorCode.missingManifest =>
      zh ? '插件包缺少 manifest.json。' : error.message,
    PluginErrorCode.manifestTooLarge =>
      zh ? 'manifest.json 过大。' : error.message,
    PluginErrorCode.invalidManifest =>
      zh ? 'manifest.json 格式不正确。' : error.message,
    PluginErrorCode.unsupportedSchema =>
      zh ? '插件规范版本不受支持，请更新应用。' : error.message,
    PluginErrorCode.invalidPluginId =>
      zh ? '插件 id 不合法（需为小写字母、数字、点、下划线或连字符）。' : error.message,
    PluginErrorCode.invalidVersion => zh ? '版本号不合法（需为 x.y.z）。' : error.message,
    PluginErrorCode.missingLicense ||
    PluginErrorCode.invalidLicense =>
      zh ? '插件必须声明有效的 SPDX 许可证。' : error.message,
    PluginErrorCode.unsupportedHostApi ||
    PluginErrorCode.appTooOld =>
      zh ? '该插件需要更高版本的应用。' : error.message,
    PluginErrorCode.unknownCapability =>
      zh ? '插件声明了未知权限，可能已损坏。' : error.message,
    PluginErrorCode.capabilityUnavailable =>
      zh ? '该插件需要当前版本尚未开放的权限。' : error.message,
    PluginErrorCode.tooManyContributions => zh ? '插件声明的贡献项过多。' : error.message,
    PluginErrorCode.invalidContribution ||
    PluginErrorCode.duplicateContribution =>
      zh ? '插件包含无效或重复的贡献项。' : error.message,
    PluginErrorCode.promptTooLong => zh ? '提示词超过 8000 字符。' : error.message,
    PluginErrorCode.nameTooLong => zh ? '名称超过长度限制。' : error.message,
    PluginErrorCode.invalidSetting ||
    PluginErrorCode.duplicateSetting ||
    PluginErrorCode.unsupportedSettingType =>
      zh ? '插件设置声明不合法。' : error.message,
    PluginErrorCode.alreadyInstalled => zh ? '该版本已安装。' : error.message,
    PluginErrorCode.downgradeNotAllowed =>
      zh ? '不能降级安装，请先卸载当前版本。' : error.message,
    PluginErrorCode.notInstalled => zh ? '插件未安装。' : error.message,
    PluginErrorCode.pluginUnavailable =>
      zh ? '插件文件缺失或损坏，请重新安装后再启用。' : error.message,
    PluginErrorCode.promptConflict =>
      zh ? '提示词 id 冲突，请卸载后重新安装。' : error.message,
    PluginErrorCode.toolbarConflict =>
      zh ? '划词工具栏动作 id 冲突，请先删除同名动作。' : error.message,
    PluginErrorCode.noToolbarSlots =>
      zh ? '划词工具栏自定义动作已达 24 个上限，请先删除一个再安装。' : error.message,
    PluginErrorCode.internal => error.message,
  };
  return reason;
}
