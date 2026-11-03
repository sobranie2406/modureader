import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/sync_preview.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Asks the user to confirm a merge before anything is written. Returns the
/// conflict preference, or null when the synchronization is cancelled.
Future<SyncConflictResolution?> showSyncPreviewDialog(
    BuildContext context, SyncPreview preview) {
  return showDialog<SyncConflictResolution>(
    animationStyle: AppMotion.style,
    context: context,
    barrierDismissible: false,
    builder: (_) => SyncPreviewDialog(preview: preview),
  );
}

class SyncPreviewDialog extends StatefulWidget {
  const SyncPreviewDialog({super.key, required this.preview});

  final SyncPreview preview;

  @override
  State<SyncPreviewDialog> createState() => _SyncPreviewDialogState();
}

class _SyncPreviewDialogState extends State<SyncPreviewDialog> {
  SyncConflictResolution _resolution = SyncConflictResolution.newest;

  String _text(String zh, String en) => ModuStrings.text(context, zh, en);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = widget.preview;
    final lastSynced = Prefs().lastUploadBookDate;
    return AlertDialog(
      key: const ValueKey('sync-preview-dialog'),
      title: Row(
        children: [
          const Icon(Icons.fact_check_outlined, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(_text('同步预览', 'Sync preview'))),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _timeRow(_text('本机数据最后修改', 'Local changes last modified'),
                  preview.localChangedAt),
              _timeRow(_text('云端数据最后修改', 'Cloud changes last modified'),
                  preview.remoteChangedAt),
              _timeRow(_text('云端文件上传时间', 'Cloud file uploaded'),
                  preview.remoteFileAt),
              _timeRow(_text('上次成功同步', 'Last successful sync'), lastSynced),
              const Divider(height: 24),
              if (preview.remoteMissing)
                Text(_text(
                    '云端还没有同步数据：本次将建立云端记录，并把本机书籍上传。',
                    'The cloud has no data yet: this sync will create the cloud archive and upload this device\'s books.'))
              else
                _bookDistribution(preview),
              if (preview.removesBooks) ...[
                const SizedBox(height: 12),
                _warning(
                  theme,
                  _text(
                    '有 ${preview.removedBooks.length} 本书在云端已被删除，同步后将从本机书架移除。阅读记录仍保留在历史中。',
                    '${preview.removedBooks.length} book(s) were deleted on another device and will leave this shelf. Reading history is kept.',
                  ),
                ),
              ],
              if (preview.addedBooks.isNotEmpty) ...[
                const SizedBox(height: 12),
                _bookList(
                    _text('将加入书架', 'Will be added'), preview.addedBooks),
              ],
              if (preview.removedBooks.isNotEmpty) ...[
                const SizedBox(height: 12),
                _bookList(
                    _text('将移出书架', 'Will be removed'), preview.removedBooks),
              ],
              if (preview.progressChangedBooks.isNotEmpty) ...[
                const SizedBox(height: 12),
                _progressList(preview.progressChangedBooks),
              ],
              const SizedBox(height: 12),
              _readingData(preview),
              if (preview.divergentRecords > 0) ...[
                const Divider(height: 24),
                _conflictSection(preview, theme),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('sync-preview-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_text('取消', 'Cancel')),
        ),
        FilledButton(
          key: const ValueKey('sync-preview-confirm'),
          onPressed: () => Navigator.of(context).pop(_resolution),
          child: Text(_text('开始同步', 'Start sync')),
        ),
      ],
    );
  }

  Widget _timeRow(String label, DateTime? time) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            time == null
                ? _text('无记录', 'None')
                : DateFormat('yyyy-MM-dd HH:mm').format(time.toLocal()),
            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }

