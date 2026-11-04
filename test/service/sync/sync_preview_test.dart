import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/sync_preview.dart';
import 'package:flutter_test/flutter_test.dart';

RowSyncRecord book(String md5,
        {String title = 'Synthetic book',
        int clock = 1000,
        bool deleted = false}) =>
    RowSyncRecord('book', 'md5:$md5', clock, 'rev-book', deleted, {
      'title': title,
      'cover_path': '',
      'file_path': 'file/$md5.epub',
      'author': 'Test',
      'description': '',
      'rating': null,
      'group_id': null,
      'file_md5': md5,
      'create_time': '2026-09-01T00:00:00Z',
      'update_time': '2026-09-01T00:00:00Z',
    });

RowSyncRecord life(String md5, {required bool deleted, int clock = 1000}) =>
    RowSyncRecord('life', 'md5:$md5', clock, 'rev-life', false,
        {'is_deleted': deleted ? 1 : 0});

RowSyncRecord position(String md5, double progress, {int clock = 1000}) =>
    RowSyncRecord('position', 'md5:$md5', clock, 'rev-pos', false, {
      'last_read_position': 'cfi-$progress',
      'reading_percentage': progress,
    });

RowSyncRecord note(String md5, String id,
        {String content = 'note', int clock = 1000}) =>
    RowSyncRecord('note', '$md5:$id', clock, 'rev-note', false, {
      'book_id': 'md5:$md5',
      'content': content,
      'cfi': id,
      'chapter': '1',
      'type': 'highlight',
      'color': 0,
      'create_time': '2026-09-01T00:00:00Z',
      'update_time': '2026-09-01T00:00:00Z',
      'reader_note': '',
    });

RowSyncRecord time(String md5, String day, int seconds, {int clock = 1000}) =>
    RowSyncRecord('time', '$md5:$day', clock, 'rev-time', false, {
      'book_id': 'md5:$md5',
      'date': '${day}T00:00:00Z',
      'reading_time': seconds,
      'round': 1,
    });

SyncPreview previewOf(List<RowSyncRecord> local, List<RowSyncRecord> remote,
        {SyncConflictResolution resolution = SyncConflictResolution.newest}) =>
    buildSyncPreview(
        context: SyncPreviewContext(local: local, remote: remote),
        resolution: resolution);

