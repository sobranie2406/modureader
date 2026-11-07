import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'dart:io';
import 'dart:math';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/providers/storage_info.dart';

import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/get_path/storage_migration.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/widgets/common/anx_button.dart';
import 'package:anx_reader/widgets/delete_confirm.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StorageSettings extends ConsumerStatefulWidget {
  const StorageSettings({super.key});

  @override
  ConsumerState<StorageSettings> createState() => _StorageSettingsState();
}

class _StorageSettingsState extends ConsumerState<StorageSettings>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Custom storage location state
  String? _selectedNewPath;
  bool _isMigrating = false;
  String? _currentStoragePath;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadCurrentPath();
  }

  Future<void> _loadCurrentPath() async {
    final path = await getAnxDocumentsPath();
    if (mounted) {
      setState(() {
        _currentStoragePath = path;
        _selectedNewPath = Prefs().prefs.getString('pendingStorageMigration');
      });
      final result = Prefs().prefs.getBool('storageMigrationSucceeded');
      if (result != null) {
        await Prefs().prefs.remove('storageMigrationSucceeded');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result
                ? L10n.of(context).storageMigrationSuccess
                : L10n.of(context).storageMigrationFailed)));
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _selectNewPath() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null) return;

    // Check if directory is empty
    final isEmpty = await isDirectoryEmpty(result);
    if (!isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.of(context).storagePathNotEmpty),
            backgroundColor:
                Theme.of(context).colorScheme.error.withValues(alpha: .5),
          ),
        );
      }
      return;
    }

    // Check write permission by creating a test file
    try {
      final testFile =
          File('$result${Platform.pathSeparator}.modu_permission_test');
      await testFile.writeAsString('test');
      await testFile.delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.of(context).storagePathNoPermission),
            backgroundColor:
                Theme.of(context).colorScheme.error.withValues(alpha: .5),
          ),
        );
      }
      return;
    }

    setState(() {
      _selectedNewPath = result;
    });
  }

  Future<void> _startMigration() async {
    if (_selectedNewPath == null ||
        _currentStoragePath == null ||
        _isMigrating) {
      return;
    }
    setState(() => _isMigrating = true);
    try {
      if (!await isDirectoryEmpty(_selectedNewPath!)) {
        throw const FileSystemException('Destination is not empty');
      }
      final saved = await Prefs()
          .prefs
          .setString('pendingStorageMigration', _selectedNewPath!);
      if (!saved) {
        throw const FileSystemException('Cannot save migration request');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ModuStrings.text(context, "请退出并重新打开默读，完成迁移。",
              "Quit and reopen Modu to finish moving your data."))));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(L10n.of(context).storageMigrationFailed)));
      }
    } finally {
      if (mounted) setState(() => _isMigrating = false);
    }
  }

  Future<void> _resetToDefaultPath() async {
    final defaultPath = await getDefaultStoragePath();
    if (_currentStoragePath == defaultPath) return;
    setState(() {
      _selectedNewPath = defaultPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    final storageInfoAsync = ref.watch(storageInfoProvider);

    Widget fileSizeTriling(String? size) {
      if (size == null) {
        return const CircularProgressIndicator.adaptive();
      }
      return Text(
        size,
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    Widget cacheSizeTriling(String? size) {
      if (size == null) {
        return const CircularProgressIndicator.adaptive();
      }
      return ElevatedButton(
        onPressed: () async {
          final confirmed = await showDialog<bool>(
              animationStyle: AppMotion.style,
              context: context,
              builder: (context) => AlertDialog(
                    title:
                        Text(ModuStrings.text(context, '清理缓存', 'Clear cache')),
                    content: Text(ModuStrings.text(
                        context,
                        "清理临时文件？请先等待导入、同步和下载完成。",
                        "Clear temporary files? Wait for imports, sync and downloads to finish first.")),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child:
                              Text(ModuStrings.text(context, '取消', 'Cancel'))),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(ModuStrings.text(context, '清理', 'Clear')))
                    ],
                  ));
          if (confirmed != true || !mounted) return;
          final success =
              await ref.read(storageInfoProvider.notifier).clearCache();
          if (!success && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ModuStrings.text(context, '清理失败，已保留尚未迁移的数据。',
                    'Cache clearing failed. Data awaiting migration was kept.'))));
          }
          ref.invalidate(storageInfoProvider);
        },
        child: Text('${L10n.of(context).storageClearCache} $size'),
      );
    }

    return settingsSections(sections: [
      SettingsSection(
        title: Text(L10n.of(context).storageInfo),
        tiles: [
          CustomSettingsTile(
            child: Column(
              children: [
                ListTile(
                  title: Text(L10n.of(context).storageTotalSize),
                  trailing:
                      fileSizeTriling(storageInfoAsync.value?.totalSizeStr),
                ),
                ListTile(
                  title: Text(L10n.of(context).storageDatabaseFile),
                  trailing:
                      fileSizeTriling(storageInfoAsync.value?.databaseSizeStr),
                ),
                ListTile(
                  title: Text(L10n.of(context).storageLogFile),
                  trailing: fileSizeTriling(storageInfoAsync.value?.logSizeStr),
                ),
                Column(
                  children: [
                    ListTile(
                      title: Text(
                          ModuStrings.text(context, '本地模型', 'Local models')),
                      trailing: fileSizeTriling(
                          storageInfoAsync.value?.localModelsSizeStr),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 20.0),
                      child: Column(
                        children: [
                          ListTile(
                            title: Text(ModuStrings.text(
                                context, '向量模型', 'Vector model')),
                            trailing: fileSizeTriling(
                                storageInfoAsync.value?.modelSizeStr),
                          ),
                          ListTile(
                            title: Text(ModuStrings.text(
                                context, 'OCR 模型', 'OCR model')),
                            trailing: fileSizeTriling(
                                storageInfoAsync.value?.ocrModelSizeStr),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                for (final item in [
                  (
                    '书籍向量索引',
                    'Book vector index',
                    storageInfoAsync.value?.indexSize
                  ),
                  (
                    'AI 对话历史',
                    'AI chat history',
                    storageInfoAsync.value?.aiHistorySize
                  ),
                  (
                    '阅读背景',
                    'Reading backgrounds',
                    storageInfoAsync.value?.backgroundSize
                  ),
                ])
                  ListTile(
                    title: Text(ModuStrings.text(context, item.$1, item.$2)),
                    trailing: fileSizeTriling(item.$3 == null
                        ? null
                        : storageInfoAsync.value!.formatSize(item.$3!)),
                  ),
                ListTile(
                  title: Text(L10n.of(context).storageCacheFile),
                  trailing:
                      cacheSizeTriling(storageInfoAsync.value?.cacheSizeStr),
                ),
                Column(
                  children: [
                    ListTile(
                      title: Text(L10n.of(context).storageDataFile),
                      trailing: fileSizeTriling(
                          storageInfoAsync.value?.dataFilesSizeStr),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 20.0),
                      child: Column(
                        children: [
                          ListTile(
                            title: Text(L10n.of(context).storageBookFile),
                            trailing: fileSizeTriling(
                                storageInfoAsync.value?.booksSizeStr),
                          ),
                          ListTile(
                            title: Text(L10n.of(context).storageCoverFile),
                            trailing: fileSizeTriling(
                                storageInfoAsync.value?.coverSizeStr),
                          ),
                          ListTile(
                            title: Text(L10n.of(context).storageFontFile),
                            trailing: fileSizeTriling(
                                storageInfoAsync.value?.fontSizeStr),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),

      if (AnxPlatform.isAndroid)
        SettingsSection(
          title: Text(ModuStrings.text(context, '存储位置', 'Storage location')),
          tiles: [
            CustomSettingsTile(
                child: ListTile(
              title: SettingHelp(
                  title: Text(ModuStrings.text(
                      context, '应用数据目录', 'App data directory')),
                  description: SettingHelp(
                      title: Text(
                          ModuStrings.text(context, "数据目录", "Data folder")),
                      description: Text(
                          '${_currentStoragePath ?? "..."}\n${ModuStrings.text(context, "书籍及应用数据保存在此目录，卸载前请备份。", "Books and app data are stored here. Back up before uninstalling.")}'))),
            )),
          ],
        ),

      // Custom storage location (Windows only)
      if (AnxPlatform.isWindows)
        SettingsSection(
          title: Text(L10n.of(context).storageCustomLocation),
          tiles: [
            CustomSettingsTile(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current storage path
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(ModuStrings.text(context, "选择空文件夹，重启默读后开始迁移。",
                        "Choose an empty folder, then restart Modu to move your data.")),
                  ),
                  ListTile(
                    title: Text(L10n.of(context).storageCurrentPath),
                    subtitle: Text(
                      _currentStoragePath ?? '...',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  // Selected new path (if any)
                  if (_selectedNewPath != null) ...[
                    ListTile(
                      title: Text(L10n.of(context).storageNewPath),
                      subtitle: Text(
                        _selectedNewPath!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () async {
                          await Prefs().prefs.remove('pendingStorageMigration');
                          if (!mounted) return;
                          setState(() {
                            _selectedNewPath = null;
                          });
                        },
                      ),
                    ),
                  ],
                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        if (_selectedNewPath == null)
                          Expanded(
                            child: AnxButton(
                              onPressed: _selectNewPath,
                              child: Text(L10n.of(context).storageSelectPath),
                            ),
                          )
                        else
                          Expanded(
                            child: AnxButton(
                              onPressed: _isMigrating ? null : _startMigration,
                              isLoading: _isMigrating,
                              child: Text(L10n.of(context).storageMigrateData),
                            ),
                          ),
                        const SizedBox(width: 8),
                        if (Prefs().customStoragePath != null &&
                            _selectedNewPath == null)
                          AnxButton.outlined(
                            onPressed:
                                _isMigrating ? null : _resetToDefaultPath,
                            child: Text(L10n.of(context).storageResetPath),
                          ),
                      ],
                    ),
                  ),
                  // Migration progress
                  if (_isMigrating) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        children: [
                          const EinkStaticIndicator(
                              child: LinearProgressIndicator()),
                          const SizedBox(height: 8),
                          Text(
                            L10n.of(context).migrationPreparing,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),

      // Tab view for data files details
      SettingsSection(
          title: Text(L10n.of(context).storageDataFileDetails),
          tiles: [
            CustomSettingsTile(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TabBar(
                      controller: _tabController,
                      tabs: [
                        Tab(
                            text: L10n.of(context).storageBookFile,
                            icon: const Icon(Icons.book)),
                        Tab(
                            text: L10n.of(context).storageCoverFile,
                            icon: const Icon(Icons.image)),
                        Tab(
                            text: L10n.of(context).storageFontFile,
                            icon: const Icon(Icons.font_download)),
                      ],
                    ),
                    SizedBox(
                      height: MediaQuery.of(context).size.height -
                          MediaQuery.of(context).padding.top -
                          MediaQuery.of(context).padding.bottom -
                          kToolbarHeight -
                          140,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // Books tab
                          storageInfoAsync.when(
                            data: (_) => DataFilesDetailTab(
                              title: L10n.of(context).storageBookFile,
                              icon: Icons.book,
                              listFiles: ref
                                  .read(storageInfoProvider.notifier)
                                  .listBookFiles(),
                              showDelete: false,
                              ref: ref,
                            ),
                            loading: () => const Center(
                                child: CircularProgressIndicator.adaptive()),
                            error: (_, __) => Center(
                                child: Text(L10n.of(context).commonError)),
                          ),
                          // Covers tab
                          storageInfoAsync.when(
                            data: (_) => DataFilesDetailTab(
                              title: L10n.of(context).storageCoverFile,
                              icon: Icons.image,
                              listFiles: ref
                                  .read(storageInfoProvider.notifier)
                                  .listCoverFiles(),
                              showDelete: false,
                              ref: ref,
                            ),
                            loading: () => const Center(
                                child: CircularProgressIndicator.adaptive()),
                            error: (_, __) => Center(
                                child: Text(L10n.of(context).commonError)),
                          ),
                          // Fonts tab
                          storageInfoAsync.when(
                            data: (_) => DataFilesDetailTab(
                              title: L10n.of(context).storageFontFile,
                              icon: Icons.font_download,
                              listFiles: ref
                                  .read(storageInfoProvider.notifier)
                                  .listFontFiles(),
                              showDelete: true,
                              ref: ref,
                            ),
                            loading: () => const Center(
                                child: CircularProgressIndicator.adaptive()),
                            error: (_, __) => Center(
                                child: Text(L10n.of(context).commonError)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ])
    ]);
  }
}

// Tab content for data files details
class DataFilesDetailTab extends StatelessWidget {
  final String title;
  final IconData icon;
  final Future<List<File>> listFiles;
  final bool showDelete;
  final WidgetRef ref;

  const DataFilesDetailTab({
    super.key,
    required this.title,
    required this.icon,
    required this.listFiles,
    this.showDelete = false,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    String formatSize(int bytes) {
      if (bytes <= 0) return '0 B';

      const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
      var i = (log(bytes) / log(1024)).floor();
      return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
    }

    Widget fileSizeWidget(File file) {
      return FutureBuilder<int>(
        future: file.length(),
        builder: (context, snapshot) {
          return Text(formatSize(snapshot.data ?? 0));
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: FutureBuilder<List<File>>(
            future: listFiles,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final files = snapshot.data!;
                files.sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
                return ListView.builder(
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return ListTile(
                      title: Text(file.path.split(Platform.pathSeparator).last),
                      subtitle: showDelete ? fileSizeWidget(file) : null,
                      trailing: showDelete
                          ? file.path.endsWith('SourceHanSerifSC-Regular.otf')
                              ? null
                              : DeleteConfirm(
                                  delete: () {
                                    snapshot.data!.remove(file);
                                    ref
                                        .read(storageInfoProvider.notifier)
                                        .deleteFile(file);
                                  },
                                  deleteIcon: const Icon(Icons.delete),
                                  confirmIcon: const Icon(Icons.check),
                                )
                          : fileSizeWidget(file),
                    );
                  },
                );
              }
              return const Center(child: CircularProgressIndicator.adaptive());
            },
          ),
        ),
      ],
    );
  }
}
