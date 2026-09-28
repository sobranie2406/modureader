import 'package:anx_reader/providers/book_list.dart';
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
      setState(() => _error = '请输入文件夹名称');
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
          _error = '操作失败，请确认书籍和文件夹仍然存在后重试';
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
        title: Text(widget.createNew ? '新建文件夹' : '移入文件夹'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('将 ${widget.bookIds.length} 本书移入文件夹'),
              const SizedBox(height: 16),
              if (widget.createNew)
                TextField(
                  controller: _name,
                  autofocus: true,
                  enabled: !_saving,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: '文件夹名称'),
                  onSubmitted: (_) => _save(),
                )
              else
                groups!.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => TextButton(
                      onPressed: () => ref.invalidate(groupDaoProvider),
                      child: const Text('文件夹加载失败，点击重试')),
                  data: (_) => destinations!.isEmpty
                      ? const Text('暂无已有文件夹，请先使用“新建文件夹”。')
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
              child: const Text('取消')),
          FilledButton(
              onPressed: _saving ||
                      widget.bookIds.isEmpty ||
                      (!widget.createNew && !validDestination)
                  ? null
                  : _save,
              child: Text(widget.createNew ? '创建并移入' : '移入')),
        ],
      ),
    );
  }
}
