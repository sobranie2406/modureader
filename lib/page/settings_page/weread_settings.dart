import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class WereadSettingsPage extends StatefulWidget {
  const WereadSettingsPage({super.key});
  @override
  State<WereadSettingsPage> createState() => _WereadSettingsPageState();
}

class _WereadSettingsPageState extends State<WereadSettingsPage> {
  late final _key = TextEditingController(text: Prefs().wereadApiKey);
  bool _hidden = true, _saving = false;
  String? _message;
  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _save({bool? enabled}) async {
    final key = _key.text.trim();
    if (enabled != false &&
        key.isNotEmpty &&
        !RegExp(r'^wrk-[A-Za-z0-9_-]+$').hasMatch(key)) {
      setState(() => _message = ModuStrings.text(
          context, 'API Key 格式应为 wrk-…', 'API Key must have the form wrk-…'));
      return;
    }
    setState(() => _saving = true);
    try {
      await Prefs().saveWereadSettings(
          enabled: enabled, apiKey: enabled == false ? null : key);
      if (mounted) {
        setState(() => _message = ModuStrings.text(context, '已保存', 'Saved'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = ModuStrings.text(
            context, '保存失败，请重试', 'Could not save. Please retry.'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title:
                Text(ModuStrings.text(context, '关联微信读书', 'WeRead connection'))),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child:
                ListView(padding: const EdgeInsets.only(bottom: 20), children: [
              SettingsSection.content(
                title: Text(ModuStrings.text(
                    context, '连接与授权', 'Connection and authorization')),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: SettingHelp(
                            title: Text(ModuStrings.text(
                                context, '启用微信读书', 'Enable WeRead')),
                            description: Text(ModuStrings.text(
                                context,
                                '默认关闭，仅在本机生效。关闭后停止查询，保留关联及缓存。',
                                'Off by default, per device. Turning off stops queries and retains saved links and data.'))),
                        value: Prefs().wereadEnabled,
                        onChanged:
                            _saving ? null : (value) => _save(enabled: value),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _key,
                        obscureText: _hidden,
                        enableSuggestions: false,
                        autocorrect: false,
                        maxLength: 512,
                        decoration: InputDecoration(
                          labelText: 'WeRead API Key',
                          hintText: 'wrk-…',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: ModuStrings.text(
                                context, '显示／隐藏密钥', 'Show/hide key'),
                            icon: Icon(_hidden
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () => setState(() => _hidden = !_hidden),
                          ),
                        ),
                      ),
                      FilledButton(
                          onPressed: _saving ? null : () => _save(),
                          child: Text(ModuStrings.text(
                              context, '保存 API Key', 'Save API Key'))),
                      TextButton.icon(
                        icon: const Icon(Icons.open_in_new),
                        label: Text(ModuStrings.text(context, '获取官方 API Key',
                            'Get an official API Key')),
                        onPressed: () async {
                          try {
                            final opened = await launchUrl(
                                Uri.parse(
                                    'https://weread.qq.com/r/weread-skills'),
                                mode: LaunchMode.externalApplication);
                            if (!opened) throw StateError('unavailable');
                          } catch (_) {
                            if (mounted) {
                              setState(() => _message = ModuStrings.text(
                                  context,
                                  '无法打开，请访问 weread.qq.com/r/weread-skills',
                                  'Open weread.qq.com/r/weread-skills in your browser.'));
                            }
                          }
                        },
                      ),
                      Text(ModuStrings.text(
                          context,
                          '使用微信读书官方接口。仅发送检索的书名、作者或关联的 bookId，不上传本地正文、笔记和书评。\n\n'
                              'API Key 纳入全局设置的敏感数据：备份须勾选包含账号密钥；云端同步须先启用“敏感数据同步”并设置独立加密密码。'
                              '所有参与密钥同步的设备需更新到支持微信读书的版本。\n\n'
                              '关联和已加载的外部资料随原书同步；未下载的书不下载这些缓存。关闭本开关不会关闭已单独启用的敏感数据同步。',
                          'Uses official WeRead APIs. Only search titles, authors and linked book IDs are sent; local book text, notes and reviews are never uploaded to WeRead.\n\n'
                              'The API Key is sensitive global configuration: exporting it requires the include-credentials option; cloud transfer requires Sensitive data sync and a separate encryption password. '
                              'Update every participating device to a version supporting WeRead.\n\n'
                              'Links and loaded external data sync with downloaded books. Disabling this connection does not disable separately enabled sensitive data sync.')),
                      if (_message != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(_message!)),
                    ]),
              ),
            ]),
          ),
        ),
      );
}
