import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/page/settings_page/plugins/plugins_page.dart';
import 'package:anx_reader/service/plugins/plugin_host.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';

class ExperimentalSettings extends StatefulWidget {
  const ExperimentalSettings({super.key, this.host});
  final PluginHost? host;

  @override
  State<ExperimentalSettings> createState() => _ExperimentalSettingsState();
}

class _ExperimentalSettingsState extends State<ExperimentalSettings> {
  bool _busy = false;
  PluginHost get _host => widget.host ?? PluginHost.instance;

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (value) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(ModuStrings.text(
                context, '开启实验性插件？', 'Enable experimental plugins?')),
            content: Text(ModuStrings.text(
                context,
                "开启后可安装项目提供的提示词包和划词动作。使用 AI 动作时，会把所选内容发送给你配置的 AI 服务。",
                "Install prompt packs and selection actions provided by the project. AI actions send selected text to your configured AI service.")),
            scrollable: true,
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
              FilledButton(
                  key: const ValueKey('confirm-experimental-plugins'),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(ModuStrings.text(
                      context, '了解风险，确认开启', 'Understand risks and enable'))),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      await _host.setExperimentalEnabled(value);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(pluginErrorText(context, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([Prefs(), _host]),
        builder: (context, _) {
          final enabled = Prefs().experimentalPluginsEnabled;
          return settingsSections(sections: [
            SettingsSection(
              title: Text(
                  ModuStrings.text(context, '实验性功能', 'Experimental features')),
              tiles: [
                SettingsTile.switchTile(
                  key: const ValueKey('experimental-plugins-switch'),
                  leading: const Icon(Icons.extension_outlined),
                  title: Text(ModuStrings.text(context, '插件', 'Plugins')),
                  description: Text(ModuStrings.text(
                      context, "在此设备上启用插件。", "Enable plugins on this device.")),
                  initialValue: enabled,
                  enabled: !_busy && PluginHost.isEnabled,
                  onToggle: _toggle,
                ),
                if (enabled)
                  SettingsTile.navigation(
                    title: Text(
                        ModuStrings.text(context, '管理插件', 'Manage plugins')),
                    leading: const Icon(Icons.settings_outlined),
                    enabled: !_busy,
                    onPressed: (_) => Navigator.push(
                        context,
                        MotionCupertinoPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(
                                title: Text(ModuStrings.text(
                                    context, '插件', 'Plugins'))),
                            body: PluginSettings(host: _host),
                          ),
                        )),
                  ),
              ],
            ),
          ]);
        },
      );
}
