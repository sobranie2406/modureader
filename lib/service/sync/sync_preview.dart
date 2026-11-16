import 'package:modu_reader/service/sync/row_sync_record.dart';

/// Read-only view of both libraries handed to the confirmation UI BEFORE the
/// library merge or cloud write. The engine never applies these records by itself.
class SyncPreviewContext {
  const SyncPreviewContext({
    required this.local,
    required this.remote,
    this.pendingRecords = const [],
    this.localChangedAt,
    this.remoteChangedAt,
    this.remoteFileAt,
    this.remoteMissing = false,
  });

  final List<RowSyncRecord> local;
  final List<RowSyncRecord> remote;
  final List<RowSyncRecord> pendingRecords;
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

/// Thrown to abort after the user declined, before any library merge or cloud
/// write. Read caches and local sync metadata may already have been prepared.
class SyncPreviewCancelled implements Exception {
  const SyncPreviewCancelled();

  @override
  String toString() => 'SyncPreviewCancelled';
}

class SyncPreviewBook {
  const SyncPreviewBook({
    required this.title,
    required this.filePath,
    this.before,
    this.after,
  });

  final String title;
  final String filePath;

  /// Reading percentage before / after this direction's merge.
  final double? before;
  final double? after;
}

/// Everything the confirmation dialog shows. Built from the same records the
/// merge consumes, so the counts match what the merge would actually do.
///
/// The merge is bidirectional, so changes are reported per direction:
/// [addedBooks]/[removedBooks]/[noteDelta]/[readingTimeDelta] describe what
/// this device receives, while [uploadedBooks]/[cloudRemovedBooks]/
/// [uploadNoteDelta]/[uploadReadingTimeDelta] describe what the cloud
/// receives. An uploading device therefore still sees its notes, reading time
/// and progress as upload deltas instead of "0".
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
    required this.uploadedBooks,
    required this.cloudRemovedBooks,
    required this.uploadedProgressChangedBooks,
    required this.localNoteCount,
    required this.mergedNoteCount,
    required this.remoteNoteCount,
    required this.localReadingSeconds,
    required this.mergedReadingSeconds,
    required this.remoteReadingSeconds,
    required this.divergentRecords,
    required this.divergentByKind,
    required this.resolution,
    this.cloudNoteCount,
    this.cloudReadingSeconds,
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

  /// Reading progress this device will move to.
  final List<SyncPreviewBook> progressChangedBooks;

  /// Books the cloud will gain from this device.
  final List<SyncPreviewBook> uploadedBooks;

  /// Books the cloud will lose because this device deleted them.
  final List<SyncPreviewBook> cloudRemovedBooks;

  /// Reading progress the cloud will move to.
  final List<SyncPreviewBook> uploadedProgressChangedBooks;

  final int localNoteCount;
  final int mergedNoteCount;
  final int remoteNoteCount;
  final int localReadingSeconds;
  final int mergedReadingSeconds;
  final int remoteReadingSeconds;

  final int divergentRecords;
  final Map<String, int> divergentByKind;
  final SyncConflictResolution resolution;

  /// What the cloud holds after an upload-only pass. Upload-only keeps records
  /// that only the cloud knows, so the upload deltas cannot be derived from the
  /// merged view (which is this device only). Null for every other choice.
  final int? cloudNoteCount;
  final int? cloudReadingSeconds;

  int get noteDelta => mergedNoteCount - localNoteCount;
  int get readingTimeDelta => mergedReadingSeconds - localReadingSeconds;
  int get uploadNoteAfter => cloudNoteCount ?? mergedNoteCount;
  int get uploadReadingSecondsAfter =>
      cloudReadingSeconds ?? mergedReadingSeconds;
  int get uploadNoteDelta => uploadNoteAfter - remoteNoteCount;
  int get uploadReadingTimeDelta =>
      uploadReadingSecondsAfter - remoteReadingSeconds;

  bool get removesBooks => removedBooks.isNotEmpty;

  bool get uploadOnly => resolution == SyncConflictResolution.uploadOnly;

