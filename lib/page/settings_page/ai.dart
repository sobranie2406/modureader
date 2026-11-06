import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_chat_display_mode.dart';
import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/page/settings_page/ai_provider_list_page.dart';
import 'package:anx_reader/page/settings_page/ai_reading_skills.dart';
import 'package:anx_reader/page/settings_page/settings_page.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
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

    final toolDefs = AiToolRegistry.current.definitions;
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
            descriptionAsHelp: false,
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
          //       MotionCupertinoPageRoute(
          //         builder: (context) => const AiChatPage(),
          //       ),
          //     );
          //   },
          // ),
        ],
      ),
      SettingsSection(
        title: Text(ModuStrings.text(context, 'AI 阅读技能', 'AI Reading Skills')),
        tiles: [
          SettingsTile.navigation(
            key: const ValueKey('ai-reading-skills-settings'),
            leading: const Icon(Icons.extension_outlined),
            title: Text(ModuStrings.text(
                context, '阅读技能与提示词', 'Reading skills and prompts')),
            description: Text(ModuStrings.text(context, '内置技能、自定义技能与功能提示词',
                'Built-in skills, custom skills and feature prompts')),
            onPressed: (context) => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsPageBody(
                  title:
                      ModuStrings.text(context, 'AI 阅读技能', 'AI Reading Skills'),
                  isMobile: true,
                  sections: const AiReadingSkillsSettings(),
                ),
              ),
            ),
          ),
        ],
      ),
      SettingsSection(
        title: Text(L10n.of(context).settingsAiChatDisplay),
        tiles: [
          aiChatDisplayModeTile(),
          if (Prefs().aiChatDisplayMode == AiChatDisplayMode.popup)
            SettingsTile.switchTile(
              key: const ValueKey('adjustable-reader-popups'),
              initialValue: Prefs().adjustableReaderPopups,
              onToggle: (value) {
                Prefs().adjustableReaderPopups = value;
                setState(() {});
              },
              title: Text(ModuStrings.text(
                  context, '允许移动和调整弹窗大小', 'Move and resize popups')),
              description: Text(ModuStrings.text(
                  context,
                  '适用于划词功能弹窗。拖动顶部移动，拖动两侧、底边或四角调整大小；每次打开恢复默认位置和大小。',
                  'For selection tool popups. Drag the top to move, or the sides, bottom and corners to resize. Each opening restores the default position and size.')),
            ),
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
        title: Text(ModuStrings.text(context, 'AI 对话历史', 'AI chat history')),
        tiles: [
          CustomSettingsTile(
            child: ListTile(
              title: SettingHelp(
                  title: Text(
                      ModuStrings.text(context, '保留对话历史', 'Keep chat history')),
                  description: Text(ModuStrings.text(
                      context,
                      '对话保存在本机数据目录，不随缓存清理，也不会按缓存数量自动删除。可在 AI 对话历史中单独管理。',
                      'Chats are stored locally and are not removed when clearing the cache or changing its size limit. Manage them separately in AI chat history.'))),
            ),
          ),
        ],
      ),
    ]);
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
      title: SettingHelp(
          title: Text(l10n.settingsAiRpm),
          description: Text(
            l10n.settingsAiRpmTip,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          )),
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
