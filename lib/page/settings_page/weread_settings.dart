import 'package:modu_reader/widgets/settings/setting_help_title.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/widgets/settings/settings_section.dart';
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
                                "保存 API Key 后，关联书籍即可查看评分和书评。",
                                "Save your API key, then link a book to see its ratings and reviews."))),
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
