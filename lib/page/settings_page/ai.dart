import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_chat_display_mode.dart';
import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/ai_provider_list_page.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/service/config_transfer/settings_config_transfer.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/config_transfer_tile.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AISettings extends ConsumerStatefulWidget {
  const AISettings({super.key});

  @override
  ConsumerState<AISettings> createState() => _AISettingsState();
}

class _AISettingsState extends ConsumerState<AISettings> {
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    ref.watch(aiProvidersProvider);

    final toolDefs = AiToolRegistry.definitions;
    final enabledToolIds = Prefs().enabledAiToolIds;

    final toolsTile = CustomSettingsTile(
      child: Column(
        children: [
          for (final tool in toolDefs)
            SettingsTile.switchTile(
              initialValue: enabledToolIds.contains(tool.id),
              onToggle: (value) {
                final next = Set<String>.from(enabledToolIds);
                if (value) {
                  next.add(tool.id);
                } else {
                  next.remove(tool.id);
                }
                Prefs().enabledAiToolIds = next.toList();
                setState(() {});
              },
              title: Text(tool.displayName(l10n)),
              description: Text(tool.description(l10n)),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                Prefs().resetEnabledAiTools();
                setState(() {});
              },
              child: Text(l10n.commonReset),
            ),
          ),
        ],
      ),
    );

    return settingsSections(sections: [
      SettingsSection(
        title: Text(L10n.of(context).settingsAiServices),
        tiles: [
          SettingsTile.navigation(
            title: Text(l10n.settingsAiProviders),
            description: _buildProviderDescription(),
            onPressed: (context) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AiProviderListPage(),
                ),
              );
            },
          ),
          CustomSettingsTile(
              child: _AiRpmTile(setState: () => setState(() {}))),
          // SettingsTile.navigation(
          //   leading: const Icon(Icons.chat),
          //   title: Text(L10n.of(context).aiChat),
          //   onPressed: (context) {
          //     Navigator.push(
          //       context,
          //       CupertinoPageRoute(
          //         builder: (context) => const AiChatPage(),
          //       ),
          //     );
          //   },
          // ),
        ],
      ),
      SettingsSection(
        title: Text(L10n.of(context).settingsAiChatDisplay),
        tiles: [
          aiChatDisplayModeTile(),
          if (Prefs().aiChatDisplayMode != AiChatDisplayMode.popup)
            aiPanelPositionTile(),
        ],
      ),
      SettingsSection(
        title: Text(l10n.settingsAiTools),
        tiles: [
          toolsTile,
        ],
      ),
      SettingsSection(
        title: const Text('AI 对话历史'),
        tiles: [
          CustomSettingsTile(
            child: const ListTile(
              title: Text('保留对话历史'),
              subtitle:
                  Text('对话保存在本机数据目录，不随缓存清理，也不会按缓存数量自动删除。可在 AI 对话历史中单独管理。'),
            ),
          ),
        ],
      ),
      SettingsSection(
        tiles: [
          ConfigTransferTile(
            kind: 'ai',
            label: _readAnyLabel('AI 配置', 'AI configuration'),
            getData: _buildAiTransferData,
            applyData: _applyAiTransferData,
          ),
        ],
      ),
    ]);
  }

  Map<String, dynamic> _buildAiTransferData() {
    final prefs = Prefs();
    return AiConfigTransfer.createPayload(
      providers: ref.read(aiProvidersProvider),
      selectedProviderId: prefs.selectedAiService,
      temperature: prefs.aiTemperature,
      maxTokens: prefs.aiMaxTokens,
      contextTurns: prefs.aiContextTurns,
      rpm: prefs.aiRpm,
      translationProviderId: prefs.translationAiService,
    );
  }

  Future<void> _applyAiTransferData(Map<String, dynamic> data) async {
    final imported = AiConfigTransfer.parse(data);
    final prefs = Prefs();
    prefs.saveAiProviders(imported.providers);
    prefs.selectedAiService = imported.selectedProviderId;
    prefs.aiTemperature = imported.temperature;
    prefs.aiMaxTokens = imported.maxTokens;
    prefs.aiContextTurns = imported.contextTurns;
    if (imported.rpm != null) prefs.aiRpm = imported.rpm!;
    final translationId = imported.translationProviderId;
    if (translationId != null &&
        imported.providers.any((provider) => provider.id == translationId)) {
      prefs.translationAiService = translationId;
    }
    ref.read(aiProvidersProvider.notifier).refresh();
    if (mounted) setState(() {});
  }

  String _readAnyLabel(String zh, String en) {
    return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
  }

  // Build description showing current selected provider
  Widget? _buildProviderDescription() {
    final provider =
        ref.read(aiProvidersProvider.notifier).getSelectedProvider();
    if (provider == null) {
      return null;
    }
    return Text(provider.title);
  }

  // AI chat display mode configuration
  AbstractSettingsTile aiChatDisplayModeTile() {
    final l10n = L10n.of(context);
    return CustomSettingsTile(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsAiChatDisplayMode,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AnxSegmentedButton<AiChatDisplayMode>(
                    segments: [
                      SegmentButtonItem(
                        value: AiChatDisplayMode.adaptive,
                        label: l10n.settingsAiChatDisplayModeAdaptive,
                        icon: const Icon(Icons.auto_awesome, size: 18),
                      ),
                      SegmentButtonItem(
                        value: AiChatDisplayMode.split,
                        label: l10n.settingsAiChatDisplayModeSplit,
                        icon: const Icon(Icons.splitscreen, size: 18),
                      ),
                      SegmentButtonItem(
                        value: AiChatDisplayMode.popup,
                        label: l10n.settingsAiChatDisplayModePopup,
                        icon: const Icon(Icons.open_in_new, size: 18),
                      ),
                    ],
                    selected: {Prefs().aiChatDisplayMode},
                    onSelectionChanged: (Set<AiChatDisplayMode> selected) {
                      if (selected.isNotEmpty) {
                        Prefs().aiChatDisplayMode = selected.first;
                        setState(() {});
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // AI panel position configuration (only shown when not in popup mode)
  AbstractSettingsTile aiPanelPositionTile() {
    final l10n = L10n.of(context);
    return CustomSettingsTile(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsAiPanelPosition,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AnxSegmentedButton<AiPanelPositionEnum>(
                    segments: [
                      SegmentButtonItem(
                        value: AiPanelPositionEnum.bottom,
                        label: l10n.settingsAiPanelPositionBottom,
                        icon: const Icon(Icons.vertical_align_bottom, size: 18),
                      ),
                      SegmentButtonItem(
                        value: AiPanelPositionEnum.right,
                        label: l10n.settingsAiPanelPositionRight,
                        icon: const Icon(Icons.border_right, size: 18),
                      ),
                    ],
                    selected: {Prefs().aiPanelPosition},
                    onSelectionChanged: (Set<AiPanelPositionEnum> selected) {
                      if (selected.isNotEmpty) {
                        Prefs().aiPanelPosition = selected.first;
                        setState(() {});
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AiRpmTile extends StatefulWidget {
  const _AiRpmTile({required this.setState});

  final VoidCallback setState;

  @override
  State<_AiRpmTile> createState() => _AiRpmTileState();
}

class _AiRpmTileState extends State<_AiRpmTile> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final rpm = Prefs().aiRpm;
    _controller = TextEditingController(text: rpm == 0 ? '' : rpm.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ListTile(
      title: Text(l10n.settingsAiRpm),
      subtitle: Text(
        l10n.settingsAiRpmTip,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      trailing: SizedBox(
        width: 80,
        child: TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            hintText: '0',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            isDense: true,
          ),
          onChanged: (value) {
            Prefs().aiRpm = int.tryParse(value) ?? 0;
            widget.setState();
          },
        ),
      ),
    );
  }
}
