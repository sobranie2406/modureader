import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'dart:io';
import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/book_notes.dart';
import 'package:anx_reader/providers/bookmark.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/providers/sync_database_revision.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/providers/tags.dart';
import 'package:anx_reader/service/local_data/anx_database_import.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/get_path/get_cache_dir.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

class AnxBackupImportPage extends ConsumerStatefulWidget {
  const AnxBackupImportPage({super.key});
  @override
  ConsumerState<AnxBackupImportPage> createState() =>
      _AnxBackupImportPageState();
}

class _AnxBackupImportPageState extends ConsumerState<AnxBackupImportPage> {
  bool _busy = false;
  String? _fileName, _status, _error;
  AnxDatabaseImport? _plan;
  AnxImportResult? _result;
  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';
  String _t(String zh, String en) => _zh ? zh : en;

  @override
  void dispose() {
    _plan?.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        allowMultiple: false,
        withData: false,
      );
      if (picked == null || !mounted) return;
      final path = picked.files.single.path;
      if (path == null) throw const FormatException('无法读取所选文件，请先将 ZIP 保存到本机');
      await _plan?.dispose();
      _plan = null;
      setState(() {
        _result = null;
        _fileName = picked.files.single.name;
        _status = ModuStrings.text(context, '正在检查备份…', 'Checking backup…');
      });
      final plan = await AnxDatabaseImport.prepare(
        cache: await getAnxCacheDir(),
        zip: File(path),
        onProgress: (value) {
          if (mounted) {
            setState(() => _status = _zh ? value : 'Preparing library files…');
          }
        },
      );
      if (!mounted) {
        await plan.dispose();
        return;
      }
      setState(() {
        _plan = plan;
        _status = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  String _message(Object error) {
    if (error is FormatException) return error.message;
    if (error is FileSystemException) {
      return ModuStrings.text(context, '文件读取或写入失败，请检查权限及剩余空间。',
          'File access failed. Check permissions and free disk space.');
    }
    return ModuStrings.text(context, "导入失败，请检查备份文件后重试。",
        "Import failed. Check the backup file and try again.");
  }

  Future<void> _import() async {
    final plan = _plan;
    if (_busy || plan == null || plan.books == 0 || _result != null) return;
    if (ref.read(syncProvider).isSyncing) {
      setState(() => _error = ModuStrings.text(context, '请等待当前同步完成后再导入。',
          'Wait for the current sync to finish before importing.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = ModuStrings.text(context, '正在备份默读数据库并合并书库，请勿关闭应用…',
          'Backing up Modu and merging the library. Keep the app open…');
    });
    try {
      final result = await plan.apply(
          await DBHelper().database, await getAnxDocumentDir());
      // Import has committed. A later UI refresh failure must not report that
      // the import failed or encourage a destructive retry.
      if (mounted) {
        setState(() => _result = result);
        ref.invalidate(bookListProvider);
        ref.invalidate(groupDaoProvider);
        ref.invalidate(bookNotesControllerProvider);
        ref.invalidate(bookmarkProvider);
        ref.invalidate(tagListProvider);
        ref.read(syncDatabaseRevisionProvider.notifier).state++;
      }
    } catch (error) {
      if (mounted && _result == null) setState(() => _error = _message(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final result = _result;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
            title: Text(ModuStrings.text(
                context, '导入 ANX Reader 的备份文件', 'Import ANX Reader backup'))),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          SettingHelp(
              title: Text(ModuStrings.text(context, "导入步骤", "Import steps")),
              description: Text(ModuStrings.text(
                  context,
                  "在 ANX 下载书籍并导出 ZIP 备份，在此选择备份后开始导入。",
                  "Download your books in ANX and export a ZIP backup, then select it here to import."))),
          const SizedBox(height: 20),
          SettingHelp(
              title: Text(ModuStrings.text(context, "导入内容", "Import contents")),
              description: Text(ModuStrings.text(
                  context,
                  "导入书籍、笔记和阅读记录。请先在 ANX 下载需要迁移的书籍。",
                  "Import books, notes and reading history. Download the books in ANX first."))),
          const SizedBox(height: 20),
          OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.file_open_outlined),
              label: Text(ModuStrings.text(
                  context, '选择 ANX 备份 ZIP', 'Select ANX backup ZIP'))),
          if (_fileName != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_fileName!)),
          if (_busy) ...[
            const EinkStaticIndicator(child: LinearProgressIndicator()),
            const SizedBox(height: 8),
            Text(_status ?? ModuStrings.text(context, '正在处理…', 'Working…'))
          ],
          if (_error != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          if (plan != null && !_busy) ...[
            const Divider(),
            Text(_t('识别到 ${plan.books} 本可导入书籍、${plan.notes} 条笔记。',
                '${plan.books} readable books and ${plan.notes} notes found.')),
            if (plan.skippedDeleted > 0)
              Text(_t('跳过 ${plan.skippedDeleted} 本已删除书籍。',
                  'Excluded ${plan.skippedDeleted} deleted books.')),
            if (plan.missingBooks.isNotEmpty) ...[
              Text(_t('以下 ${plan.missingBooks.length} 本缺少正文文件，将连同其笔记和记录跳过：',
                  'These ${plan.missingBooks.length} books lack their files; their notes/history will also be skipped:')),
              SelectableText(plan.missingBooks.join('\n')),
            ],
            if (result == null)
              FilledButton.icon(
                  onPressed: plan.books == 0 ? null : _import,
                  icon: const Icon(Icons.library_add),
                  label:
                      Text(ModuStrings.text(context, '开始导入', 'Start import'))),
          ],
          if (result != null) ...[
            const Divider(),
            Text(_t(
                '导入完成：新增 ${result.addedBooks} 本书、${result.addedNotes} 条笔记。相同记录已跳过。',
                'Import complete: ${result.addedBooks} books and ${result.addedNotes} notes added. Existing records were retained.')),
            const SizedBox(height: 8),
            Text(ModuStrings.text(
                context, '导入前数据库备份位置：', 'Pre-import database backup:')),
            SelectableText(p.normalize(result.backupPath)),
          ],
        ]),
      ),
    );
  }
}
