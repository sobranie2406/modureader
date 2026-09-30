import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The dialog owns the pending transaction so failed moves retain selection.
class BookFolderDialog extends ConsumerStatefulWidget {
  const BookFolderDialog(
      {super.key, required this.bookIds, required this.createNew});
  final List<int> bookIds;
  final bool createNew;

  @override
  ConsumerState<BookFolderDialog> createState() => _BookFolderDialogState();
}

class _BookFolderDialogState extends ConsumerState<BookFolderDialog> {
  final _name = TextEditingController();
  int? _groupId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (widget.createNew && _name.text.trim().isEmpty) {
      setState(() => _error =
          ModuStrings.text(context, '请输入文件夹名称', 'Enter a folder name'));
      return;
    }
    if (!widget.createNew && _groupId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(bookListProvider.notifier).moveBooksToFolder(
          widget.bookIds,
          groupId: widget.createNew ? null : _groupId,
          newFolderName: widget.createNew ? _name.text.trim() : null);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = ModuStrings.text(context, '操作失败，请确认书籍和文件夹仍然存在后重试',
              'Operation failed. Check that the books and folder still exist, then retry.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.createNew ? null : ref.watch(groupDaoProvider);
    final destinations = groups?.valueOrNull
        ?.where((g) => g.id > 0 && g.isDeleted == 0)
        .toList();
    final validDestination =
        destinations?.any((g) => g.id == _groupId) ?? false;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(widget.createNew
            ? ModuStrings.text(context, '新建文件夹', 'New folder')
            : ModuStrings.text(context, '移入文件夹', 'Move to folder')),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ModuStrings.format(context, '将 {count} 本书移入文件夹',
                  'Move {count} books to a folder',
                  values: {'count': widget.bookIds.length})),
              const SizedBox(height: 16),
              if (widget.createNew)
                TextField(
                  controller: _name,
                  autofocus: true,
                  enabled: !_saving,
                  maxLength: 100,
                  decoration: InputDecoration(
                      labelText:
                          ModuStrings.text(context, '文件夹名称', 'Folder name')),
                  onSubmitted: (_) => _save(),
                )
              else
                groups!.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => TextButton(
                      onPressed: () => ref.invalidate(groupDaoProvider),
                      child: Text(ModuStrings.text(context, '文件夹加载失败，点击重试',
                          'Could not load folders. Tap to retry.'))),
                  data: (_) => destinations!.isEmpty
                      ? Text(ModuStrings.text(context, '暂无已有文件夹，请先使用“新建文件夹”。',
                          'No folders yet. Use New folder first.'))
                      : Column(children: [
                          for (final group in destinations)
                            ListTile(
                              leading: Icon(_groupId == group.id
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off),
                              title: Text(group.name),
                              selected: _groupId == group.id,
                              enabled: !_saving,
                              onTap: () => setState(() {
                                _groupId = group.id;
                                _error = null;
                              }),
                            )
                        ]),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              if (_saving) const LinearProgressIndicator(),
            ],
          )),
        ),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context, false),
              child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
          FilledButton(
              onPressed: _saving ||
                      widget.bookIds.isEmpty ||
                      (!widget.createNew && !validDestination)
                  ? null
                  : _save,
              child: Text(widget.createNew
                  ? ModuStrings.text(context, '创建并移入', 'Create and move')
                  : ModuStrings.text(context, '移入', 'Move'))),
        ],
      ),
    );
  }
}
