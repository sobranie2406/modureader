import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/enums/app_layout_mode.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/app_language.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/enums/bookshelf_folder_style.dart';
import 'package:anx_reader/page/settings_page/theme_colors.dart';
import 'package:anx_reader/page/settings_page/weread_settings.dart';

const List<Map<String, String>> languageOptions = [
  {'system': 'System'},
  {'English': 'en'},
  {'简体中文': 'zh-CN'},
  {'繁體中文': 'zh-TW'},
  {'文言文': 'zh-LZH'},
  {'Türkçe': 'tr'},
  {'Deutsch': 'de'},
  {'العربية': 'ar'},
  {'Русский': 'ru'},
  {'Français': 'fr'},
  {'Español': 'es'},
  {'Italiano': 'it'},
  {'Português': 'pt'},
  {'日本語': 'ja'},
  {'한국어': 'ko'},
  {'Română': 'ro'},
];

class AppearanceSetting extends StatefulWidget {
  const AppearanceSetting({super.key});

  @override
  State<AppearanceSetting> createState() => _AppearanceSettingState();
}

class _AppearanceSettingState extends State<AppearanceSetting> {
  /// Preset name, or the raw hex for a colour chosen outside the palette.
  String _activeThemeColorLabel(BuildContext context) {
    final preset = Prefs().activeThemePreset;
    if (preset != null) return preset.label(Localizations.localeOf(context));
    final hex = Prefs()
        .themeColor
        .toARGB32()
        .toRadixString(16)
        .substring(2)
        .toUpperCase();
    return '#$hex';
  }

