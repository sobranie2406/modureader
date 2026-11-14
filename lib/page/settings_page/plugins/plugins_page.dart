import 'dart:async';
import 'dart:io';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/page/settings_page/plugins/plugin_detail_page.dart';
import 'package:modu_reader/page/settings_page/plugins/plugin_install_preview.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_catalog.dart';
import 'package:modu_reader/widgets/settings/settings_section.dart';
import 'package:modu_reader/widgets/settings/settings_tile.dart';
import 'package:modu_reader/widgets/settings/settings_title.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class PluginSettings extends StatefulWidget {
  const PluginSettings({super.key, this.host, this.pickPackage, this.catalog});

  /// Injectable for tests; defaults to the app-wide singleton.
  final PluginHost? host;
  final Future<File?> Function()? pickPackage;
  final PluginCatalog? catalog;

  @override
  State<PluginSettings> createState() => _PluginSettingsState();
}

class _PluginSettingsState extends State<PluginSettings> {
  bool _busy = false;
  bool _loadingCatalog = false;
  Object? _catalogError;
  String? _downloadingId;
  List<PluginCatalogEntry> _entries = const [];
  late final PluginCatalog _catalog;
  late String _catalogSource;
  int _catalogRequest = 0;

  PluginHost get _host => widget.host ?? PluginHost.instance;

  @override
  void initState() {
    super.initState();
    _catalogSource = Prefs().pluginCatalogSource;
    _catalog = widget.catalog ?? PluginCatalog(sourceId: _catalogSource);
    unawaited(_catalog.changeSource(_catalogSource).then<void>((_) async {
      if (mounted) await _loadCatalog();
    }));
  }

  @override
  void dispose() {
    unawaited(_catalog.dispose());
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    if (_loadingCatalog) return;
    final request = ++_catalogRequest;
    setState(() {
      _loadingCatalog = true;
      _catalogError = null;
    });
    try {
      final entries = await _catalog.load();
      if (mounted && request == _catalogRequest) {
        setState(() => _entries = entries);
      }
    } catch (error) {
      if (mounted && request == _catalogRequest) {
        setState(() => _catalogError = error);
      }
    } finally {
      if (mounted && request == _catalogRequest) {
        setState(() => _loadingCatalog = false);
      }
    }
  }

  Future<void> _changeCatalogSource(String? value) async {
    if (value == null || value == _catalogSource || _busy) return;
    final request = ++_catalogRequest;
    setState(() {
      _catalogSource = value;
      _entries = const [];
      _catalogError = null;
      _loadingCatalog = false;
    });
    try {
      await _catalog.changeSource(value);
      if (!mounted || request != _catalogRequest) return;
      await Prefs().savePluginCatalogSource(value);
      if (mounted && request == _catalogRequest) await _loadCatalog();
    } catch (error) {
      if (mounted && request == _catalogRequest) {
        setState(() => _catalogError = error);
      }
    }
  }

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
                description: Text(ModuStrings.text(context, "安装项目提供的插件包。",
                    "Install plugin packages provided by the project.")),
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
          _catalogSection(context),
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

