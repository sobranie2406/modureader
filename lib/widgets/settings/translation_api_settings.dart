import 'package:modu_reader/widgets/settings/setting_help_title.dart';
import 'package:modu_reader/service/translate/index.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/service/translate/classical_translation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:modu_reader/widgets/settings/translation_usage_card.dart';

/// Credentials are shared; reading language, direction and output style are not.
class TranslationApiSettings extends StatefulWidget {
  const TranslationApiSettings(
      {super.key, required this.engine, this.onChanged});
  final ClassicalTranslationEngine engine;
  final VoidCallback? onChanged;
  @override
  State<TranslationApiSettings> createState() => _TranslationApiSettingsState();
}

class _TranslationApiSettingsState extends State<TranslationApiSettings> {
  final Map<String, TextEditingController> controllers = {};
  final Set<String> revealed = {};
  String? savedStatus;
  String label(String zh, String en) => ModuStrings.text(context, zh, en);
  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget field(String key, String title, {bool secret = false}) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
          key: ValueKey(key),
          controller: controllers.putIfAbsent(
              key,
              () => TextEditingController(
                  text: Prefs().classicalTranslationConfig[key] ??
                      (key.startsWith('microsoft_')
                          ? (Prefs().getTranslateServiceConfig(
                                          TranslateService.microsoftApi) ??
                                      {})[
                                  key == 'microsoft_key' ? 'api_key' : 'region']
                              ?.toString()
                          : null) ??
                      '')),
          obscureText: secret && !revealed.contains(key),
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
              labelText: title,
              border: const OutlineInputBorder(),
              suffixIcon: secret
                  ? IconButton(
                      tooltip: label('显示／隐藏密钥', 'Show/hide key'),
                      icon: Icon(revealed.contains(key)
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => setState(() {
                            revealed.contains(key)
                                ? revealed.remove(key)
                                : revealed.add(key);
                          }))
                  : null),
          onChanged: (_) => setState(() => savedStatus = null)));

  void saveCredentials(ClassicalTranslationEngine engine) {
    final keys = engine == ClassicalTranslationEngine.baidu
        ? ['baidu_appid', 'baidu_key']
        : ['microsoft_key', 'microsoft_region'];
    final values = {
      for (final key in keys) key: controllers[key]?.text.trim() ?? ''
    };
    if (engine == ClassicalTranslationEngine.baidu &&
        values.values.any((v) => v.isNotEmpty) &&
        values.values.any((v) => v.isEmpty)) {
      setState(() => savedStatus =
          label('请同时填写 APP ID 和密钥。', 'Enter both APP ID and secret key.'));
      return;
    }
    final region = values['microsoft_region'] ?? '';
    if (region.isNotEmpty && !RegExp(r'^[a-z0-9-]+$').hasMatch(region)) {
      setState(() => savedStatus = label('区域请填写 Azure 区域代码，例如 eastasia。',
          'Use an Azure region code, e.g. eastasia.'));
      return;
    }
    Prefs().classicalTranslationConfig = {
      ...Prefs().classicalTranslationConfig,
      ...values
    };
    setState(() => savedStatus = label('配置已保存，尚未发送翻译请求。',
        'Configuration saved. No translation request sent.'));
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (engine == ClassicalTranslationEngine.baidu) ...[
            field('baidu_appid', 'APP ID'),
            field('baidu_key', label('密钥', 'Secret key'), secret: true),
            const SizedBox(height: 8),
            SettingHelp(
                title: Text(ModuStrings.text(context, "获取密钥", "Get a key")),
                description: Text(label("在百度翻译开放平台开通“通用文本翻译”，填写 APP ID 和密钥。",
                    "Enable General Text Translation on Baidu Translate and enter its APP ID and secret key."))),
            TextButton(
                onPressed: () => launchUrl(
                    Uri.parse('https://fanyi-api.baidu.com/doc_bd/21'),
                    mode: LaunchMode.externalApplication),
                child: Text(label('百度官方接入文档', 'Baidu API documentation'))),
          ],
          if (engine == ClassicalTranslationEngine.microsoft) ...[
            field(
                'microsoft_key',
                label(
                    '订阅密钥（Key 1 或 Key 2）', 'Subscription key (Key 1 or Key 2)'),
                secret: true),
            field('microsoft_region',
                label('资源区域（例如 eastasia）', 'Resource region (e.g. eastasia)')),
            const SizedBox(height: 8),
            SettingHelp(
                title: Text(ModuStrings.text(context, "获取密钥", "Get a key")),
                description: Text(label("在 Azure 的 Translator 资源中复制密钥和区域。",
                    "Copy the key and region from your Azure Translator resource."))),
            TextButton(
                onPressed: () => launchUrl(
                    Uri.parse(
                        'https://learn.microsoft.com/azure/ai-services/translator/text-translation/reference/authentication'),
                    mode: LaunchMode.externalApplication),
                child: Text(label(
                    '微软官方接入文档', 'Microsoft authentication documentation'))),
          ],
          if (engine != ClassicalTranslationEngine.ai) ...[
            FilledButton.icon(
                key: const ValueKey('save-classical-credentials'),
                onPressed: () => saveCredentials(engine),
                icon: const Icon(Icons.save_outlined),
                label: Text(label('保存配置', 'Save configuration'))),
            if (savedStatus != null) Text(savedStatus!),
            const SizedBox(height: 16),
            TranslationUsageCard(engine: engine.name, config: {
              ...Prefs().classicalTranslationConfig,
              if (engine == ClassicalTranslationEngine.microsoft &&
                  (Prefs().classicalTranslationConfig['microsoft_key'] ?? '')
                      .isEmpty)
                'microsoft_key': (Prefs().getTranslateServiceConfig(
                            TranslateService.microsoftApi)?['api_key'] ??
                        '')
                    .toString(),
            }),
          ],
        ]);
  }
}