  /// Books disappear on one of the two sides and cannot be restored by a later
  /// merge, so the dialog asks for an explicit acknowledgement first.
  bool get deletesBooks =>
      removedBooks.isNotEmpty || cloudRemovedBooks.isNotEmpty;

  bool get hasDownloadChanges =>
      addedBooks.isNotEmpty ||
      removedBooks.isNotEmpty ||
      progressChangedBooks.isNotEmpty ||
      noteDelta != 0 ||
      readingTimeDelta != 0;

  bool get hasUploadChanges =>
      uploadedBooks.isNotEmpty ||
      cloudRemovedBooks.isNotEmpty ||
      uploadedProgressChangedBooks.isNotEmpty ||
      uploadNoteDelta != 0 ||
      uploadReadingTimeDelta != 0;

  bool get hasChanges =>
      hasDownloadChanges || hasUploadChanges || divergentRecords > 0;
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
  final uploadOnly = resolution == SyncConflictResolution.uploadOnly;
  // Upload-only never imports the cloud, so the merged view is this device plus
  // its own pending operations.
  final merged = uploadOnly
      ? mergeSyncRecords(local, context.pendingRecords)
      : resolveSyncConflicts(
          local: local,
          remote: remote,
          merged: mergeSyncRecords(
              local, mergeSyncRecords(remote, context.pendingRecords)),
          resolution: resolution,
        );

  final localBooks = _bookInfo(local);
  final remoteBooks = _bookInfo(remote);
  final mergedBooks = _bookInfo(merged);
  final localVisible = _visibleBooks(local);
  final remoteVisible = _visibleBooks(remote);
  final mergedVisible = _visibleBooks(merged);
  final localProgress = _progressByBook(local);
  final remoteProgress = _progressByBook(remote);
  final mergedProgress = _progressByBook(merged);
  // With upload-only the local side of every delta is the post-merge view, so
  // the dialog reports no incoming changes.
  final localView = uploadOnly ? merged : local;
  final localBooksView = uploadOnly ? mergedBooks : localBooks;
  final localVisibleView = uploadOnly ? mergedVisible : localVisible;
  final localProgressView = uploadOnly ? mergedProgress : localProgress;
  // Upload-only keeps cloud-only records, so the cloud's post-sync counts are
  // the union of both sides rather than this device's view.
  final cloudView = uploadOnly
      ? mergeSyncRecords(
          remote, mergeSyncRecords(local, context.pendingRecords))
      : merged;
  final allKnownBooks = {...remoteBooks, ...localBooksView, ...mergedBooks};

  List<SyncPreviewBook> bookList(Set<String> ids,
      {required Map<String, double> before,
      required Map<String, double> after}) {
    final books = <SyncPreviewBook>[];
    for (final id in ids) {
      final data = mergedBooks[id] ?? localBooks[id] ?? remoteBooks[id];
      if (data == null) continue;
      books.add(SyncPreviewBook(
        title: _title(data, id),
        filePath: data['file_path'] as String? ?? '',
        before: before[id],
        after: after[id],
      ));
    }
    books.sort((a, b) => a.title.compareTo(b.title));
    return books;
  }