  SettingsSection _catalogSection(BuildContext context) => SettingsSection(
        title: Row(children: [
          Expanded(
              child: Text(ModuStrings.text(context, '插件仓库', 'Plugin catalog'))),
          IconButton(
              key: const ValueKey('plugin-catalog-refresh'),
              tooltip: ModuStrings.text(context, '刷新', 'Refresh'),
              onPressed: _busy || _loadingCatalog ? null : _loadCatalog,
              icon: const Icon(Icons.refresh)),
        ]),
        tiles: [
          CustomSettingsTile(
              child: ListTile(
            title: Text(ModuStrings.text(context, '下载来源', 'Download source')),
            trailing: DropdownButton<String>(
              key: const ValueKey('plugin-catalog-source'),
              value: _catalogSource,
              items: const [
                DropdownMenuItem(value: 'github', child: Text('GitHub')),
                DropdownMenuItem(value: 'gitee', child: Text('Gitee')),
              ],
              onChanged: _busy ? null : _changeCatalogSource,
            ),
          )),
          if (_loadingCatalog)
            const CustomSettingsTile(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()))),
          if (_catalogError != null)
            CustomSettingsTile(
                child: ListTile(
                    title: Text(ModuStrings.text(
                        context, '无法读取插件列表', 'Could not load plugins')),
                    trailing: TextButton(
                        key: const ValueKey('plugin-catalog-retry'),
                        onPressed:
                            _loadingCatalog || _busy ? null : _loadCatalog,
                        child:
                            Text(ModuStrings.text(context, '重试', 'Retry'))))),
          if (!_loadingCatalog && _catalogError == null && _entries.isEmpty)
            CustomSettingsTile(
                child: ListTile(
                    title: Text(ModuStrings.text(
                        context, '暂无已上架插件', 'No listed plugins')))),
          for (final entry in _entries)
            CustomSettingsTile(
                child: ListTile(
              key: ValueKey('plugin-catalog-${entry.id}-${entry.version}'),
              leading: const Icon(Icons.extension_outlined),
              title: Text(entry.name
                  .resolve(Localizations.localeOf(context).toLanguageTag())),
              subtitle: Text('v${entry.version}'),
              trailing: _downloadingId == entry.id
                  ? TextButton(
                      onPressed: () => unawaited(_catalog.cancel()),
                      child: Text(ModuStrings.text(context, '取消', 'Cancel')))
                  : TextButton(
                      key: ValueKey('plugin-catalog-install-${entry.id}'),
                      onPressed: _busy ||
                              _loadingCatalog ||
                              entry.requiresAppUpdate(_host.appVersion) ||
                              _host.byId(entry.id)?.version == entry.version &&
                                  _host.byId(entry.id)?.isUsable == true
                          ? null
                          : () => _installFromCatalog(entry),
                      child: Text(entry.requiresAppUpdate(_host.appVersion)
                          ? ModuStrings.text(
                              context, '更新默读后可用', 'Update Modu to use')
                          : _host.byId(entry.id)?.version == entry.version &&
                                  _host.byId(entry.id)?.isUsable == true
                              ? ModuStrings.text(context, '已安装', 'Installed')
                              : ModuStrings.text(
                                  context, '下载安装', 'Download and install'))),
            )),
        ],
      );

  Future<void> _installFromCatalog(PluginCatalogEntry entry) async {
    if (_busy || entry.requiresAppUpdate(_host.appVersion)) return;
    setState(() {
      _busy = true;
      _downloadingId = entry.id;
    });
    PluginCatalogDownload? download;
    try {
      await _host.trust.acceptCatalog(_catalog.signedCatalog);
      download = await _catalog.download(entry);
      if (!mounted) return;
      setState(() => _downloadingId = null);
      final replacing = _host.byId(entry.id) != null;
      final preview =
          await _host.preview(download.file, allowSameVersion: replacing);
      if (preview.manifest.id != entry.id ||
          preview.manifest.version != entry.version ||
          preview.sha256 != entry.sha256) {
        throw const PluginCatalogFailure('checksum');
      }
      if (!mounted) return;
      final confirmed = await PluginInstallPreviewPage.show(context, preview);
      if (!confirmed || !mounted) return;
      final installed = await _host.install(download.file,
          allowSameVersion: replacing, expectedSha256: entry.sha256);
      if (mounted && installed.warnings.isNotEmpty) {
        await _showWarnings(installed.warnings);
      }
    } catch (error) {
      if (mounted &&
          !(error is PluginCatalogFailure && error.code == 'cancelled')) {
        await _showError(error);
      }
    } finally {
      await download?.dispose();
      if (mounted) {
        setState(() {
          _busy = false;
          _downloadingId = null;
        });
      }
    }
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
  if (error is PluginCatalogFailure) {
    return switch (error.code) {
      'checksum' => ModuStrings.text(
          context, '插件文件校验失败，请重试。', 'Plugin verification failed. Try again.'),
      'size' => ModuStrings.text(
          context, '插件文件超过大小限制。', 'The plugin file is too large.'),
      'unapproved' => ModuStrings.text(context, '请更新默读后再安装此插件。',
          'Update Modu before installing this plugin.'),
      'catalog' => ModuStrings.text(context, '插件目录校验失败，请稍后重试。',
          'The plugin catalog could not be verified. Try again later.'),
      _ => ModuStrings.text(context, '无法连接插件仓库，请重试。',
          'Could not connect to the plugin catalog. Try again.'),
    };
  }
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
