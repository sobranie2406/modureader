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
            r'默认保存位置：Windows 当前用户的 Downloads（下载）文件夹，通常为 C:\Users\<用户名>\Downloads。导出后显示实际完整位置，可复制。',
            r'Default location: the current Windows user’s Downloads folder, usually C:\Users\<username>\Downloads. Export shows the actual full location with a copy action.'),
        AnxPlatformEnum.macos || AnxPlatformEnum.linux => ModuStrings.text(
            context,
            '保存位置：在系统保存窗口选择目录，没有固定的自动保存目录。导出后显示实际完整路径，可复制。',
            'Save location: choose a folder in the system save dialog; there is no fixed automatic destination. Export shows the actual full path with a copy action.'),
        _ => ModuStrings.text(
            context,
            '保存位置：在系统保存窗口选择“下载”或“文件”中的目录，以所选位置为准。导出后显示文件名或完整路径，便于查找。',
            'Save location: choose a folder in Downloads or Files using the system save dialog. Export shows the file name or full path to help you find it.'),
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
                  Text(ModuStrings.text(
                      context,
                      '这是 ZIP 数据库备份包，包含书库数据库、笔记/高亮、书签、阅读记录、文件夹/标签，以及本机已有的书籍、封面、字体、背景图片、AI 对话历史和一般设置；不是仅导出数据库文件，也不同于“全局设置备份”的 JSON 文件。',
                      'This ZIP database backup contains the library database, notes/highlights, bookmarks, reading records, folders/tags, local books, covers, fonts, background images, AI chat history and general settings. It is more than a database file and is separate from the JSON Global settings backup.')),
                  const SizedBox(height: 12),
                  SelectableText(_saveLocation(context)),
                ],
              ),
            ),
          ),
          SettingsTile.navigation(
            key: const ValueKey('database-backup-export'),
            title: Text(
                ModuStrings.text(context, '数据库备份导出', 'Export database backup')),
            description: Text(ModuStrings.text(
                context,
                '导出：选择是否加密包含服务配置与凭据 → 生成 Modu-Backup-*.zip → 保存。仅包含本机已有文件，请先下载需要迁移的书籍。',
                'Export: choose whether to include encrypted service settings and credentials → create Modu-Backup-*.zip → save. Only local files are included; download books you want to transfer first.')),
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
                '导入：选择本功能导出的 ZIP（无需解压）→ 确认覆盖并校验 → 若设置加密，输入导出时的密码 → 完成后重启默读。会替换现有书库、笔记和备份中的设置，不会合并，建议先导出当前数据。',
                'Import: select a ZIP exported here (no extraction needed) → confirm replacement and validate → enter the export password if settings are encrypted → restart Modu. This replaces the current library, notes and backed-up settings; it does not merge. Export your current data first.')),
            leading: const Icon(Icons.settings_backup_restore),
            enabled: !busy,
            onPressed: (_) => onImport(),
          ),
        ],
      );
}
