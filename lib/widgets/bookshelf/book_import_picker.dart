import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/book_local_sources.dart';
import 'package:anx_reader/service/receive_file/external_book_inbox.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'dart:io';
import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/service/ios_linked_books.dart';
import 'package:anx_reader/service/md5_service.dart';

import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/service/book_import_source.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// One acquisition/selection flow at a time, including drops on a reading page.
bool _pickingBooks = false;

Future<void> pickBooksForImport(BuildContext context, WidgetRef ref,
    {bool folder = false,
    bool? inPlace,
    Book? relinkBook,
    List<String>? droppedPaths}) async {
  final useInPlace =
      droppedPaths == null && (inPlace ?? Prefs().inPlaceImportEnabled);
  if (_pickingBooks) return;
  _pickingBooks = true;
  final mobileFolder = folder && (Platform.isAndroid || Platform.isIOS);
  try {
    if (droppedPaths != null) {
      final entries = await discoverBookImportFiles(droppedPaths);
      externalBookInbox.add(entries.map((entry) => entry.id));
      return;
    }

    List<BookImportEntry>? entries;
    if (useInPlace && !(Platform.isWindows || Platform.isLinux)) {
      entries = await _withImportProgress(
          context,
          () => MobileBookFolder.pick(
              files: !folder,
              inPlace: true,
              extensions: IosLinkedBooks.extensions));
    } else if (mobileFolder) {
      entries = await _withImportProgress(context, MobileBookFolder.pick);
    } else if (folder) {
      final path = await FilePicker.platform.getDirectoryPath();
      if (path == null || !context.mounted) return;
      entries = await _withImportProgress(
          context, () => discoverBookImportFiles([path]));
    } else {
      final picked = await FilePicker.platform.pickFiles(
        // Mobile providers may not register MIME/UTI types for AZW3/FB2/MD.
        // Filter the returned names instead of hiding valid books in the picker.
        type: Platform.isAndroid || Platform.isIOS
            ? FileType.any
            : FileType.custom,
        allowedExtensions:
            Platform.isAndroid || Platform.isIOS ? null : allowBookExtensions,
        allowMultiple: true,
      );
      if (picked == null || !context.mounted) return;
      if (picked.files.any((e) => e.path == null)) {
        throw const FileSystemException(
            'Selected file is not available locally');
      }
      entries = await _withImportProgress(
          context,
          () => discoverBookImportFiles(
              picked.files.map((e) => e.path!).toList()));
    }
    if (entries == null || !context.mounted) return;
    if (useInPlace) {
      entries = entries
          .where((entry) => IosLinkedBooks.extensions
              .contains(entry.name.split('.').last.toLowerCase()))
          .toList();
      if (BookSources.store == null) {
        throw StateError('Local source storage unavailable');
      }
    }
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ModuStrings.text(
              context,
              useInPlace
                  ? '原位添加支持 EPUB、PDF、MOBI、AZW3、FB2；其他格式请用普通导入。'
                  : '没有找到支持的书籍文件',
              useInPlace
                  ? 'In-place reading supports EPUB, PDF, MOBI, AZW3 and FB2. Use normal import for other formats.'
                  : 'No supported books found'))));
      return;
    }
    final selected = await showDialog<List<BookImportEntry>>(
      animationStyle: AppMotion.style,
      context: context,
      builder: (_) =>
          BookImportSelection(entries: entries!, inPlace: useInPlace),
    );
    if (selected == null || selected.isEmpty || !context.mounted) return;
    if (relinkBook != null && selected.length != 1) {
      throw const FileSystemException('Select one matching original');
    }
    if (useInPlace) {
      var failed = 0;
      await _withImportProgress(context, () async {
        for (final entry in selected) {
          String? key;
          try {
            final desktop = Platform.isWindows || Platform.isLinux;
            if (desktop) {
              key =
                  'file/linked-${DateTime.now().microsecondsSinceEpoch}.${entry.name.split('.').last.toLowerCase()}';
              IosLinkedBooks.registerPath(key, entry.id);
            } else {
              key = await IosLinkedBooks.link(entry.id);
            }
            final file = File(IosLinkedBooks.resolve(key)!);
            final md5 = await MD5Service.calculateFileMd5(file.path);
            if (md5 == null) {
              throw const FileSystemException('Cannot verify book');
            }
            if (relinkBook != null &&
                md5.toLowerCase() != relinkBook.md5?.toLowerCase()) {
              throw const FileSystemException(
                  'Selected file does not match this book');
            }
            final existing = relinkBook ?? await bookDao.getBookByMd5(md5);
            if (existing != null && !existing.isDeleted) {
              if (!context.mounted) break;
              final replace = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                        title: Text(ModuStrings.text(
                            context, '关联已有书籍', 'Link existing book')),
                        content: Text(ModuStrings.text(
                            context,
                            '改为从所选原文件读取？笔记和进度保留。',
                            'Read from the selected original? Notes and progress are kept.')),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(
                                  ModuStrings.text(context, '跳过', 'Skip'))),
                          TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child:
                                  Text(ModuStrings.text(context, '关联', 'Link')))
                        ],
                      ));
              if (replace != true) continue;
              final previous = BookSources.store!
                      .read(existing.md5, existing.filePath)?['locator'] ??
                  existing.filePath;
              await BookSources.store!.save(existing.md5, existing.filePath,
                  kind: 'linked', locator: desktop ? file.path : key);
              // The old internal copy is retained until an explicit cleanup;
              // switching sources never removes the only verified copy.
              key = null;
              if (IosLinkedBooks.isLinked(previous)) {
                await IosLinkedBooks.forget(previous);
              }
              continue;
            }
            await getBookMetadata(file,
                md5: md5,
                linkedPath: key,
                sourceName: entry.name,
                sourceFormat: entry.name.split('.').last.toLowerCase());
            key = null; // The saved book now owns this bookmark.
          } catch (_) {
            failed++;
          } finally {
            if (key != null &&
                !(await bookDao.getCurrentBooks()).contains(key)) {
              await IosLinkedBooks.forget(key);
            }
          }
        }
        await ref.read(bookListProvider.notifier).refresh();
        ref.invalidate(syncStatusProvider);
      });
      if (failed > 0 && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ModuStrings.format(
                context,
                '{count} 本书未能添加，请检查文件和授权后重试。',
                '{count} books could not be added. Check files and access, then retry.',
                values: {'count': failed}))));
      }
      return;
    }
    final files = await _withImportProgress(
        context,
        () async => mobileFolder
            ? await MobileBookFolder.stage(selected)
            : await stageBookImportFiles(selected, await getAnxTempDir()));
    if (!context.mounted) {
      for (final file in files) {
        if (await file.exists()) await file.delete();
      }
      return;
    }
    importBookList(files, context, ref);
  } catch (error, stack) {
    if (droppedPaths != null) {
      AnxLog.severe('Dropped book import failed: $error\n$stack');
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ModuStrings.text(
              context,
              '无法读取所选文件或文件夹，请检查访问权限及文件是否已下载到本机后重试。',
              'Unable to read the selection. Check access and download cloud files locally, then try again.'))));
    }
  } finally {
    try {
      if (mobileFolder ||
          (useInPlace && !(Platform.isWindows || Platform.isLinux))) {
        await MobileBookFolder.release();
      }
    } finally {
      _pickingBooks = false;
    }
  }
}