void main() {
  test('counts shared, local-only and cloud-only books', () {
    final preview = previewOf(
      [book('a'), life('a', deleted: false), book('b'), life('b', deleted: false)],
      [book('a'), life('a', deleted: false), book('c'), life('c', deleted: false)],
    );
    expect(preview.sharedBooks, 1);
    expect(preview.localOnlyBooks, 1);
    expect(preview.remoteOnlyBooks, 1);
    expect(preview.addedBooks.single.title, 'Synthetic book');
    expect(preview.removedBooks, isEmpty);
    expect(preview.hasChanges, isTrue);
  });

  test('a cloud deletion is reported as a book leaving the shelf', () {
    final preview = previewOf(
      [book('a'), life('a', deleted: false)],
      [
        book('a'),
        life('a', deleted: true, clock: 2000),
      ],
    );
    expect(preview.removedBooks, hasLength(1));
    expect(preview.removedBooks.single.filePath, 'file/a.epub');
    expect(preview.addedBooks, isEmpty);
    expect(preview.removesBooks, isTrue);
    expect(preview.sharedBooks, 0);
  });

  test('a cloud restore brings the book back with the cloud progress', () {
    final preview = previewOf(
      [
        book('a'),
        life('a', deleted: true),
        position('a', 0.2),
      ],
      [
        book('a'),
        life('a', deleted: false, clock: 3000),
        position('a', 0.62, clock: 3000),
      ],
    );
    expect(preview.addedBooks, hasLength(1));
    expect(preview.addedBooks.single.after, 0.62);
    expect(preview.removedBooks, isEmpty);
  });

  test('a progress jump between visible books is reported', () {
    final preview = previewOf(
      [book('a'), life('a', deleted: false), position('a', 0.2)],
      [
        book('a'),
        life('a', deleted: false),
        position('a', 0.62, clock: 3000),
      ],
    );
    expect(preview.progressChangedBooks, hasLength(1));
    final changed = preview.progressChangedBooks.single;
    expect(changed.before, 0.2);
    expect(changed.after, 0.62);
  });

  test('notes and reading time deltas come from the merged records', () {
    final preview = previewOf(
      [book('a'), life('a', deleted: false), note('a', 'n1'), time('a', '2026-09-01', 600)],
      [
        book('a'),
        life('a', deleted: false),
        note('a', 'n1'),
        note('a', 'n2'),
        time('a', '2026-09-01', 600),
        time('a', '2026-09-02', 300),
      ],
    );
    expect(preview.noteDelta, 1);
    expect(preview.readingTimeDelta, 300);
  });

  test('an uploading device reports its own changes as upload deltas', () {
    // Regression: the uploading device used to see every delta as zero,
    // because the preview only compared the merge result with local state.
    final preview = previewOf(
      [
        book('a'),
        life('a', deleted: false),
        position('a', 0.5, clock: 3000),
        note('a', 'n1'),
        note('a', 'n2'),
        note('a', 'n3'),
        time('a', '2026-11-03', 600, clock: 3000),
      ],
      [
        book('a'),
        life('a', deleted: false),
        position('a', 0.4, clock: 1000),
        note('a', 'n1'),
        time('a', '2026-11-03', 300),
      ],
    );
    // Nothing new arrives here: the merge result is this device's own state.
    expect(preview.hasDownloadChanges, isFalse);
    expect(preview.noteDelta, 0);
    expect(preview.readingTimeDelta, 0);
    // The cloud receives the extra notes, reading time and newer progress.
    expect(preview.hasUploadChanges, isTrue);
    expect(preview.uploadNoteDelta, 2);
    expect(preview.uploadReadingTimeDelta, 300);
    expect(preview.uploadedProgressChangedBooks, hasLength(1));
    final progress = preview.uploadedProgressChangedBooks.single;
    expect(progress.before, 0.4);
    expect(progress.after, 0.5);
    expect(preview.hasChanges, isTrue);
  });

  test('divergent content is counted by kind and ignores clock drift', () {
    final preview = previewOf(
      [
        book('a'),
        life('a', deleted: false),
        note('a', 'n1', content: 'local'),
      ],
      [
        book('a'),
        life('a', deleted: false, clock: 9999),
        note('a', 'n1', content: 'cloud', clock: 9999),
      ],
    );
    expect(preview.divergentRecords, 1);
    expect(preview.divergentByKind, {'note': 1});
    expect(preview.resolution, SyncConflictResolution.newest);
  });

  test('preferRemote and preferLocal replace only divergent records', () {
    final local = [note('a', 'n1', content: 'local'), note('a', 'n2', content: 'same')];
    final remote = [note('a', 'n1', content: 'cloud'), note('a', 'n2', content: 'same')];
    final merged = mergeSyncRecords(local, remote);

    final preferRemote = resolveSyncConflicts(
        local: local,
        remote: remote,
        merged: merged,
        resolution: SyncConflictResolution.preferRemote);
    expect(
        preferRemote.singleWhere((r) => r.id.endsWith('n1')).data['content'],
        'cloud');
    expect(
        preferRemote.singleWhere((r) => r.id.endsWith('n2')).data['content'],
        'same');

    final preferLocal = resolveSyncConflicts(
        local: local,
        remote: remote,
        merged: merged,
        resolution: SyncConflictResolution.preferLocal);
    expect(
        preferLocal.singleWhere((r) => r.id.endsWith('n1')).data['content'],
        'local');
  });

  test('newest keeps the clock winner', () {
    final local = [note('a', 'n1', content: 'local', clock: 1000)];
    final remote = [note('a', 'n1', content: 'cloud', clock: 2000)];
    final merged = resolveSyncConflicts(
        local: local,
        remote: remote,
        merged: mergeSyncRecords(local, remote),
        resolution: SyncConflictResolution.newest);
    expect(merged.single.data['content'], 'cloud');
  });

  test('latestSyncRecordTime ignores secret envelopes and empty lists', () {
    expect(latestSyncRecordTime(const []), isNull);
    final stamp = latestSyncRecordTime([
      RowSyncRecord('secret', 'x', 9000, 'r', false, const {}),
      RowSyncRecord('book', 'md5:a', 4000, 'r', false, const {}),
    ]);
    expect(stamp!.millisecondsSinceEpoch, 4000);
  });
}
