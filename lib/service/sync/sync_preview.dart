import 'package:anx_reader/service/sync/row_sync_record.dart';

/// Read-only view of both libraries handed to the confirmation UI BEFORE the
/// merge writes anything. The engine never applies these records by itself.
class SyncPreviewContext {
  const SyncPreviewContext({
    required this.local,
    required this.remote,
    this.localChangedAt,
    this.remoteChangedAt,
    this.remoteFileAt,
    this.remoteMissing = false,
  });

  final List<RowSyncRecord> local;
  final List<RowSyncRecord> remote;
  final DateTime? localChangedAt;
  final DateTime? remoteChangedAt;

  /// Upload time of the cloud archive (`database8.db`), not of the records.
  final DateTime? remoteFileAt;

  /// Neither a cloud archive nor a record-log batch exists yet.
  final bool remoteMissing;
}

/// What the user answered in the preview dialog.
class SyncPreviewDecision {
  const SyncPreviewDecision(this.resolution);
  const SyncPreviewDecision.cancel() : resolution = null;

  final SyncConflictResolution? resolution;
  bool get cancelled => resolution == null;
}

typedef SyncPreviewHook = Future<SyncPreviewDecision> Function(
    SyncPreviewContext context);

/// Thrown to abort a synchronization after the user declined it. No database or
/// cloud write has happened at this point; the next attempt starts over.
class SyncPreviewCancelled implements Exception {
  const SyncPreviewCancelled();

  @override
  String toString() => 'SyncPreviewCancelled';
}

class SyncPreviewBook {
  const SyncPreviewBook({
    required this.title,
    required this.filePath,
    this.localProgress,
    this.remoteProgress,
  });

  final String title;
  final String filePath;

  /// Reading percentage on this device, null when never opened here.
  final double? localProgress;

  /// Reading percentage after the merge.
  final double? remoteProgress;
}

/// Everything the confirmation dialog shows. Built from the same records the
/// merge consumes, so the counts match what the merge would actually do.
class SyncPreview {
  const SyncPreview({
    required this.localChangedAt,
    required this.remoteChangedAt,
    required this.remoteFileAt,
    required this.remoteMissing,
    required this.sharedBooks,
    required this.localOnlyBooks,
    required this.remoteOnlyBooks,
    required this.bothDeletedBooks,
    required this.addedBooks,
    required this.removedBooks,
    required this.progressChangedBooks,
    required this.localNoteCount,
    required this.mergedNoteCount,
    required this.localReadingSeconds,
    required this.mergedReadingSeconds,
    required this.divergentRecords,
    required this.divergentByKind,
    required this.resolution,
  });

  final DateTime? localChangedAt;
  final DateTime? remoteChangedAt;
  final DateTime? remoteFileAt;
  final bool remoteMissing;

  final int sharedBooks;
  final int localOnlyBooks;
  final int remoteOnlyBooks;
  final int bothDeletedBooks;

  /// Books that will appear on this device after the merge.
  final List<SyncPreviewBook> addedBooks;

  /// Books that will leave this device's shelf because the cloud deleted them.
  final List<SyncPreviewBook> removedBooks;

  final List<SyncPreviewBook> progressChangedBooks;

  final int localNoteCount;
  final int mergedNoteCount;
  final int localReadingSeconds;
  final int mergedReadingSeconds;

  final int divergentRecords;
  final Map<String, int> divergentByKind;
  final SyncConflictResolution resolution;

  int get noteDelta => mergedNoteCount - localNoteCount;
  int get readingTimeDelta => mergedReadingSeconds - localReadingSeconds;

  bool get removesBooks => removedBooks.isNotEmpty;

  bool get hasChanges =>
      addedBooks.isNotEmpty ||
      removedBooks.isNotEmpty ||
      progressChangedBooks.isNotEmpty ||
      noteDelta != 0 ||
      readingTimeDelta != 0 ||
      divergentRecords > 0;
}

DateTime? latestSyncRecordTime(Iterable<RowSyncRecord> records) {
  var newest = 0;
  for (final record in records) {
    if (record.kind == 'secret' || record.clock <= newest) continue;
    newest = record.clock;
  }
  return newest == 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(newest, isUtc: true);
}

