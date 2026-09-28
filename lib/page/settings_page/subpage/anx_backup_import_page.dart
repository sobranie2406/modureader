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
        _status = _t('正在检查备份…', 'Checking backup…');
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
      return _t('文件读取或写入失败，请检查权限及剩余空间。',
          'File access failed. Check permissions and free disk space.');
    }
    return _t('导入未完成，现有数据库未被替换。请确认备份完整、版本兼容后重试。',
        'Import did not complete. Your database was not replaced. Check backup integrity and version compatibility.');
  }

  Future<void> _import() async {
    final plan = _plan;
    if (_busy || plan == null || plan.books == 0 || _result != null) return;
    if (ref.read(syncProvider).isSyncing) {
      setState(() => _error = _t('请等待当前同步完成后再导入。',
          'Wait for the current sync to finish before importing.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = _t('正在备份默读数据库并合并书库，请勿关闭应用…',
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
            title: Text(_t('导入 ANX Reader 的备份文件', 'Import ANX Reader backup'))),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Text(_t('操作步骤', 'Steps'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(_t(
              '1. 在 ANX Reader 中下载需要迁移的书籍。\n2. 打开 ANX Reader「设置 → 同步 → 导出与导入 → 导出」，保存 ZIP 备份（不同版本菜单名称可能略有差异）。\n3. 将 ZIP 保存到当前设备，不要解压或修改文件。\n4. 在此选择备份，检查识别结果后点击「开始导入」。',
              '1. Download the books to migrate in ANX Reader.\n2. In ANX Reader, open Settings → Sync → Export and Import → Export, and save the ZIP backup (menu labels may vary).\n3. Save the ZIP on this device; do not extract or modify it.\n4. Select the backup here, review the results and start importing.')),
          const SizedBox(height: 20),
          Text(_t('导入范围与限制', 'Scope and limitations'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(_t(
              '• 导入书籍文件、封面、笔记/高亮、阅读进度、阅读时长、文件夹和标签。\n• 不导入 ANX 的账号、密码、API 密钥、同步配置、AI 聊天记录、字体、主题或其他应用设置。\n• 仅支持原版 ANX ZIP 备份，内部数据库版本为 7（不是 ANX 应用版本号）；不接受单独的 DB、加密 ZIP 或修改版数据库。\n• 已删除书籍不导入；备份缺少正文文件的书籍及其笔记、记录会跳过，并显示书名。请在 ANX 下载完整后重新备份。\n• 相同文件内容识别为同一本书，保留默读已有进度、笔记修改和文件夹安排。重复导入同一备份不会重复创建同一记录，不会用旧备份覆盖已有数据。\n• 不改动原 ZIP，不直接访问 ANX 私有目录。导入前自动备份默读数据库，完成后显示备份位置。\n• 请预留足够空间用于解压、文件复制及数据库备份；准备阶段只校验，不会替换现有书库。',
              '• Imports book files, covers, notes/highlights, reading position/time, folders and tags.\n• Does not import accounts, passwords, API keys, sync configuration, AI chats, fonts, themes or other app settings.\n• Supports original ANX ZIP backups with database schema version 7 (not the app version). Standalone DBs, encrypted ZIPs and modified databases are not supported.\n• Deleted books are excluded. Books without their actual files, and their notes/history, are skipped and listed. Download them in ANX and export again.\n• Identical contents are deduplicated. Existing Modu positions, note edits and folder assignments are preserved. Reimporting the same backup does not recreate the same records or overwrite existing data.\n• The ZIP is unchanged; ANX private storage is never accessed. A local Modu database backup is created before importing, with its location shown afterwards.\n• Allow space for extraction, copies and the database backup. Preparation only validates the backup.')),
          const SizedBox(height: 20),
          ExpansionTile(
            title: Text(_t('文件大小与兼容限制', 'Size and compatibility limits')),
            children: [
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_t(
                      'ZIP 最多 10 万个条目，展开后不超过 20 GiB；数据库及 WAL 各不超过 256 MiB，每张数据表最多 20 万行。旧系统若不支持安全数据库快照，会终止导入。备份可能包含敏感设置，请妥善保管。',
                      'Maximum 100,000 ZIP entries and 20 GiB expanded; database/WAL each up to 256 MiB, up to 200,000 rows per table. Import stops if an older system cannot create a safe database snapshot. Backups may contain sensitive settings; store them securely.')))
            ],
          ),
          OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.file_open_outlined),
              label: Text(_t('选择 ANX 备份 ZIP', 'Select ANX backup ZIP'))),
          if (_fileName != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_fileName!)),
          if (_busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(_status ?? _t('正在处理…', 'Working…'))
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
                  label: Text(_t('开始导入', 'Start import'))),
          ],
          if (result != null) ...[
            const Divider(),
            Text(_t(
                '导入完成：新增 ${result.addedBooks} 本书、${result.addedNotes} 条笔记。相同记录已跳过。',
                'Import complete: ${result.addedBooks} books and ${result.addedNotes} notes added. Existing records were retained.')),
            const SizedBox(height: 8),
            Text(_t('导入前数据库备份位置：', 'Pre-import database backup:')),
            SelectableText(p.normalize(result.backupPath)),
          ],
        ]),
      ),
    );
  }
}