  TimeOfDay _time(int minute) =>
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60);

  String _nightHours(BuildContext context) {
    final prefs = Prefs();
    final nextDay = prefs.nightEndMinute < prefs.nightStartMinute
        ? ModuStrings.text(context, '次日 ', 'next day ')
        : '';
    return '${_time(prefs.nightStartMinute).format(context)} – $nextDay${_time(prefs.nightEndMinute).format(context)}';
  }

  Future<void> _editNightHours(BuildContext context) async {
    final start = await showTimePicker(
        context: context,
        helpText: ModuStrings.text(context, '夜间开始时间', 'Night starts'),
        initialTime: _time(Prefs().nightStartMinute));
    if (start == null || !context.mounted) return;
    final end = await showTimePicker(
        context: context,
        helpText: ModuStrings.text(context, '夜间结束时间', 'Night ends'),
        initialTime: _time(Prefs().nightEndMinute));
    if (end == null || !context.mounted) return;
    final startMinute = start.hour * 60 + start.minute;
    final endMinute = end.hour * 60 + end.minute;
    if (startMinute == endMinute) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ModuStrings.text(
              context, '开始和结束时间不能相同', 'Start and end times must differ'))));
      return;
    }
    await Prefs().saveThemeSchedule(start: startMinute, end: endMinute);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final localeKey = appLocaleKey(Localizations.localeOf(context));
    final languageSubtitle = Prefs().locale == null
        ? ModuStrings.text(context, '跟随系统', 'Follow system')
        : languageOptions
            .firstWhere(
                (element) =>
                    element.values.first == appLocaleKey(Prefs().locale!),
                orElse: () => languageOptions[0])
            .keys
            .first;

    return settingsSections(
      sections: [
        SettingsSection(
          title: Text(L10n.of(context).settingsAppearanceTheme),
          tiles: [
            SettingsTile.switchTile(
              key: const ValueKey('scheduled-theme-enabled'),
              title: Text(ModuStrings.text(
                  context, '按时间切换日夜模式', 'Scheduled day/night mode')),
              description: Text(ModuStrings.text(
                  context,
                  '根据本机时间自动切换；墨水屏模式下不生效。',
                  'Switch automatically using local time. Unavailable in E-Ink mode.')),
              initialValue: Prefs().scheduledTheme,
              enabled: !Prefs().eInkMode,
              onToggle: (value) async {
                await Prefs().saveThemeSchedule(enabled: value);
                if (mounted) setState(() {});
              },
            ),
            if (Prefs().scheduledTheme)
              SettingsTile.navigation(
                key: const ValueKey('scheduled-theme-hours'),
                title: Text(ModuStrings.text(context, '夜间时段', 'Night hours')),
                value: Text(_nightHours(context)),
                enabled: !Prefs().eInkMode,
                onPressed: _editNightHours,
              ),
            SettingsTile.navigation(
                title: Text(L10n.of(context).settingsAppearanceThemeColor),
                leading: const Icon(Icons.color_lens),
                value: Text(_activeThemeColorLabel(context)),
                description: Text(ModuStrings.text(context, '明暗模式、预设与自定义配色',
                    'Light/dark mode, presets and custom palettes')),
                onPressed: (context) async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ThemeColorsPage()));
                  if (context.mounted) setState(() {});
                }),
            SettingsTile.switchTile(
              title: Text('OLED · ${L10n.of(context).settingsDarkMode}'),
              leading: const Icon(Icons.brightness_2),
              initialValue: Prefs().trueDarkMode,
              onToggle: (bool value) {
                setState(() {
                  Prefs().trueDarkMode = value;
                });
              },
            ),
            SettingsTile.switchTile(
              key: const ValueKey('eink-mode'),
              title: Text(L10n.of(context).eInkMode),
              leading: const Icon(Icons.contrast),
              initialValue: Prefs().eInkMode,
              onToggle: (bool value) {
                setState(() {
                  Prefs().eInkMode = value;
                });
              },
            ),
            SettingsTile.switchTile(
              key: const ValueKey('eink-disable-animations'),
              title: Text(ModuStrings.text(
                  context, '关闭所有动画', 'Disable all animations')),
              description: Text(ModuStrings.text(
                  context,
                  '仅在 E-Ink 模式下生效。关闭后恢复原有动画设置，不改变黑白显示和屏幕刷新设置。',
                  'Only applies in E-Ink mode. Turn off to restore your animation settings without changing monochrome display or screen refresh.')),
              leading: const Icon(Icons.animation),
              initialValue: Prefs().eInkDisableAnimations,
              enabled: Prefs().eInkMode,
              onToggle: Prefs().eInkMode
                  ? (bool value) {
                      setState(() => Prefs().eInkDisableAnimations = value);
                    }
                  : null,
            ),
          ],
        ),
        SettingsSection(
            title: Text(L10n.of(context).settingsAppearanceDisplay),
            tiles: [
              CustomSettingsTile(
                child: ListTile(
                  title: Text(
                      ModuStrings.text(context, '界面布局', 'Interface layout')),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: AnxSegmentedButton<AppLayoutMode>(
                      segments: [
                        SegmentButtonItem(
                          label: ModuStrings.text(context, '自动', 'Auto'),
                          value: AppLayoutMode.auto,
                        ),
                        SegmentButtonItem(
                          label: ModuStrings.text(context, '宽屏版', 'Wide'),
                          value: AppLayoutMode.wide,
                        ),
                        SegmentButtonItem(
                          label: ModuStrings.text(context, '窄屏版', 'Narrow'),
                          value: AppLayoutMode.narrow,
                        ),
                      ],
                      selected: {Prefs().appLayoutMode},
                      onSelectionChanged: (value) {
                        setState(() => Prefs().appLayoutMode = value.first);
                      },
                    ),
                  ),
                ),
              ),
              SettingsTile.navigation(
                  title: Text(L10n.of(context).settingsAppearanceLanguage),
                  value: Text(languageSubtitle),
                  description: Text(ModuStrings.text(
                      context,
                      '界面与内置提示词使用所选语言，用户自定义的提示词保持不变。',
                      'The interface and built-in prompts use this language. Custom prompts remain unchanged.')),
                  leading: const Icon(Icons.language),
                  onPressed: (context) {
                    showLanguagePickerDialog(context);
                  }),
              SettingsTile.switchTile(
                title:
                    Text(L10n.of(context).settingsAppearanceOpenBookAnimation),
                description: Text(ModuStrings.text(
                    context,
                    '控制从书架进入书籍时的滑入、封面过渡和淡出。关闭后直接进入阅读，不影响正文翻页设置。',
                    'Animate opening books from the library. Turn off for instant navigation; page-turn settings are unchanged.')),
                leading: const Icon(Icons.animation),
                initialValue: Prefs().openBookAnimation,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().openBookAnimation = value;
                  });
                },
              ),
              SettingsTile.switchTile(
                title: Text(L10n.of(context).settingsAdvancedAutoHideBottomBar),
                description: Text(ModuStrings.text(context,
                    '仅用于窄窗口的底部导航栏，不影响桌面侧边栏。', '仅用于窄窗口的底部导航栏，不影响桌面侧边栏。')),
                leading: const Icon(Icons.vertical_align_bottom),
                initialValue: Prefs().autoHideBottomBar,
                onToggle: (value) {
                  Prefs().autoHideBottomBar = value;
                  setState(() {});
                },
              ),
              SettingsTile.switchTile(
                title: Text(L10n.of(context).readingPageShowActionLabels),
                leading: const Icon(Icons.subtitles_outlined),
                initialValue: Prefs().showActionLabels,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().showActionLabels = value;
                  });
                },
                description:
                    Text(L10n.of(context).readingPageShowActionLabelsTips),
              ),
            ]),
        SettingsSection(
            title: Text(L10n.of(context).settingsBookshelfCover),
            tiles: [
              CustomSettingsTile(
                  child: ListTile(
                title: Text(L10n.of(context).settingsBookshelfCoverWidth),
                subtitle: Row(
                  children: [
                    Text(Prefs().bookCoverWidth.toStringAsFixed(0)),
                    Expanded(
                      child: Slider(
                        value: Prefs().bookCoverWidth,
                        onChanged: (value) {
                          setState(() {
                            Prefs().bookCoverWidth = value;
                          });
                        },
                        max: 260,
                        min: 80,
                        divisions: 18,
                      ),
                    ),
                  ],
                ),
              )),
              CustomSettingsTile(
                  child: ListTile(
                title: Text(L10n.of(context).settingsBookshelfFolderStyle),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: AnxSegmentedButton<BookshelfFolderStyle>(
                    segments: [
                      SegmentButtonItem(
                        label: L10n.of(context)
                            .settingsBookshelfFolderStyleOverlap,
                        value: BookshelfFolderStyle.stacked,
                        icon: Icon(Icons.layers),
                      ),
                      SegmentButtonItem(
                        label:
                            L10n.of(context).settingsBookshelfFolderStyleGrid,
                        value: BookshelfFolderStyle.grid2x2,
                        icon: Icon(Icons.grid_view),
                      ),
                    ],
                    selected: {Prefs().bookshelfFolderStyle},
                    onSelectionChanged: (value) {
                      setState(() {
                        Prefs().bookshelfFolderStyle = value.first;
                      });
                    },
                  ),
                ),
              )),
              SettingsTile.switchTile(
                title: Text(ModuStrings.text(
                    context, '显示书籍格式标签', 'Show book format labels')),
                description: Text(ModuStrings.text(
                    context,
                    '在书籍封面显示 TXT、EPUB、PDF 等格式。',
                    'Show formats such as TXT, EPUB and PDF on book covers.')),
                leading: const Icon(Icons.label_outline),
                initialValue: Prefs().showBookFormatBadge,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().showBookFormatBadge = value;
                  });
                },
              ),
              SettingsTile.switchTile(
                title: Text(ModuStrings.text(
                    context, '显示已索引标签', 'Show indexed labels')),
                description: Text(ModuStrings.text(
                    context,
                    '显示书籍的已索引标记。关闭不影响索引、索引进度或失败提示。',
                    'Show indexed labels on books. Hiding them keeps indexes, indexing progress and failure notices.')),
                leading: const Icon(Icons.fact_check_outlined),
                initialValue: Prefs().showBookIndexBadge,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().showBookIndexBadge = value;
                  });
                },
              ),
              SettingsTile.switchTile(
                title: Text(
                    L10n.of(context).settingsBookshelfDefaultCoverShowTitle),
                leading: const Icon(Icons.title),
                initialValue: Prefs().showBookTitleOnDefaultCover,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().showBookTitleOnDefaultCover = value;
                  });
                },
              ),
              SettingsTile.switchTile(
                title: Text(
                    L10n.of(context).settingsBookshelfDefaultCoverShowAuthor),
                leading: const Icon(Icons.person),
                initialValue: Prefs().showAuthorOnDefaultCover,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().showAuthorOnDefaultCover = value;
                  });
                },
              ),
              // SettingsTile.switchTile(
              //   title: Text(
              //       L10n.of(context).settingsAdvancedUseOriginalCoverRatio),
              //   leading: const Icon(Icons.photo_size_select_large_outlined),
              //   initialValue: Prefs().useOriginalCoverRatio,
              //   onToggle: (bool value) {
              //     setState(() {
              //       Prefs().useOriginalCoverRatio = value;
              //     });
              //   },
              // ),
            ]),
        SettingsSection(
          title: Text(ModuStrings.text(context, '书籍资料', 'Book information')),
          tiles: [
            SettingsTile.navigation(
              leading: const Icon(Icons.link),
              title: Text(
                  ModuStrings.text(context, '关联微信读书', 'WeRead connection')),
              description: Text(ModuStrings.text(context, '开关、API Key 与书籍资料来源',
                  'Connection, API Key and external book information')),
              onPressed: (context) => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const WereadSettingsPage())),
            ),
          ],
        ),
        SettingsSection(
          title: Text(L10n.of(context).settingsAppearanceBottomNavigatorShow),
          tiles: [
            SettingsTile.switchTile(
              title: Text(switch (localeKey) {
                'zh-CN' => '远程',
                'zh-TW' || 'zh-LZH' => '遠程',
                _ => ModuStrings.text(context, '远程', 'Remote'),
              }),
              initialValue: Prefs().bottomNavigatorShowRemote,
              onToggle: (bool value) {
                setState(() {
                  Prefs().bottomNavigatorShowRemote = value;
                });
              },
            ),
            SettingsTile.switchTile(
              title: Text(switch (localeKey) {
                'zh-CN' => '历史',
                'zh-TW' || 'zh-LZH' => '歷史',
                _ => L10n.of(context).navBarStatistics,
              }),
              initialValue: Prefs().bottomNavigatorShowStatistics,
              onToggle: (bool value) {
                setState(() {
                  Prefs().bottomNavigatorShowStatistics = value;
                });
              },
            ),
            if (EnvVar.enableAIFeature)
              SettingsTile.switchTile(
                title: Text(L10n.of(context).navBarAI),
                initialValue: Prefs().bottomNavigatorShowAI,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().bottomNavigatorShowAI = value;
                  });
                },
              ),
            SettingsTile.switchTile(
              title: Text(L10n.of(context).navBarNotes),
              initialValue: Prefs().bottomNavigatorShowNote,
              onToggle: (bool value) {
                setState(() {
                  Prefs().bottomNavigatorShowNote = value;
                });
              },
            ),
          ],
        ),
      ],
    );
  }
}

void showLanguagePickerDialog(BuildContext context) {
  final title = L10n.of(context).settingsAppearanceLanguage;
  showDialog<void>(
      animationStyle: AppMotion.style,
      context: context,
      builder: (dialogContext) => SimpleDialog(
            key: const ValueKey('app-language-picker'),
            title: Text(title),
            children: languageOptions.map((option) {
              final code = option.values.first;
              return SimpleDialogOption(
                key: ValueKey('app-language-$code'),
                onPressed: () async {
                  await Prefs().saveLocaleToPrefs(code);
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                },
                child: Row(children: [
                  Expanded(
                      child: Text(code == 'System'
                          ? ModuStrings.text(context, '跟随系统', 'Follow system')
                          : option.keys.first)),
                  if (code ==
                      (Prefs().locale == null
                          ? 'System'
                          : appLocaleKey(Prefs().locale!)))
                    const Icon(Icons.check, size: 20),
                ]),
              );
            }).toList(),
          ));
}
