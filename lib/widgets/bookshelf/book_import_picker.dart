import 'package:anx_reader/utils/app_motion.dart';
import 'dart:io';

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
    {bool folder = false, List<String>? droppedPaths}) async {
  if (_pickingBooks) return;
  _pickingBooks = true;
  final mobileFolder = folder && (Platform.isAndroid || Platform.isIOS);
  try {
    List<BookImportEntry>? entries;
    if (droppedPaths != null) {
      entries = await _withImportProgress(
          context, () => discoverBookImportFiles(droppedPaths));
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
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ModuStrings.text(
              context, '没有找到支持的书籍文件', 'No supported books found'))));
      return;
    }
    final selected = await showDialog<List<BookImportEntry>>(
      animationStyle: AppMotion.style,
      context: context,
      builder: (_) => BookImportSelection(entries: entries!),
    );
    if (selected == null || selected.isEmpty || !context.mounted) return;
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
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ModuStrings.text(
              context,
              '无法读取所选文件或文件夹，请检查访问权限及文件是否已下载到本机后重试。',
              'Unable to read the selection. Check access and download cloud files locally, then try again.'))));
    }
  } finally {
    try {
      if (mobileFolder) {
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
  const BookImportSelection({super.key, required this.entries});
  final List<BookImportEntry> entries;
  @override
  State<BookImportSelection> createState() => _BookImportSelectionState();
}

class _BookImportSelectionState extends State<BookImportSelection> {
  late final selected = widget.entries.map((e) => e.id).toSet();
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            ModuStrings.text(context, '选择要导入的书籍', 'Select books to import')),
        content: SizedBox(
            width: 520,
            height: MediaQuery.sizeOf(context).height * .55,
            child: Column(children: [
              Text(ModuStrings.text(
                  context,
                  '支持 EPUB、MOBI、AZW3、FB2、PDF、TXT、Markdown、UMD。文件夹包含子文件夹，原文件保持不变。',
                  'EPUB, MOBI, AZW3, FB2, PDF, TXT, Markdown and UMD. Includes subfolders; original files are kept.')),
              CheckboxListTile(
                title: Text(ModuStrings.text(context, '全选', 'Select all')),
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
              ),
              Expanded(
                  child: ListView.builder(
                      itemCount: widget.entries.length,
                      itemBuilder: (context, index) {
                        final entry = widget.entries[index];
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
            ])),
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
              child:
                  Text(ModuStrings.text(context, '导入所选', 'Import selected'))),
        ],
      );
}

/// Used by the reader as well as the bookshelf; directory drops use the same
/// selection and staging pipeline as the folder picker.
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
