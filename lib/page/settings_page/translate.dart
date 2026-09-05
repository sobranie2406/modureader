import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/service/translate/deepl.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';

class TranslateSetting extends StatefulWidget {
  const TranslateSetting({super.key});

  @override
  State<TranslateSetting> createState() => _TranslateSettingState();
}

class _TranslateSettingState extends State<TranslateSetting> {
  late final TextEditingController _deepLApiKeyController;
  late final TextEditingController _deepLBaseUrlController;
  bool _obscureDeepLKey = true;

  bool get _isChinese => Localizations.localeOf(context).languageCode == 'zh';

  String _label(String zh, String en) => _isChinese ? zh : en;

  @override
  void initState() {
    super.initState();
    final config = TranslateService.deepl.provider.getConfig();
    _deepLApiKeyController = TextEditingController(
      text: config['api_key']?.toString() ?? '',
    );
    _deepLBaseUrlController = TextEditingController(
      text: config['api_url']?.toString() ?? 'https://api-free.deepl.com/v2',
    );
  }

  @override
  void dispose() {
    _deepLApiKeyController.dispose();
    _deepLBaseUrlController.dispose();
    super.dispose();
  }

  void _selectService(TranslateService service) {
    Prefs().translateService = service;
    Prefs().fullTextTranslateService = service;
    setState(() {});
  }