  Widget _bookDistribution(SyncPreview preview) {
    final rows = <List<Object>>[
      [
        _text('两端都有', 'On both devices'),
        preview.sharedBooks,
        Icons.library_books_outlined
      ],
      [
        _text('仅本机（将上传）', 'Local only (will upload)'),
        preview.localOnlyBooks,
        Icons.upload_outlined
      ],
      [
        _text('仅云端（将下载）', 'Cloud only (will download)'),
        preview.remoteOnlyBooks,
        Icons.download_outlined
      ],
      [
        _text('两端都已删除', 'Deleted on both'),
        preview.bothDeletedBooks,
        Icons.delete_outline
      ],
    ];
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(row[2] as IconData, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(row[0] as String)),
                Text('${row[1]}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _bookList(String title, List<SyncPreviewBook> books) {
    const max = 6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        for (final book in books.take(max))
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('· ${book.title}', maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        if (books.length > max)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(_text('等 ${books.length} 本', 'and ${books.length - max} more'),
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }

  Widget _progressList(List<SyncPreviewBook> books) {
    const max = 6;
    String percent(double? value) =>
        value == null ? '—' : '${(value * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_text('阅读进度变化', 'Reading progress changes'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        for (final book in books.take(max))
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text('· ${book.title}',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Text('${percent(book.localProgress)} → '
                    '${percent(book.remoteProgress)}'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _readingData(SyncPreview preview) {
    final minutes = (preview.readingTimeDelta / 60).round();
    final deltaStyle = TextStyle(
      fontWeight: FontWeight.bold,
      color: deltaColor(preview.readingTimeDelta),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.edit_note, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_text('笔记', 'Notes'))),
              Text('${_signed(preview.noteDelta)} '
                  '(${preview.localNoteCount} → ${preview.mergedNoteCount})'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.timer_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_text('阅读时长', 'Reading time'))),
              Text(
                '${minutes >= 0 ? '+' : ''}$minutes '
                '${_text('分钟', 'min')}',
                style: deltaStyle,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color deltaColor(int seconds) {
    if (seconds == 0) return Theme.of(context).colorScheme.onSurface;
    return seconds > 0
        ? Colors.green.shade700
        : Theme.of(context).colorScheme.error;
  }

  String _signed(int value) => value > 0 ? '+$value' : '$value';

  Widget _conflictSection(SyncPreview preview, ThemeData theme) {
    final kinds = preview.divergentByKind.entries
        .map((entry) => '${_kindLabel(entry.key)} ${entry.value}')
        .join('、');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_text('两端记录不一致', 'Divergent records'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(_text(
          '有 ${preview.divergentRecords} 处记录两端都修改过（$kinds）。',
          '${preview.divergentRecords} record(s) were changed on both devices ($kinds).',
        )),
        const SizedBox(height: 8),
        SegmentedButton<SyncConflictResolution>(
          key: const ValueKey('sync-preview-resolution'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: SyncConflictResolution.newest,
              label: Text(_text('较新优先', 'Newest')),
            ),
            ButtonSegment(
              value: SyncConflictResolution.preferLocal,
              label: Text(_text('以本机为准', 'Keep local')),
            ),
            ButtonSegment(
              value: SyncConflictResolution.preferRemote,
              label: Text(_text('以云端为准', 'Keep cloud')),
            ),
          ],
          selected: {_resolution},
          onSelectionChanged: (selected) =>
              setState(() => _resolution = selected.single),
        ),
        if (_resolution == SyncConflictResolution.preferLocal)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_text('云端较新的改动会被本机覆盖。',
                'Newer cloud changes will be overwritten by this device.')),
          ),
        if (_resolution == SyncConflictResolution.preferRemote)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _text('本机未同步的改动会被云端覆盖。',
                  'Unsynced local changes will be overwritten by the cloud.'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _warning(ThemeData theme, String message) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }

  String _kindLabel(String kind) => _text(
        switch (kind) {
          'book' => '书籍信息',
          'position' => '阅读进度',
          'note' => '笔记',
          'time' => '阅读时长',
          'round' => '阅读轮次',
          'review' => '书评',
          'group' => '分组',
          'life' => '删除状态',
          _ => '其他记录',
        },
        switch (kind) {
          'book' => 'books',
          'position' => 'progress',
          'note' => 'notes',
          'time' => 'reading time',
          'round' => 'rounds',
          'review' => 'reviews',
          'group' => 'groups',
          'life' => 'deletion state',
          _ => 'other records',
        },
      );
}