SyncPreview buildSyncPreview({
  required SyncPreviewContext context,
  SyncConflictResolution resolution = SyncConflictResolution.newest,
}) {
  final local = context.local;
  final remote = context.remote;
  final merged = resolveSyncConflicts(
    local: local,
    remote: remote,
    merged: mergeSyncRecords(local, remote),
    resolution: resolution,
  );

  final localBooks = _bookInfo(local);
  final remoteBooks = _bookInfo(remote);
  final mergedBooks = _bookInfo(merged);
  final localVisible = _visibleBooks(local);
  final remoteVisible = _visibleBooks(remote);
  final mergedVisible = _visibleBooks(merged);
  final localProgress = _progressByBook(local);
  final mergedProgress = _progressByBook(merged);

  final allKnownBooks = {...remoteBooks, ...localBooks, ...mergedBooks};
  final added = mergedVisible.difference(localVisible)
      .map((id) => _bookPreview(allKnownBooks, mergedProgress, id,
          localProgress: localProgress, includeAfter: true))
      .whereType<SyncPreviewBook>()
      .toList();
  final removed = localVisible.difference(mergedVisible)
      .map((id) => _bookPreview(allKnownBooks, mergedProgress, id,
          localProgress: localProgress, includeAfter: false))
      .whereType<SyncPreviewBook>()
      .toList();
  final progressChanged = <SyncPreviewBook>[];
  for (final id in mergedVisible.intersection(localVisible)) {
    final before = localProgress[id];
    final after = mergedProgress[id];
    if (before == null ||
        after == null ||
        (after - before).abs() < 0.001) {
      continue;
    }
    final book = _bookPreview(mergedBooks, mergedProgress, id,
        localProgress: localProgress, includeAfter: true);
    if (book != null) progressChanged.add(book);
  }

  added.sort((a, b) => a.title.compareTo(b.title));
  removed.sort((a, b) => a.title.compareTo(b.title));
  progressChanged.sort((a, b) => a.title.compareTo(b.title));

  final divergent = divergentSyncKeys(local, remote);
  final divergentByKind = <String, int>{};
  for (final key in divergent) {
    final kind = key.split('/').first;
    divergentByKind[kind] = (divergentByKind[kind] ?? 0) + 1;
  }

  return SyncPreview(
    localChangedAt: context.localChangedAt,
    remoteChangedAt: context.remoteChangedAt,
    remoteFileAt: context.remoteFileAt,
    remoteMissing: context.remoteMissing,
    sharedBooks: localVisible.intersection(remoteVisible).length,
    // "Local only" means the cloud has no record of the book at all, so the
    // merge really uploads it. A book the cloud deleted still has a record and
    // is reported through removedBooks instead of being counted as an upload.
    localOnlyBooks: localVisible.difference(remoteBooks.keys.toSet()).length,
    remoteOnlyBooks: remoteVisible.difference(localBooks.keys.toSet()).length,
    bothDeletedBooks: allKnownBooks.keys
        .toSet()
        .difference(localVisible.union(remoteVisible))
        .length,
    addedBooks: added,
    removedBooks: removed,
    progressChangedBooks: progressChanged,
    localNoteCount: _noteCount(local),
    mergedNoteCount: _noteCount(merged),
    localReadingSeconds: _readingSeconds(local),
    mergedReadingSeconds: _readingSeconds(merged),
    divergentRecords: divergent.length,
    divergentByKind: divergentByKind,
    resolution: resolution,
  );
}

Map<String, Map<String, Object?>> _bookInfo(Iterable<RowSyncRecord> records) => {
      for (final record in records)
        if (record.kind == 'book' && !record.deleted) record.id: record.data
    };

/// Visible shelf books: a live book record whose `life` state is not deleted.
/// Hard-delete tombstones (a deleted book record) are hidden as well.
Set<String> _visibleBooks(Iterable<RowSyncRecord> records) {
  final deleted = <String, bool>{};
  for (final record in records) {
    if (record.kind != 'life' || record.deleted) continue;
    deleted[record.id] = record.data['is_deleted'] == 1;
  }
  return {
    for (final record in records)
      if (record.kind == 'book' &&
          !record.deleted &&
          deleted[record.id] != true)
        record.id
  };
}

Map<String, double> _progressByBook(Iterable<RowSyncRecord> records) => {
      for (final record in records)
        if (record.kind == 'position' && !record.deleted)
          if (record.data['reading_percentage'] is num)
            record.id: (record.data['reading_percentage'] as num).toDouble()
    };

SyncPreviewBook? _bookPreview(
  Map<String, Map<String, Object?>> books,
  Map<String, double> after,
  String id, {
  required Map<String, double> localProgress,
  required bool includeAfter,
}) {
  final data = books[id];
  if (data == null) return null;
  return SyncPreviewBook(
    title: (data['title'] as String?)?.trim().isNotEmpty == true
        ? data['title'] as String
        : id,
    filePath: data['file_path'] as String? ?? '',
    localProgress: localProgress[id],
    remoteProgress: includeAfter ? after[id] : null,
  );
}

int _noteCount(Iterable<RowSyncRecord> records) => records
    .where((record) => record.kind == 'note' && !record.deleted)
    .length;

int _readingSeconds(Iterable<RowSyncRecord> records) {
  var total = 0;
  for (final record in records) {
    if (record.kind != 'time' || record.deleted) continue;
    final seconds = record.data['reading_time'];
    if (seconds is int) total += seconds;
  }
  return total;
}
