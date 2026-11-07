import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';

/// ZIP library backup is separate from the JSON global-settings transfer.
class DatabaseBackupSection extends AbstractSettingsSection {
  const DatabaseBackupSection({
    super.key,
    required this.onExport,
    required this.onImport,
    this.busy = false,
    this.platform,
  });

  final VoidCallback onExport;
  final VoidCallback onImport;
  final bool busy;
  final AnxPlatformEnum? platform;

  String _saveLocation(BuildContext context) =>
      switch (platform ?? AnxPlatform.type) {
        AnxPlatformEnum.windows => ModuStrings.text(
            context,
            "默认保存在当前用户的 Downloads（下载）文件夹。",
            "Saved in the current user’s Downloads folder by default."),
        AnxPlatformEnum.macos || AnxPlatformEnum.linux => ModuStrings.text(
            context,
            "在系统保存窗口选择文件夹。",
            "Choose a folder in the system save dialog."),
        _ => ModuStrings.text(context, "在系统保存窗口选择“下载”或“文件”中的目录。",
            "Choose a folder in Downloads or Files using the system save dialog."),
      };

  @override
  Widget build(BuildContext context) => SettingsSection(
        title: Text(ModuStrings.text(context, '数据库备份', 'Database backup')),
        tiles: [
          CustomSettingsTile(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingHelp(
                      title: Text(
                          ModuStrings.text(context, "备份内容", "Backup contents")),
                      description: Text(ModuStrings.text(
                          context,
                          "备份本机书籍、笔记、阅读记录和设置，生成 ZIP 文件。",
                          "Create a ZIP backup of local books, notes, reading history and settings."))),
                  const SizedBox(height: 12),
                  SettingHelp(
                      title: Text(
                          ModuStrings.text(context, "保存位置", "Save location")),
                      description: Text(_saveLocation(context))),
                ],
              ),
            ),
          ),
          SettingsTile.navigation(
            key: const ValueKey('database-backup-export'),
            title: Text(
                ModuStrings.text(context, '数据库备份导出', 'Export database backup')),
            description: Text(ModuStrings.text(context, "先下载要备份的书籍，再导出 ZIP 文件。",
                "Download the books you want to back up, then export the ZIP.")),
            leading: const Icon(Icons.upload_file),
            enabled: !busy,
            onPressed: (_) => onExport(),
          ),
          SettingsTile.navigation(
            key: const ValueKey('database-backup-import'),
            title: Text(
                ModuStrings.text(context, '数据库备份导入', 'Import database backup')),
            description: Text(ModuStrings.text(
                context,
                "选择备份 ZIP，输入密码（如有），恢复后重启。恢复会替换当前书库和设置。",
                "Select the backup ZIP and enter its password if needed. Restoring replaces the current library and settings. Restart afterwards.")),
            leading: const Icon(Icons.settings_backup_restore),
            enabled: !busy,
            onPressed: (_) => onImport(),
          ),
        ],
      );
}