  List<SyncPreviewBook> progressList(Set<String> ids,
      {required Map<String, double> before,
      required Map<String, double> after}) {
    final books = <SyncPreviewBook>[];
    for (final id in ids) {
      final old = before[id];
      final next = after[id];
      if (old == null || next == null || (next - old).abs() < 0.001) continue;
      final data = mergedBooks[id] ?? localBooks[id] ?? remoteBooks[id];
      if (data == null) continue;
      books.add(SyncPreviewBook(
        title: _title(data, id),
        filePath: data['file_path'] as String? ?? '',
        before: old,
        after: next,
      ));
    }
    books.sort((a, b) => a.title.compareTo(b.title));
    return books;
  }

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
    sharedBooks: localVisibleView.intersection(remoteVisible).length,
    // "Local only" means the cloud has no record of the book at all, so the
    // merge really uploads it. A book the cloud deleted still has a record and
    // is reported through removedBooks instead of being counted as an upload.
    localOnlyBooks: localVisibleView
        .difference(_knownBookIds(remote))
        .length,
    remoteOnlyBooks: remoteVisible
        .difference(_knownBookIds(localView))
        .length,
    bothDeletedBooks: allKnownBooks.keys
        .toSet()
        .difference(localVisibleView.union(remoteVisible))
        .length,
    addedBooks: bookList(mergedVisible.difference(localVisibleView),
        before: const {}, after: mergedProgress),
    removedBooks: bookList(localVisibleView.difference(mergedVisible),
        before: localProgressView, after: const {}),
    progressChangedBooks:
        progressList(mergedVisible.intersection(localVisibleView),
            before: localProgressView, after: mergedProgress),
    uploadedBooks: bookList(
        // Upload-only never revives a book the cloud deleted, so only books
        // without any cloud record are reported as gains.
        uploadOnly
            ? mergedVisible.difference(_knownBookIds(remote))
            : mergedVisible.difference(remoteVisible),
        before: const {}, after: mergedProgress),
    cloudRemovedBooks: bookList(
        uploadOnly
            ? remoteVisible.where((id) => _deletedLocally(merged, id)).toSet()
            : remoteVisible.difference(mergedVisible),
        before: remoteProgress,
        after: const {}),
    uploadedProgressChangedBooks: progressList(
        mergedVisible.intersection(remoteVisible),
        before: remoteProgress,
        after: mergedProgress),
    localNoteCount: _noteCount(localView),
    mergedNoteCount: _noteCount(merged),
    remoteNoteCount: _noteCount(remote),
    localReadingSeconds: _readingSeconds(localView),
    mergedReadingSeconds: _readingSeconds(merged),
    remoteReadingSeconds: _readingSeconds(remote),
    divergentRecords: divergent.length,
    divergentByKind: divergentByKind,
    resolution: resolution,
    cloudNoteCount: uploadOnly ? _noteCount(cloudView) : null,
    cloudReadingSeconds: uploadOnly ? _readingSeconds(cloudView) : null,
  );
}

String _title(Map<String, Object?> data, String id) {
  final title = data['title'] as String?;
  return title?.trim().isNotEmpty == true ? title! : id;
}

Map<String, Map<String, Object?>> _bookInfo(Iterable<RowSyncRecord> records) =>
    {
      for (final record in records)
        if (record.kind == 'book' && !record.deleted) record.id: record.data
    };

/// Every book id either side has a record for, tombstones included. Used to
/// tell "the cloud has never heard of this book" apart from "the cloud deleted
/// it", which the merge treats very differently.
Set<String> _knownBookIds(Iterable<RowSyncRecord> records) => {
      for (final record in records)
        if (record.kind == 'book' || record.kind == 'life') record.id
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

/// True when this device knows the book and has deleted it, either as a hard
/// tombstone or through the `life` soft-delete flag. Upload-only uses this to
/// keep cloud-only books out of the "the cloud will lose" list, because those
/// records stay in the cloud untouched.
bool _deletedLocally(Iterable<RowSyncRecord> records, String id) {
  var known = false;
  var deleted = false;
  for (final record in records) {
    if (record.id != id || (record.kind != 'book' && record.kind != 'life')) {
      continue;
    }
    known = true;
    if (record.deleted ||
        (record.kind == 'life' && record.data['is_deleted'] == 1)) {
      deleted = true;
    }
  }
  return known && deleted;
}

Map<String, double> _progressByBook(Iterable<RowSyncRecord> records) {
  final progress = <String, double>{};
  for (final record in records) {
    if (record.kind != 'position' || record.deleted) continue;
    final value = record.data['reading_percentage'];
    if (value is num) progress[record.id] = value.toDouble();
  }
  return progress;
}

int _noteCount(Iterable<RowSyncRecord> records) =>
    records.where((record) => record.kind == 'note' && !record.deleted).length;

int _readingSeconds(Iterable<RowSyncRecord> records) {
  var total = 0;
  for (final record in records) {
    if (record.kind != 'time' || record.deleted) continue;
    final seconds = record.data['reading_time'];
    if (seconds is int) total += seconds;
  }
  return total;
}