Future<T> _withImportProgress<T>(
    BuildContext context, Future<T> Function() work) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(children: [
              const EinkStaticIndicator(child: CircularProgressIndicator()),
              const SizedBox(width: 20),
              Expanded(
                  child: Text(
                      ModuStrings.text(context, '正在准备书籍…', 'Preparing books…')))
            ]),
          )));
  navigator.push(route);
  try {
    return await work();
  } finally {
    if (route.isActive) navigator.removeRoute(route);
  }
}

class BookImportSelection extends StatefulWidget {
  const BookImportSelection(
      {super.key, required this.entries, this.inPlace = false});
  final List<BookImportEntry> entries;
  final bool inPlace;
  @override
  State<BookImportSelection> createState() => _BookImportSelectionState();
}

class _BookImportSelectionState extends State<BookImportSelection> {
  late final selected = widget.entries.map((e) => e.id).toSet();
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(ModuStrings.text(
            context,
            widget.inPlace ? '原位添加书籍' : '选择要导入的书籍',
            widget.inPlace ? 'Add books in place' : 'Select books to import')),
        content: SizedBox(
            width: 520,
            height: MediaQuery.sizeOf(context).height * .55,
            child: ListView.builder(
                itemCount: widget.entries.length + 2,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Text(ModuStrings.text(
                        context,
                        widget.inPlace
                            ? '只读原文件，不上传原书；笔记和进度照常同步。TXT、Markdown、UMD 请关闭原位开关后导入。'
                            : '支持 EPUB、MOBI、AZW3、FB2、PDF、TXT、Markdown、UMD。文件夹包含子文件夹，原文件保持不变。',
                        widget.inPlace
                            ? 'Read originals without uploading them. Notes and progress still sync. Turn off in-place adding to import TXT, Markdown or UMD.'
                            : 'EPUB, MOBI, AZW3, FB2, PDF, TXT, Markdown and UMD. Includes subfolders; original files are kept.'));
                  }
                  if (index == 1) {
                    return CheckboxListTile(
                      title:
                          Text(ModuStrings.text(context, '全选', 'Select all')),
                      subtitle: Text(ModuStrings.format(
                          context, '已选 {count} 本', '{count} books selected',
                          values: {'count': selected.length})),
                      value: selected.length == widget.entries.length
                          ? true
                          : selected.isEmpty
                              ? false
                              : null,
                      tristate: true,
                      onChanged: (_) => setState(() {
                        if (selected.length == widget.entries.length) {
                          selected.clear();
                        } else {
                          selected.addAll(widget.entries.map((e) => e.id));
                        }
                      }),
                    );
                  }
                  final entry = widget.entries[index - 2];
                  return CheckboxListTile(
                      key: ValueKey(entry.id),
                      title: Text(entry.name),
                      subtitle: Text(entry.label),
                      value: selected.contains(entry.id),
                      onChanged: (value) => setState(() {
                            if (value == true) {
                              selected.add(entry.id);
                            } else {
                              selected.remove(entry.id);
                            }
                          }));
                })),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
          FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      widget.entries
                          .where((e) => selected.contains(e.id))
                          .toList()),
              child: Text(ModuStrings.text(
                  context,
                  widget.inPlace ? '添加所选' : '导入所选',
                  widget.inPlace ? 'Add selected' : 'Import selected'))),
        ],
      );
}

/// Used by the reader as well as the bookshelf; directory drops use the same
/// safe staging pipeline, without picker confirmations or result dialogs.
class BookImportDropTarget extends ConsumerWidget {
  const BookImportDropTarget({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) => DropTarget(
        onDragDone: (detail) => pickBooksForImport(context, ref,
            droppedPaths: detail.files.map((e) => e.path).toList()),
        child: child,
      );
}