  Future<void> _showServicePicker() async {
    final selected = await showModalBottomSheet<TranslateService>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  _label('选择翻译引擎', 'Select translation engine'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            for (final service in TranslateService.readAnyValues)
              RadioListTile<TranslateService>(
                value: service,
                groupValue: Prefs().fullTextTranslateService,
                title: Text(service.getLabel(context)),
                subtitle: Text(_serviceDescription(service)),
                onChanged: (value) => Navigator.pop(context, value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null) _selectService(selected);
  }

  String _serviceDescription(TranslateService service) {
    return switch (service) {
      TranslateService.microsoftFree => _label(
          '无需 API 密钥，开箱即用',
          'Works without an API key',
        ),
      TranslateService.ai => _label(
          '使用 AI 设置中已配置的服务商和模型',
          'Uses a provider and model configured in AI settings',
        ),
      TranslateService.deepl => _label(
          '支持 DeepL 官方接口和 DeepLX 自定义地址',
          'Supports official DeepL and custom DeepLX endpoints',
        ),
      _ => _label('兼容旧版配置', 'Legacy-compatible provider'),
    };
  }

  List<AiProvider> get _configuredAiModels {
    final providers = <AiProvider>[];
    for (final raw in Prefs().getAiProviders()) {
      try {
        final provider = AiProvider.fromJson(raw as Map<String, dynamic>);
        if (provider.enabled &&
            provider.hasValidKey &&
            provider.model.trim().isNotEmpty) {
          providers.add(provider);
        }
      } catch (_) {
        // Ignore malformed legacy entries; AI settings can repair them.
      }
    }
    return providers;
  }

  AiProvider? _currentTranslationAiModel(List<AiProvider> providers) {
    if (providers.isEmpty) return null;
    final selected = Prefs().translationAiService;
    for (final provider in providers) {
      if (provider.id == selected) return provider;
    }
    return providers.first;
  }

  Future<void> _showAiModelPicker(List<AiProvider> providers) async {
    if (providers.isEmpty) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  _label('选择翻译模型', 'Select translation model'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final provider in providers)
                    RadioListTile<String>(
                      value: provider.id,
                      groupValue: Prefs().translationAiService,
                      title: Text(provider.model),
                      subtitle: Text(provider.title),
                      onChanged: (value) => Navigator.pop(context, value),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null) {
      Prefs().translationAiService = selected;
      setState(() {});
    }
  }

  Future<void> _showLanguagePicker() async {
    final languages = LangListEnum.values
        .where((language) => language != LangListEnum.auto)
        .toList(growable: false);
    final selected = await showModalBottomSheet<LangListEnum>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    _label('选择目标语言', 'Select target language'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: languages.length,
                  itemBuilder: (context, index) {
                    final language = languages[index];
                    return RadioListTile<LangListEnum>(
                      value: language,
                      groupValue: Prefs().fullTextTranslateTo,
                      title: Text(language.nativeName),
                      onChanged: (value) => Navigator.pop(context, value),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      Prefs().translateFrom = LangListEnum.auto;
      Prefs().fullTextTranslateFrom = LangListEnum.auto;
      Prefs().translateTo = selected;
      Prefs().fullTextTranslateTo = selected;
      setState(() {});
    }
  }

  void _saveDeepLConfig() {
    TranslateService.deepl.provider.saveConfig({
      'api_key': _deepLApiKeyController.text.trim(),
      'api_url': normalizeDeepLBaseUrl(_deepLBaseUrlController.text),
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = Prefs().fullTextTranslateService;
    final aiModels = _configuredAiModels;
    final aiModel = _currentTranslationAiModel(aiModels);

    return settingsSections(
      sections: [
        SettingsSection(
          title: Text(_label('翻译设置', 'Translation settings')),
          tiles: [
            CustomSettingsTile(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    _label('配置翻译选项', 'Configure translation options'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
            SettingsTile.navigation(
              leading: const Icon(Icons.translate_outlined),
              title: Text(_label('翻译引擎', 'Translation engine')),
              value: Text(service.getLabel(context)),
              onPressed: (_) => _showServicePicker(),
            ),
            if (service == TranslateService.ai)
              SettingsTile.navigation(
                leading: const Icon(Icons.smart_toy_outlined),
                title: Text(_label('翻译模型', 'Translation model')),
                description: aiModel == null
                    ? Text(_label(
                        '请先在 AI 设置中配置服务商和模型',
                        'Configure a provider and model in AI settings first',
                      ))
                    : Text(aiModel.title),
                value: Text(aiModel?.model ?? _label('未配置', 'Not configured')),
                enabled: aiModels.isNotEmpty,
                onPressed: (_) => _showAiModelPicker(aiModels),
              ),
            if (service == TranslateService.deepl)
              CustomSettingsTile(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _deepLApiKeyController,
                        obscureText: _obscureDeepLKey,
                        decoration: InputDecoration(
                          labelText: 'DeepL API Key',
                          hintText: _label(
                            '输入 DeepL API Key',
                            'Enter DeepL API key',
                          ),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureDeepLKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(
                              () => _obscureDeepLKey = !_obscureDeepLKey,
                            ),
                          ),
                        ),
                        onChanged: (_) => _saveDeepLConfig(),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _deepLBaseUrlController,
                        decoration: InputDecoration(
                          labelText: _label(
                            'DeepL 请求地址',
                            'DeepL request URL',
                          ),
                          hintText: 'https://api-free.deepl.com/v2',
                          helperText: _label(
                            '支持官方 DeepL、DeepLX 基础地址或完整 /translate 地址',
                            'Supports official DeepL, a DeepLX base URL, or a full /translate URL',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => _saveDeepLConfig(),
                        onEditingComplete: () {
                          final normalized = normalizeDeepLBaseUrl(
                            _deepLBaseUrlController.text,
                          );
                          _deepLBaseUrlController.value = TextEditingValue(
                            text: normalized,
                            selection: TextSelection.collapsed(
                              offset: normalized.length,
                            ),
                          );
                          _saveDeepLConfig();
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        SettingsSection(
          title: Text(_label('阅读翻译', 'Reader translation')),
          tiles: [
            SettingsTile.navigation(
              leading: const Icon(Icons.language_outlined),
              title: Text(_label('目标语言', 'Target language')),
              description: Text(_label(
                '阅读器底栏也可以临时切换目标语言',
                'The target can also be changed from the reader toolbar',
              )),
              value: Text(Prefs().fullTextTranslateTo.nativeName),
              onPressed: (_) => _showLanguagePicker(),
            ),
            SettingsTile.switchTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              initialValue: Prefs().autoTranslateSelection,
              title: Text(_label(
                '选中文本后自动翻译',
                'Translate selected text automatically',
              )),
              description: Text(_label(
                '选择正文后直接打开翻译结果',
                'Open translation automatically after selecting text',
              )),
              onToggle: (value) {
                Prefs().autoTranslateSelection = value;
                setState(() {});
              },
            ),
            CustomSettingsTile(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _label(
                          '执行翻译时，当前文字会发送到所选翻译服务。',
                          'When translating, the current text is sent to the selected translation service.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
