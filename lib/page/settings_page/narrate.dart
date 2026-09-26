import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/config_transfer/tts_config_transfer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/tts_providers.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/system_tts.dart';
import 'package:anx_reader/service/tts/system_tts_support.dart';
import 'package:anx_reader/service/tts/tts_factory.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/service/tts/tts_service.dart' as tts_svc;
import 'package:anx_reader/utils/get_current_language_code.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/widgets/common/anx_button.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/widgets/settings/service_config_form.dart';
import 'package:anx_reader/widgets/settings/mimo_voice_settings.dart';
import 'package:anx_reader/widgets/settings/openai_voice_settings.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NarrateSettings extends ConsumerStatefulWidget {
  const NarrateSettings({super.key});

  @override
  ConsumerState<NarrateSettings> createState() => _NarrateSettingsState();
}

class _NarrateSettingsState extends ConsumerState<NarrateSettings>
    with SingleTickerProviderStateMixin {
  String? selectedVoiceModel;
  Map<String, List<TtsVoice>> groupedVoices = {};
  Set<String> expandedGroups = {};
  final ScrollController _scrollController = ScrollController();
  String? _highlightedModel;
  late AnimationController _highlightAnimationController;
  late Animation<Color?> _highlightAnimation;
  TtsVoice? _currentModelDetails;
  String? _currentModelLanguageGroup;

  final Map<String, GlobalKey> _languageKeys = {};
  final TextEditingController _testTextController = TextEditingController();
  bool _showVoiceList = false;

  final Map<String, bool> _modelLoadingStates = {};
  bool _mainTestLoading = false;
  final Map<String, Map<String, dynamic>> _configDrafts = {};
  bool _savingSettings = false;
  int _configRevision = 0;

  String _text(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  Future<void> _applySettings(Map<String, dynamic> data) async {
    // Reject invalid imports before interrupting speech or changing anything.
    final valid = TtsConfigTransfer.validate(data);
    if (_savingSettings) throw StateError('TTS settings are being saved');
    final hadVoiceList = _showVoiceList;
    setState(() {
      _savingSettings = true;
      _showVoiceList = false;
      _configRevision++;
    });
    final factory = TtsFactory();
    final hadPlayer = factory.hasCurrent;
    try {
      // Detach voice-list listeners before invalidating providers, otherwise
      // an import can unexpectedly fetch remote voices with the new API key.
      if (hadVoiceList) await WidgetsBinding.instance.endOfFrame;
      if (hadPlayer) {
        await TtsHandler().stop();
        await factory.dispose();
      }
      await TtsConfigTransfer.apply(Prefs(), valid);
      if (mounted) {
        setState(() {
          _configDrafts.clear();
          _showVoiceList = false;
          _currentModelDetails = null;
          _currentModelLanguageGroup = null;
          selectedVoiceModel = tts_svc
              .getTtsService(Prefs().ttsService)
              .provider
              .getSelectedVoice();
        });
        for (final id in TtsConfigTransfer.services) {
          ref.invalidate(onlineTtsConfigProvider(id));
        }
        ref.invalidate(ttsServiceProvider);
        ref.invalidate(ttsVoicesProvider);
      }
    } finally {
      // Rebind reading callbacks even if persistence failed and was rolled back.
      // No speech starts here; the user must explicitly press play again.
      try {
        if (hadPlayer) await TtsHandler().switchTtsType(Prefs().ttsService);
      } finally {
        if (mounted) setState(() => _savingSettings = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    final data = TtsConfigTransfer.snapshot(Prefs());
    for (final entry in _configDrafts.entries) {
      data['providers'][entry.key]['config'] =
          Map<String, dynamic>.from(entry.value);
    }
    try {
      await _applySettings(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_text('朗读设置已保存', 'Speech settings saved')),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_text('保存失败，请检查接口地址和朗读参数后重试',
              'Could not save. Check the service URL and speech parameters.')),
        ));
      }
    }
  }

  Future<void> _clearSettings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_text('清除朗读设置？', 'Clear speech settings?')),
        content: Text(_text(
            '将停止朗读，清除所有朗读服务的 API Key、接口配置、声音选择和未保存修改，并恢复默认语速、音调、音量及系统朗读。不影响 AI、书籍、笔记或同步设置。',
            'Stop speech, remove all TTS keys, service configurations, voice selections and drafts, and restore default rate, pitch, volume and system speech. AI, books, notes and sync settings are unchanged.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_text('取消', 'Cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_text('清除', 'Clear'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _applySettings(TtsConfigTransfer.defaults());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_text('朗读设置已清除', 'Speech settings cleared')),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              _text('清除失败，请重试', 'Could not clear settings. Please retry.')),
        ));
      }
    }
  }

  Widget _buildSettingsTransfer() => SettingsSection(
        title: Text(_text('朗读设置管理', 'Speech settings management')),
        tiles: [
          CustomSettingsTile(
              child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_text(
                  '接口修改请先保存，再获取声音或试听。请在“全局设置备份”中使用二维码或 modu 链接迁移已保存设置；跨设备系统声音可能需要重新选择。',
                  'Save service edits before loading voices or previewing. Transfer saved settings in Global settings backup via QR images or modu links. System voices may need reselection on another device.')),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                FilledButton.icon(
                    onPressed: _savingSettings ? null : _saveSettings,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_text('保存设置', 'Save settings'))),
                OutlinedButton.icon(
                    onPressed: _savingSettings ? null : _clearSettings,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(_text('清除设置', 'Clear settings'))),
              ]),
              if (_configDrafts.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_text('有未保存的接口修改。保存后可在“全局设置备份”中导出。',
                        'Unsaved edits. Save before exporting in Global settings backup.'))),
            ]),
          )),
        ],
      );

  Future<void> _testSpeak(String text, String? voiceShortName,
      {bool isMainButton = false}) async {
    if (isMainButton) {
      if (_mainTestLoading) return;
      setState(() {
        _mainTestLoading = true;
      });
    } else if (voiceShortName != null) {
      if (_modelLoadingStates[voiceShortName] == true) return;
      setState(() {
        _modelLoadingStates[voiceShortName] = true;
      });
    }

    try {
      final tts = TtsFactory().current;
      await tts.stop();
      if (tts is OnlineTts) {
        if (voiceShortName != null) {
          await tts.speakWithVoice(text, voiceShortName);
        } else {
          await tts.speak(content: text);
        }
      } else if (tts is SystemTts) {
        if (voiceShortName != null) {
          await tts.speakWithVoice(text, voiceShortName);
        } else {
          await tts.speak(content: text);
        }
      }
    } catch (e) {
      AnxLog.severe('TTS Test Speak Error: $e');
      if (mounted) {
        final errorColor = Theme.of(context).colorScheme.error;
        SmartDialog.show(
          useSystem: true,
          animationType: SmartAnimationType.centerFade_otherSlide,
          builder: (dialogContext) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error, color: errorColor),
                const SizedBox(width: 8),
                Text(L10n.of(dialogContext).commonError),
              ],
            ),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => SmartDialog.dismiss(),
                child: Text(L10n.of(dialogContext).commonOk),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (isMainButton) {
            _mainTestLoading = false;
          } else if (voiceShortName != null) {
            _modelLoadingStates[voiceShortName] = false;
          }
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();

    _highlightAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    final serviceId = Prefs().ttsService;
    selectedVoiceModel =
        tts_svc.getTtsService(serviceId).provider.getSelectedVoice();
    _testTextController.text = "Hello, this is a test.";
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _highlightAnimation = ColorTween(
      begin: Theme.of(context).colorScheme.primaryContainer.withAlpha(100),
      end: Colors.transparent,
    ).animate(_highlightAnimationController)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _highlightedModel = null;
          });
        }
      });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _highlightAnimationController.dispose();
    _testTextController.dispose();
    super.dispose();
  }

  void _updateCurrentModelDetails(List<TtsVoice> voices) {
    if (Prefs().ttsService == 'system') {
      selectedVoiceModel = Prefs().getTtsVoiceModel('system');
    }
    _currentModelDetails = null;
    _currentModelLanguageGroup = null;
    if (selectedVoiceModel != null) {
      for (var voice in voices) {
        if (voice.shortName == selectedVoiceModel) {
          _currentModelDetails = voice;
          break;
        }
      }

      for (var entry in groupedVoices.entries) {
        for (var voice in entry.value) {
          if (voice.shortName == selectedVoiceModel) {
            _currentModelLanguageGroup = entry.key;
            break;
          }
        }
        if (_currentModelLanguageGroup != null) break;
      }
    }
  }

  void _scrollToSelectedModel() {
    if (selectedVoiceModel == null || _currentModelLanguageGroup == null) {
      return;
    }

    if (!expandedGroups.contains(_currentModelLanguageGroup)) {
      setState(() {
        expandedGroups.add(_currentModelLanguageGroup!);
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _languageKeys[_currentModelLanguageGroup];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          alignment: 0.1, // Align near top
        );
      }

      setState(() {
        _highlightedModel = selectedVoiceModel;
      });
      _highlightAnimationController.reset();
      _highlightAnimationController.forward();
    });
  }

  void _groupVoicesByLanguage(List<TtsVoice> voices) {
    groupedVoices.clear();

    for (var voice in voices) {
      String locale = voice.locale; // TtsVoice ensures non-null
      String languageName = _getLanguageNameFromLocale(locale);

      if (!groupedVoices.containsKey(languageName)) {
        groupedVoices[languageName] = [];
      }

      groupedVoices[languageName]!.add(voice);
    }
  }

  String _getLanguageNameFromLocale(String locale) {
    if (locale.isEmpty) return 'Unknown';
    String langCode = locale.split('-')[0].toLowerCase();

    const Map<String, String> languageMap = {
      'ar': 'العربية', // Arabic
      'bg': 'Български', // Bulgarian
      'ca': 'Català', // Catalan
      'cs': 'Čeština', // Czech
      'da': 'Dansk', // Danish
      'de': 'Deutsch', // German
      'el': 'Ελληνικά', // Greek
      'en': 'English', // English
      'es': 'Español', // Spanish
      'et': 'Eesti', // Estonian
      'fi': 'Suomi', // Finnish
      'fr': 'Français', // French
      'gl': 'Galego', // Galician
      'gu': 'ગુજરાતી', // Gujarati
      'he': 'עברית', // Hebrew
      'hi': 'हिन्दी', // Hindi
      'hr': 'Hrvatski', // Croatian
      'hu': 'Magyar', // Hungarian
      'id': 'Bahasa Indonesia', // Indonesian
      'it': 'Italiano', // Italian
      'ja': '日本語', // Japanese
      'ko': '한국어', // Korean
      'lt': 'Lietuvių', // Lithuanian
      'lv': 'Latviešu', // Latvian
      'ms': 'Bahasa Melayu', // Malay
      'mt': 'Malti', // Maltese
      'nb': 'Norsk bokmål', // Norwegian Bokmål
      'nl': 'Nederlands', // Dutch
      'pl': 'Polski', // Polish
      'pt': 'Português', // Portuguese
      'ro': 'Română', // Romanian
      'ru': 'Русский', // Russian
      'sk': 'Slovenčina', // Slovak
      'sl': 'Slovenščina', // Slovenian
      'sv': 'Svenska', // Swedish
      'ta': 'தமிழ்', // Tamil
      'te': 'తెలుగు', // Telugu
      'th': 'ไทย', // Thai
      'tr': 'Türkçe', // Turkish
      'uk': 'Українська', // Ukrainian
      'ur': 'اردو', // Urdu
      'vi': 'Tiếng Việt', // Vietnamese
      'zh': '中文', // Chinese
      'yue': '粵語', // Cantonese
      'wuu': '吳語', // Wu Chinese
    };

    return languageMap[langCode] ?? locale;
  }

  void _toggleGroup(String languageName) {
    setState(() {
      if (expandedGroups.contains(languageName)) {
        expandedGroups.remove(languageName);
      } else {
        expandedGroups.add(languageName);
      }
    });
  }

  void _selectVoiceModel(String shortName) {
    final serviceId = ref.read(ttsServiceProvider);
    final provider = tts_svc.getTtsService(serviceId).provider;
    final hasVoiceField = provider.getConfig().containsKey('voice');
    if (hasVoiceField) {
      ref
          .read(onlineTtsConfigProvider(serviceId).notifier)
          .updateConfig('voice', shortName);
    }
    setState(() {
      selectedVoiceModel = shortName;
      provider.setSelectedVoice(shortName);
    });
  }

  IconData _getGenderIcon(String gender) {
    switch (gender.toLowerCase()) {
      case 'female':
        return Icons.female;
      case 'male':
        return Icons.male;
      default:
        return Icons.person;
    }
  }

  String _getCurrentModelDisplayName() {
    if (_currentModelDetails == null) {
      return L10n.of(context).settingsNarrateVoiceModelNotSelected;
    }
    return _currentModelDetails!.name;
  }

  String _getCurrentModelLanguageName() {
    if (_currentModelDetails == null) return '';
    return _currentModelDetails!.locale;
  }

  String _getCurrentModelGender() {
    if (_currentModelDetails == null) return '';
    return _currentModelDetails!.gender;
  }

  @override
  Widget build(BuildContext context) {
    final ttsServiceId = ref.watch(ttsServiceProvider);
    final currentProvider = tts_svc.getTtsService(ttsServiceId).provider;
    final unsupportedSystem = ttsServiceId == 'system' && !supportsSystemTts();

    // Listen to config changes to hide voice list
    ref.listen(onlineTtsConfigProvider(ttsServiceId), (prev, next) {
      if (prev != next) {
        setState(() {
          _showVoiceList = false;
          selectedVoiceModel = currentProvider.getSelectedVoice();
        });
      }
    });

    return AbsorbPointer(
        absorbing: _savingSettings,
        child: ListView(
          controller: _scrollController,
          padding:
              const EdgeInsets.only(bottom: 50.0), // Add padding for bottom
          children: [
            if (AnxPlatform.isAndroid)
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: Text(Localizations.localeOf(context).languageCode == 'zh'
                    ? '朗读通知'
                    : 'Reading notifications'),
                subtitle: Text(Localizations.localeOf(context).languageCode ==
                        'zh'
                    ? '在系统设置中管理通知栏与锁屏播放控制'
                    : 'Manage notification and lock-screen controls in system settings'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () async {
                  await openAppSettings();
                },
              ),
            if (AnxPlatform.isIOS)
              SettingsSection(
                title: Text(L10n.of(context).settingsNarrateTtsService),
                tiles: [
                  SettingsTile.switchTile(
                      title: Text(L10n.of(context).allowMixing),
                      description: Text(L10n.of(context).enableMixTip),
                      initialValue: Prefs().allowMixWithOtherAudio,
                      onToggle: (value) {
                        Prefs().allowMixWithOtherAudio = value;
                        setState(() {});
                      }),
                ],
              ),
            SettingsSection(
              title: Text(L10n.of(context).ttsType),
              tiles: [
                CustomSettingsTile(child: _buildServiceSelection(ttsServiceId)),
                if (unsupportedSystem)
                  CustomSettingsTile(
                      child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(systemTtsUnsupportedMessage(
                      chinese:
                          Localizations.localeOf(context).languageCode == 'zh',
                    )),
                  )),
                if (ttsServiceId != 'system')
                  CustomSettingsTile(child: _buildConfigSection(ttsServiceId)),
              ],
            ),

            _buildSettingsTransfer(),

            // Do not preview stale credentials while service edits are pending.
            if (!unsupportedSystem && !_configDrafts.containsKey(ttsServiceId))
              SettingsSection(
                title: Text(L10n.of(context).settingsNarrateTtsVoiceModels),
                tiles: [
                  CustomSettingsTile(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: _showVoiceList
                          ? Column(
                              children: [..._buildVoiceListContent()],
                            )
                          : Center(
                              child: AnxButton(
                                onPressed: () async {
                                  final revision = _configRevision;
                                  setState(() {
                                    _showVoiceList = true;
                                  });
                                  late final List<TtsVoice> voices;
                                  try {
                                    voices = await ref
                                        .refresh(ttsVoicesProvider.future);
                                  } catch (_) {
                                    // The voice list already renders the provider error.
                                    return;
                                  }
                                  if (!mounted ||
                                      !context.mounted ||
                                      revision != _configRevision ||
                                      _savingSettings ||
                                      Prefs().ttsService != ttsServiceId)
                                    return;
                                  if ((selectedVoiceModel?.isEmpty ?? true) &&
                                      voices.isNotEmpty) {
                                    final currentLocale =
                                        Localizations.localeOf(context);
                                    final currentLangCode =
                                        currentLocale.languageCode;

                                    // Try to find a voice matching current language
                                    TtsVoice? match = voices.firstWhere(
                                      (v) => v.locale.toLowerCase().startsWith(
                                          currentLangCode.toLowerCase()),
                                      orElse: () => voices.firstWhere(
                                        // Fallback to English
                                        (v) => v.locale
                                            .toLowerCase()
                                            .startsWith('en'),
                                        // Fallback to first available
                                        orElse: () => voices.first,
                                      ),
                                    );

                                    _selectVoiceModel(match.shortName);
                                  }
                                },
                                child: Text(L10n.of(context)
                                    .settingsNarrateGetVoiceList),
                              ),
                            ),
                    ),
                  )
                ],
              )
          ],
        ));
  }

  Widget _buildServiceSelection(String currentServiceId) {
    final isChinese = Localizations.localeOf(context).languageCode == 'zh';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: DropdownButtonFormField<String>(
        key: ValueKey('tts-service-$currentServiceId'),
        initialValue: currentServiceId,
        decoration: InputDecoration(
          labelText: L10n.of(context).settingsNarrateTtsService,
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem(value: 'edge', child: Text('Edge TTS')),
          DropdownMenuItem(
              value: 'system',
              enabled: supportsSystemTts(),
              child: Text(supportsSystemTts()
                  ? L10n.of(context).settingsNarrateSystemTts
                  : (isChinese
                      ? '系统语音（此平台不支持）'
                      : 'System speech (unavailable)'))),
          const DropdownMenuItem(value: 'dashscope', child: Text('DashScope')),
          const DropdownMenuItem(value: 'xiaomi', child: Text('Xiaomi MiMo')),
          DropdownMenuItem(
              value: 'openai',
              child: Text(isChinese ? 'OpenAI 兼容' : 'OpenAI compatible')),
        ],
        onChanged: (value) async {
          if (value != null && value != currentServiceId) {
            await TtsHandler().switchTtsType(value);
            ref.read(ttsServiceProvider.notifier).setService(value);

            // Hide voice list when switching services, require manual fetch
            _showVoiceList = false;

            // Sync selected voice model for the new service
            selectedVoiceModel =
                tts_svc.getTtsService(value).provider.getSelectedVoice();

            setState(() {});
          }
        },
      ),
    );
  }

  Widget _buildConfigSection(String serviceId) {
    final service = tts_svc.getTtsService(serviceId);
    if (service == tts_svc.TtsService.system) return const SizedBox.shrink();

    final provider = service.provider;
    final configItems = provider.getConfigItems(context);
    if (configItems.isEmpty) return const SizedBox.shrink();

    ref.watch(onlineTtsConfigProvider(serviceId));
    final config = _configDrafts[serviceId] ?? provider.getConfig();
    final isMimo = service == tts_svc.TtsService.xiaomi;
    final isOpenAi = service == tts_svc.TtsService.openai;
    void updateDraft(Map<String, dynamic> newConfig) {
      setState(() => _configDrafts[serviceId] = Map.from(newConfig));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
      child: Column(
        children: [
          ServiceConfigForm(
            key: ValueKey('tts-config-$serviceId-$_configRevision'),
            configItems: isMimo
                ? configItems
                    .where((item) => !const {'model', 'voice', 'stylePrompt'}
                        .contains(item.key))
                    .toList()
                : isOpenAi
                    ? configItems
                        .where((item) => item.key != 'instructions')
                        .toList()
                    : configItems,
            initialConfig: config,
            onConfigChanged: updateDraft,
          ),
          if (isMimo)
            MimoVoiceSettings(
              key: ValueKey('mimo-config-$_configRevision'),
              config: config,
              onChanged: updateDraft,
            ),
          if (isOpenAi)
            OpenAiVoiceSettings(
              key: ValueKey('openai-voice-config-$_configRevision'),
              config: config,
              onChanged: updateDraft,
            ),
        ],
      ),
    );
  }

  List<Widget> _buildVoiceListContent() {
    final voicesAsync = ref.watch(ttsVoicesProvider);

    return voicesAsync.when(
      data: (voices) {
        if (voices.isEmpty) {
          return [
            Center(child: Text(L10n.of(context).settingsNarrateNoVoicesFound))
          ];
        }

        _groupVoicesByLanguage(voices);
        _updateCurrentModelDetails(voices);

        return [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              controller: _testTextController,
              decoration: InputDecoration(
                labelText: L10n.of(context).settingsNarrateTestText,
                suffixIcon: Padding(
                  padding: const EdgeInsets.all(5.0),
                  child: AnxButton.icon(
                    type: AnxButtonType.text,
                    isLoading: _mainTestLoading,
                    icon: Icon(Icons.play_arrow),
                    label: Text(L10n.of(context).commonTest),
                    onPressed: () => _testSpeak(
                        _testTextController.text, selectedVoiceModel,
                        isMainButton: true),
                  ),
                ),
              ),
            ),
          ),
          if (!(Prefs().ttsService == 'xiaomi' &&
              tts_svc.TtsService.xiaomi.provider.getConfig()['model'] ==
                  'mimo-v2.5-tts-voicedesign')) ...[
            _buildCurrentModelSection(),
            Divider(thickness: 4, color: Theme.of(context).colorScheme.surface),
            ..._buildVoiceModelList(),
          ],
        ];
      },
      loading: () => [const Center(child: CircularProgressIndicator())],
      error: (err, stack) => [Center(child: Text('Error: $err'))],
    );
  }

  Widget _buildCurrentModelSection() {
    // Reuse existing UI logic
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: FilledContainer(
        child: InkWell(
          onTap: _scrollToSelectedModel,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      L10n.of(context).settingsNarrateVoiceModelCurrentModel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    Icon(
                      _getGenderIcon(_getCurrentModelGender()),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      radius: 24,
                      child: Icon(
                        _getGenderIcon(_getCurrentModelGender()),
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getCurrentModelDisplayName(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getCurrentModelLanguageName(),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      L10n.of(context).settingsNarrateVoiceModelClickToView,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Icon(
                      Icons.arrow_downward,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildVoiceModelList() {
    List<Widget> voiceModelList = [];

    String currentLangCode = getCurrentLanguageCode();
    String currentLangName = _getLanguageNameFromLocale(currentLangCode);

    var sortedEntries = groupedVoices.entries.toList()
      ..sort((a, b) {
        if (a.key == currentLangName) return -1;
        if (b.key == currentLangName) return 1;
        return a.key.compareTo(b.key);
      });

    for (var language in sortedEntries) {
      String languageName = language.key;
      List<TtsVoice> voicesInLanguage = language.value;

      // Assign key for auto-scroll
      final GlobalKey key =
          _languageKeys.putIfAbsent(languageName, () => GlobalKey());

      voiceModelList.add(
        Column(
          children: [
            FilledContainer(
              radius: 5,
              key: key,
              child: ListTile(
                title: Text(
                  languageName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                trailing: Icon(
                  expandedGroups.contains(languageName)
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onTap: () => _toggleGroup(languageName),
              ),
            ),
            if (expandedGroups.contains(languageName))
              ...voicesInLanguage.map((voice) {
                String shortName = voice.shortName;
                String friendlyName = voice.name;
                String gender = voice.gender;
                String displayName = friendlyName;

                bool isHighlighted = _highlightedModel == shortName;
                bool isSelected = selectedVoiceModel == shortName;
                String localizationedGender = gender.toLowerCase() == 'female'
                    ? L10n.of(context).settingsNarrateVoiceModelFemale
                    : gender.toLowerCase() == 'male'
                        ? L10n.of(context).settingsNarrateVoiceModelMale
                        : gender;

                final description = voice.description;
                final subtitle = description.isNotEmpty
                    ? '$localizationedGender · ${voice.locale} · $description'
                    : '$localizationedGender · ${voice.locale}';

                return AnimatedBuilder(
                  animation: _highlightAnimation,
                  builder: (context, child) {
                    return Container(
                      color: isHighlighted
                          ? _highlightAnimation.value
                          : Colors.transparent,
                      child: child,
                    );
                  },
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(
                        _getGenderIcon(gender),
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(
                      displayName,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(subtitle),
                    trailing: isSelected
                        ? Icon(Icons.check,
                            color: Theme.of(context).primaryColor)
                        : null,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnxButton.icon(
                            type: AnxButtonType.text,
                            isLoading: _modelLoadingStates[shortName] ?? false,
                            icon: Icon(Icons.play_arrow),
                            label: Text(L10n.of(context).commonTest),
                            onPressed: () =>
                                _testSpeak(_testTextController.text, shortName),
                          ),
                          AnxButton(
                            type: AnxButtonType.outlined,
                            child:
                                Text(L10n.of(context).settingsNarrateUseVoice),
                            onPressed: () {
                              _selectVoiceModel(shortName);
                            },
                          )
                        ],
                      )
                    ],
                  ),
                );
              }),
            if (language != sortedEntries.last)
              Divider(
                height: 1,
                thickness: 4,
                color: Theme.of(context).colorScheme.surface,
              ),
          ],
        ),
      );
    }

    return voiceModelList;
  }
}
