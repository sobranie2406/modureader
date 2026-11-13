import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/page/settings_page/css_settings.dart';
import 'package:modu_reader/page/settings_page/settings_page.dart';
import 'package:modu_reader/widgets/settings/settings_tile.dart';
import 'package:modu_reader/widgets/reading_page/more_settings/other_settings.dart';
import 'package:modu_reader/widgets/reading_page/more_settings/reading_settings.dart';
import 'package:modu_reader/widgets/reading_page/more_settings/style_settings.dart';
import 'package:modu_reader/widgets/settings/settings_section.dart';
import 'package:modu_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';
import 'package:modu_reader/widgets/settings/reader_popup_height_tile.dart';
import 'package:modu_reader/widgets/settings/reader_menu_opacity_tile.dart';
import 'package:modu_reader/widgets/reading_page/reader_top_actions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReadingSettings extends ConsumerStatefulWidget {
  const ReadingSettings({super.key});

  @override
  ConsumerState<ReadingSettings> createState() => _ReadingSettingsState();
}

class _ReadingSettingsState extends ConsumerState<ReadingSettings> {
  @override
  Widget build(BuildContext context) {
    CustomSettingsSection section(String title, Widget child) =>
        CustomSettingsSection(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SettingsSectionTitle(child: Text(title)),
            child,
          ]),
        );
    return settingsSections(sections: [
      SettingsSection(
        title: Text(ModuStrings.text(context, '添加书籍', 'Add books')),
        tiles: [
          SettingsTile.switchTile(
            initialValue: Prefs().inPlaceImportEnabled,
            onToggle: (value) =>
                setState(() => Prefs().inPlaceImportEnabled = value),
            title:
                Text(ModuStrings.text(context, '原位添加书籍', 'Add books in place')),
            description: Text(ModuStrings.text(context, '加号读取原文件；拖入仍保存副本。',
                'The add button links originals; dropping files imports copies.')),
          ),
          SettingsTile.navigation(
            title: Text(
                ModuStrings.text(context, '默认打开书籍', 'Open books by default')),
            onPressed: (context) => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(ModuStrings.text(
                    context, '默认打开书籍', 'Open books by default')),
                content: Text(ModuStrings.text(
                    context,
                    Platform.isIOS
                        ? '在文件中选择书籍，点“共享”或“打开方式”，选择默读。'
                        : '在系统文件管理器中选择书籍，将打开方式设为默读。外部打开会导入副本；要原位读取，请在默读中点加号选择原文件。',
                    'Choose Modu from the file manager’s Open with menu. External opening imports a copy; use the add button in Modu to link an original.')),
                actions: [
                  if (Platform.isAndroid)
                    TextButton(
                        onPressed: () async {
                          await openAppSettings();
                        },
                        child: Text(
                            ModuStrings.text(context, '应用设置', 'App settings'))),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(ModuStrings.text(context, '知道了', 'OK'))),
                ],
              ),
            ),
          )
        ],
      ),
      SettingsSection.content(
        title: Text(ModuStrings.text(context, '阅读弹出菜单', 'Reader popups')),
        child: const Column(
            children: [ReaderPopupHeightTile(), ReaderMenuOpacityTile()]),
      ),
      SettingsSection.content(
        title: Text(ModuStrings.text(context, '阅读顶部菜单', 'Reader top toolbar')),
        child: const ReaderTopActionsSettings(),
      ),
      SettingsSection(
        title: Text(ModuStrings.text(context, 'CSS 设置', 'CSS settings')),
        tiles: [
          SettingsTile.navigation(
            key: const ValueKey('reading-css-settings'),
            leading: const Icon(Icons.tune),
            title: Text(ModuStrings.text(context, 'CSS 设置', 'CSS settings')),
            description: Text(ModuStrings.text(context, '预设模板 · 图形调节 · 自定义代码',
                'Templates · Visual controls · Custom code')),
            onPressed: (context) =>
                Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SettingsPageBody(
                title: ModuStrings.text(context, 'CSS 设置', 'CSS settings'),
                isMobile: true,
                sections: const CssSettings(),
              ),
            )),
          ),
        ],
      ),
      section(L10n.of(context).readingPageReading,
          const ReadingMoreSettings(readerMenu: true)),
      section(L10n.of(context).readingPageStyle,
          const StyleSettings(readerMenu: true)),
      section(L10n.of(context).readingPageOther,
          const OtherSettings(readerMenu: true, showKeyboardShortcuts: true)),
    ]);
  }
}
