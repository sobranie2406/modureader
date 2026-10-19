import 'dart:convert';
import 'package:anx_reader/models/narration_position.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/sync_paths.dart';

const syncRecordsTable = 'modu_sync_records';
const _control = 'modu_sync_control';
const _now = "CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)";
const _tick = 'UPDATE $_control SET clock = MAX(clock + 1, $_now);';
const _clock = '(SELECT clock FROM $_control)';
const _active = '(SELECT applying FROM $_control) = 0';

const _fields = <String, List<String>>{
  'group': ['name', 'parent_id', 'is_deleted', 'create_time', 'update_time'],
  'book': [
    'title',
    'cover_path',
    'file_path',
    'author',
    'description',
    'rating',
    'group_id',
    'file_md5',
    'create_time',
    'update_time'
  ],
  'position': ['last_read_position', 'reading_percentage'],
  'life': ['is_deleted'],
  'review': ['review'],
  'note': [
    'book_id',
    'content',
    'cfi',
    'chapter',
    'type',
    'color',
    'create_time',
    'update_time',
    'reader_note'
  ],
  'time': ['book_id', 'date', 'reading_time', 'round'],
  // Reading rounds are synced as their own kind. `total_reading_time` is
  // intentionally NOT synced: it is derived from the synced `time` rows so two
  // devices finishing the same round cannot fight over a stored total.
  'round': [
    'book_id',
    'round_number',
    'status',
    'start_time',
    'end_time',
    'start_percentage',
    'end_percentage',
    'end_position'
  ],
  // tb_styles is also used for tags. ONLY the two tag sentinels are portable;
  // ordinary font/typography styles are deliberately excluded.
  'tag': ['font_size', 'font_family', 'line_height'],
  'tag_link': ['font_size', 'line_height', 'letter_spacing'],
  'secret': ['encrypted_payload', 'updated_at'],
};
const _tables = <String, String>{
  'group': 'tb_groups',
  'book': 'tb_books',
  'position': 'tb_books',
  'life': 'tb_books',
  'review': 'tb_books',
  'note': 'tb_notes',
  'time': 'tb_reading_time',
  'round': 'tb_reading_rounds',
  'tag': 'tb_styles',
  'tag_link': 'tb_styles',
  'secret': 'tb_sync_secrets',
};
const _refs = <String, Map<String, String>>{
  'group': {'parent_id': 'group'},
  'book': {'group_id': 'group'},
  'note': {'book_id': 'book'},
  'time': {'book_id': 'book'},
  'round': {'book_id': 'book'},
  'tag_link': {'line_height': 'book', 'letter_spacing': 'tag'},
};

String _hash(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();
String _bookKey(Map<String, Object?> row) =>
    (row['file_md5'] as String? ?? '').isNotEmpty
        ? 'md5:${(row['file_md5'] as String).toLowerCase()}'
        : 'path:${row['file_path']}';
String _sqlBookKey(String row) => "CASE WHEN COALESCE($row.file_md5, '') != '' "
    "THEN 'md5:' || lower($row.file_md5) ELSE 'path:' || $row.file_path END";

/// Tracks changes in the SAME SQLite transaction as existing DAO writes.
/// Applying remote data suppresses triggers only inside its write transaction.
/// Local integer IDs are retained, including while reading/indexing is active.
class RowSyncStore {
  RowSyncStore(this.db);
  final Database db;

  static Future<void> install(DatabaseExecutor db) async {
    final exists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [_control]);
    if (exists.isNotEmpty) return;
    await db.execute(
        'CREATE TABLE $_control (applying INTEGER NOT NULL, clock INTEGER NOT NULL)');
    await db.insert(_control, {'applying': 0, 'clock': 0});
    await db.execute('''CREATE TABLE $syncRecordsTable (
      kind TEXT NOT NULL, sync_id TEXT NOT NULL, local_id INTEGER,
      clock INTEGER NOT NULL, revision TEXT NOT NULL, deleted INTEGER NOT NULL,
      payload TEXT NOT NULL DEFAULT '{}', dirty INTEGER NOT NULL DEFAULT 1,
      narration TEXT,
      PRIMARY KEY(kind, sync_id), UNIQUE(kind, local_id))''');
    await db.execute('''CREATE TABLE IF NOT EXISTS tb_sync_secrets (
      id TEXT PRIMARY KEY NOT NULL, encrypted_payload TEXT NOT NULL, updated_at TEXT NOT NULL)''');

    final identities = <String, Map<int, String>>{};
    for (final kind in _tables.keys) {
      if (kind == 'secret' || kind == 'review') continue;
      // Reading rounds are created by a later app schema migration; a v7/v8
      // install must skip the missing table and let ensureRounds() add it.
      if (!await _tableExists(db, _tables[kind]!)) continue;
      final rows = await db.query(_tables[kind]!, where: _filter(kind));
      final ids = identities.putIfAbsent(kind, () => {});
      for (final row in rows) {
        final id = row['id'] as int;
        String key;
        switch (kind) {
          case 'book':
          case 'position':
          case 'life':
            key = _bookKey(row);
          case 'group':
            key = id == 0
                ? 'root'
                : 'legacy:${_hash([id, row['name'], row['create_time']])}';
          case 'note':
            key = 'legacy:${_hash([
                  identities['book']![row['book_id']],
                  id,
                  row['cfi'],
                  row['create_time']
                ])}';
          case 'time':
            key = 'legacy:${_hash([
                  identities['book']![row['book_id']],
                  (row['date'] as String).substring(0, 10)
                ])}';
          case 'round':
            key =
                '${identities['book']![row['book_id']]}:r${row['round_number']}';
          case 'tag':
            key =
                'legacy:${_hash((row['font_family'] as String).toLowerCase())}';
          case 'tag_link':
            key =
                '${identities['book']![(row['line_height'] as num).toInt()]}:${identities['tag']![(row['letter_spacing'] as num).toInt()]}';
          default:
            throw StateError('Unknown sync kind');
        }
        ids[id] = key;
        final timestamp = DateTime.tryParse(
            ((kind == 'life' && row['is_deleted'] != 1
                    ? row['create_time']
                    : null) ??
                row['update_time'] ??
                row['create_time'] ??
                row['date'] ??
                '') as String);
        final clock = timestamp?.toUtc().millisecondsSinceEpoch ?? 0;
        // An old database can contain multiple same-day rows. Collapse them
        // before assigning the common legacy baseline identity.
        final previous = await db.query(syncRecordsTable,
            where: 'kind = ? AND sync_id = ?', whereArgs: [kind, key]);
        if (previous.isNotEmpty) {
          if (kind != 'time') throw StateError('同步迁移发现重复的 $kind 标识，请先备份并检查书库');
          final existingId = previous.single['local_id'];
          await db.rawUpdate(
              'UPDATE tb_reading_time SET reading_time = reading_time + ? WHERE id = ?',
              [row['reading_time'], existingId]);
          await db.delete('tb_reading_time', where: 'id = ?', whereArgs: [id]);
          continue;
        }
        await db.insert(syncRecordsTable, {
          'kind': kind,
          'sync_id': key,
          'local_id': id,
          'clock': clock,
          'revision': 'legacy',
          'deleted': 0
        });
      }
    }
    for (final kind
        in _tables.keys.where((k) => k != 'secret' && k != 'review')) {
      if (!await _tableExists(db, _tables[kind]!)) continue;
      await _installTriggers(db, kind);
    }
    await db.execute(
        'UPDATE $_control SET clock=COALESCE((SELECT MAX(clock) FROM $syncRecordsTable),0)');
    await ensureReviews(db);
  }

  static String? _filter(String kind) => switch (kind) {
        'tag' => 'font_size = 1 AND font_family IS NOT NULL',
        'tag_link' => 'font_size = 2',
        _ => null,
      };

  static Future<void> _installTriggers(DatabaseExecutor db, String kind) async {
    final table = _tables[kind]!;
    final filter = kind == 'tag'
        ? 'AND NEW.font_size = 1 AND NEW.font_family IS NOT NULL'
        : kind == 'tag_link'
            ? 'AND NEW.font_size = 2'
            : '';
    final key = switch (kind) {
      'book' || 'position' || 'life' => _sqlBookKey('NEW'),
      'group' =>
        "CASE WHEN NEW.id = 0 THEN 'root' ELSE lower(hex(randomblob(16))) END",
      // A round is identified by its book identity + round number. Both devices
      // finishing the same round therefore resolve to the SAME sync record.
      'round' =>
        "(SELECT sync_id FROM $syncRecordsTable WHERE kind='book' AND local_id=NEW.book_id) || ':r' || NEW.round_number",
      'tag_link' =>
        "(SELECT sync_id FROM $syncRecordsTable WHERE kind='book' AND local_id=CAST(NEW.line_height AS INTEGER)) || ':' || "
            "(SELECT sync_id FROM $syncRecordsTable WHERE kind='tag' AND local_id=CAST(NEW.letter_spacing AS INTEGER))",
      _ => 'lower(hex(randomblob(16)))',
    };
    await db
        .execute('''CREATE TRIGGER modu_${kind}_insert AFTER INSERT ON $table
      WHEN $_active $filter BEGIN $_tick
      INSERT OR IGNORE INTO $syncRecordsTable(kind,sync_id,local_id,clock,revision,deleted,dirty)
      VALUES('$kind',$key,NEW.id,$_clock,lower(hex(randomblob(16))),0,1);
      UPDATE $syncRecordsTable SET local_id=NEW.id,clock=$_clock,
        revision=lower(hex(randomblob(16))),deleted=0,dirty=1
        WHERE kind='$kind' AND sync_id=$key;
      END''');
    final changed = _fields[kind]!
        .where((f) => f != 'update_time')
        .map((f) => 'OLD.$f IS NOT NEW.$f')
        .join(' OR ');
    await db
        .execute('''CREATE TRIGGER modu_${kind}_update AFTER UPDATE ON $table
      WHEN $_active $filter AND ($changed) BEGIN $_tick
      UPDATE $syncRecordsTable SET clock=$_clock,revision=lower(hex(randomblob(16))),dirty=1
      WHERE kind='$kind' AND local_id=NEW.id; END''');
    await db
        .execute('''CREATE TRIGGER modu_${kind}_delete BEFORE DELETE ON $table
      WHEN $_active BEGIN $_tick
      UPDATE $syncRecordsTable SET clock=$_clock,revision=lower(hex(randomblob(16))),
        deleted=1,dirty=0,local_id=NULL WHERE kind='$kind' AND local_id=OLD.id; END''');
  }

  Future<List<RowSyncRecord>> snapshot() => db.transaction(_snapshot);

  /// Called inside the round transaction, including when the cursor was empty.
  static Future<void> markPositionReset(DatabaseExecutor db, int bookId) async {
    await db.execute(_tick);
    await db.rawUpdate(
        'UPDATE $syncRecordsTable SET clock=$_clock, '
        "revision=? || lower(hex(randomblob(16))), dirty=1 "
        "WHERE kind='position' AND local_id=? AND deleted=0",
        [syncPositionResetPrefix, bookId]);
  }

  static Future<List<RowSyncRecord>> _snapshot(Transaction txn) async {
    final metadata = await txn.query(syncRecordsTable);
    final ids = <String, Map<int, String>>{};
    for (final row in metadata) {
      if (row['local_id'] != null) {
        ids.putIfAbsent(
                row['kind'] as String, () => {})[row['local_id'] as int] =
            row['sync_id'] as String;
      }
    }
    for (final meta
        in metadata.where((r) => r['dirty'] == 1 && r['deleted'] == 0)) {
      final kind = meta['kind'] as String;
      final rows = await txn.query(_tables[kind]!,
          where: 'id = ?', whereArgs: [meta['local_id']]);
      if (rows.length != 1) throw StateError('同步记录缺少本地数据');
      final row = rows.single;
      final data = {for (final field in _fields[kind]!) field: row[field]};
      if (kind == 'time' && data['round'] == null) data['round'] = 1;
      if (kind == 'review' && data['review'] == null) data['review'] = '';
      for (final ref in (_refs[kind] ?? const <String, String>{}).entries) {
        final id = (data[ref.key] as num?)?.toInt();
        data[ref.key] = id == null ? null : ids[ref.value]?[id];
        if (id != null && data[ref.key] == null) throw StateError('同步记录缺少关联标识');
      }
      await txn.update(
          syncRecordsTable,
          {
            'payload': jsonEncode(normalizeSyncReadingPosition(RowSyncRecord(
                    kind,
                    meta['sync_id'] as String,
                    meta['clock'] as int,
                    meta['revision'] as String,
                    false,
                    data))
                .data),
            'dirty': 0
          },
          where: 'kind = ? AND sync_id = ?',
          whereArgs: [kind, meta['sync_id']]);
    }
    final records =
        (await txn.query(syncRecordsTable)).map(RowSyncRecord.fromMap).toList();
    // Already encrypted by the opt-in settings service; never export prefs.
    for (final secret in await txn.query('tb_sync_secrets')) {
      records.add(RowSyncRecord(
          'secret',
          secret['id'] as String,
          DateTime.parse(secret['updated_at'] as String)
              .toUtc()
              .millisecondsSinceEpoch,
          _hash(secret['encrypted_payload']!),
          false,
          {for (final f in _fields['secret']!) f: secret[f]}));
    }
    records.sort((a, b) => a.key.compareTo(b.key));
    return records;
  }

  static Future<void> touchPosition(DatabaseExecutor txn, int bookId) async {
    await txn.execute(_tick);
    await txn.rawUpdate(
        'UPDATE $syncRecordsTable SET clock=$_clock, '
        "revision=lower(hex(randomblob(16))),dirty=1 WHERE kind='position' AND local_id=?",
        [bookId]);
  }

  static Future<void> installNarration(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info($syncRecordsTable)');
    if (!columns.any((row) => row['name'] == 'narration')) {
      await db
          .execute('ALTER TABLE $syncRecordsTable ADD COLUMN narration TEXT');
    }
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [table]);
    return rows.isNotEmpty;
  }

  /// Called inside a transaction after the review column exists. An untouched
  /// empty review is not an edit and must never erase another device's review.
  static Future<void> ensureReviews(DatabaseExecutor db) async {
    if (!await _tableExists(db, _control)) return;
    final columns = await db.rawQuery('PRAGMA table_info(tb_books)');
    if (!columns.any((row) => row['name'] == 'review')) return;
    final installed = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='trigger' AND name='modu_review_update'");
    if (installed.isNotEmpty) return;
    await db.execute('''INSERT OR IGNORE INTO $syncRecordsTable
      (kind,sync_id,local_id,clock,revision,deleted,dirty)
      SELECT 'review',r.sync_id,b.id,
        COALESCE(CAST((julianday(b.update_time)-2440587.5)*86400000 AS INTEGER),r.clock),
        'legacy',0,1
      FROM tb_books b JOIN $syncRecordsTable r
        ON r.kind='book' AND r.local_id=b.id
      WHERE COALESCE(b.review,'') != '' ''');
    await db.execute('UPDATE $_control SET clock=MAX(clock, '
        'COALESCE((SELECT MAX(clock) FROM $syncRecordsTable),0))');
    final key = "COALESCE((SELECT sync_id FROM $syncRecordsTable "
        "WHERE kind='book' AND local_id=NEW.id), ${_sqlBookKey('NEW')})";
    for (final operation in ['insert', 'update']) {
      final changed = operation == 'insert'
          ? "COALESCE(NEW.review,'') != ''"
          : "COALESCE(OLD.review,'') IS NOT COALESCE(NEW.review,'')";
      await db.execute('''CREATE TRIGGER modu_review_$operation
        AFTER ${operation.toUpperCase()} ON tb_books
        WHEN $_active AND ($changed) BEGIN $_tick
        INSERT OR IGNORE INTO $syncRecordsTable
          (kind,sync_id,local_id,clock,revision,deleted,dirty)
          VALUES('review',$key,NEW.id,$_clock,lower(hex(randomblob(16))),0,1);
        UPDATE $syncRecordsTable SET local_id=NEW.id,clock=$_clock,
          revision=lower(hex(randomblob(16))),deleted=0,dirty=1
          WHERE kind='review' AND sync_id=$key;
        END''');
    }
    await db
        .execute('''CREATE TRIGGER modu_review_delete BEFORE DELETE ON tb_books
      WHEN $_active BEGIN $_tick
      UPDATE $syncRecordsTable SET clock=$_clock,revision=lower(hex(randomblob(16))),
        deleted=1,dirty=0,local_id=NULL WHERE kind='review' AND local_id=OLD.id;
      END''');
  }

  /// v9 reading-round sync migration. Called on every database open and
  /// idempotent:
  ///
  /// - re-creates the `time` triggers so a `round` change marks the record dirty
  /// - installs the `round` kind triggers/identities
  /// - backfills `round` records for rounds written before this upgrade
  /// - backfills `time.payload.round` from the local row
  ///
  /// Nothing here changes a single reading-time row; only sync metadata.
  static Future<void> ensureRounds(DatabaseExecutor db) async {
    if (!await _tableExists(db, _control)) return;
    if (!await _tableExists(db, _tables['round']!)) return;

    final roundTrigger = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='trigger' AND name='modu_round_insert'");
    final timeTrigger = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='trigger' AND name='modu_time_update'");
    final timeHasRound = timeTrigger.isNotEmpty &&
        (timeTrigger.single['sql'] as String? ?? '').contains('NEW.round');
    if (roundTrigger.isNotEmpty && timeHasRound) return;

    for (final suffix in ['insert', 'update', 'delete']) {
      await db.execute('DROP TRIGGER IF EXISTS modu_time_$suffix');
      await db.execute('DROP TRIGGER IF EXISTS modu_round_$suffix');
    }
    await _installTriggers(db, 'time');
    await _installTriggers(db, 'round');
    await _backfillRoundRecords(db);
    await _backfillTimeRounds(db);
    await db.execute('UPDATE $_control SET clock = MAX(clock, '
        'COALESCE((SELECT MAX(clock) FROM $syncRecordsTable), 0))');
  }

  static Future<void> _backfillRoundRecords(DatabaseExecutor db) async {
    final books = await db.query(syncRecordsTable,
        columns: ['sync_id', 'local_id'],
        where: "kind='book' AND deleted=0 AND local_id IS NOT NULL");
    final bookSync = {
      for (final row in books) row['local_id'] as int: row['sync_id'] as String
    };
    final rounds = await db.query(_tables['round']!);
    for (final row in rounds) {
      final id = row['id'] as int?;
      final bookId = row['book_id'] as int?;
      if (id == null || bookId == null) continue;
      final bookKey = bookSync[bookId];
      if (bookKey == null) continue;
      final key = '$bookKey:r${row['round_number'] ?? 1}';
      final clock = DateTime.tryParse(row['update_time'] as String? ?? '')
              ?.millisecondsSinceEpoch ??
          0;
      final existing = await db.query(syncRecordsTable,
          where: "kind='round' AND sync_id=?", whereArgs: [key]);
      if (existing.isEmpty) {
        await db.insert(syncRecordsTable, {
          'kind': 'round',
          'sync_id': key,
          'local_id': id,
          'clock': clock,
          'revision': 'legacy',
          'deleted': 0,
          'payload': '{}',
          'dirty': 1,
        });
      } else if (existing.single['local_id'] != id) {
        await db.update(
            syncRecordsTable, {'local_id': id, 'clock': clock, 'dirty': 1},
            where: "kind='round' AND sync_id=?", whereArgs: [key]);
      }
    }
  }

  static Future<void> _backfillTimeRounds(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
        'SELECT r.sync_id, r.payload, r.local_id, r.deleted, t.round '
        'FROM $syncRecordsTable r LEFT JOIN ${_tables['time']} t '
        'ON t.id = r.local_id WHERE r.kind = ?',
        ['time']);
    for (final row in rows) {
      if (row['deleted'] == 1 || row['local_id'] == null) continue;
      final round = (row['round'] as num?)?.toInt() ?? 1;
      final payload =
          jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      if (payload['round'] == round) continue;
      payload['round'] = round;
      await db.update(
          syncRecordsTable, {'payload': jsonEncode(payload), 'dirty': 1},
          where: "kind='time' AND sync_id=?", whereArgs: [row['sync_id']]);
    }
  }

  /// Merge into live rows in one transaction, including changes made while
  /// the network request was in flight. No closing/replacing the live DB.
  Future<List<RowSyncRecord>> merge(List<RowSyncRecord> remote,
      {bool importOnlyMissingRecords = false}) async {
    remote = remote.map(normalizeRoundFields).toList();
    for (final record in remote) {
      validate(record);
    }
    return db.transaction((txn) async {
      final local = await _snapshot(txn);
      var merged = mergeSyncRecords(local, remote);
      if (importOnlyMissingRecords) {
        // A one-off external library import is not a remote editing device.
        // Resolve aliases first, then preserve the latest local records inside
        // this same transaction (including edits made during file copying).
        final protected = mergeSyncRecords(
            local, merged.where((r) => bookSyncAliasTarget(r) != null));
        final keys = protected.map((r) => r.key).toSet();
        merged = mergeSyncRecords(
            merged.where((r) => !keys.contains(r.key)), protected);
      }
      for (final record in merged) {
        validate(record);
      }
      final old = {for (final r in local) r.key: jsonEncode(r.toMap())};
      await txn.update(_control, {'applying': 1});
      if (await _rebindBookAliases(txn, merged)) old.clear();
      final ids = <String, Map<String, int>>{};
      final allocated = <String>{};
      for (final row in await txn.query(syncRecordsTable)) {
        if (row['local_id'] != null) {
          ids.putIfAbsent(
                  row['kind'] as String, () => {})[row['sync_id'] as String] =
              row['local_id'] as int;
        }
      }
      // Allocate IDs first: references never depend on a remote numeric ID or
      // on group parent ordering. Existing IDs are never renumbered.
      for (final kind in [
        'group',
        'book',
        'round',
        'note',
        'time',
        'tag',
        'tag_link'
      ]) {
        final map = ids.putIfAbsent(kind, () => {});
        for (final r in merged.where((r) =>
            r.kind == kind &&
            bookSyncAliasTarget(r) == null &&
            (!r.deleted || kind == 'group' || kind == 'book'))) {
          if (map.containsKey(r.id)) continue;
          final table = _tables[kind]!;
          final inserted = await txn.insert(
              table,
              kind == 'group' && r.id == 'root'
                  ? {'id': 0}
                  : <String, Object?>{'id': null});
          map[r.id] = inserted;
          allocated.add(r.key);
          old.remove(r.key);
        }
      }
      for (final r in merged) {
        final rebind = (_refs[r.kind] ?? const <String, String>{}).entries.any(
                (ref) =>
                    allocated.contains('${ref.value}/${r.data[ref.key]}')) ||
            (const ['position', 'life', 'review'].contains(r.kind) &&
                allocated.contains('book/${r.id}'));
        if (old[r.key] == jsonEncode(r.toMap()) && !rebind) continue;
        if (r.kind == 'secret') {
          await txn.insert('tb_sync_secrets', {'id': r.id, ...r.data},
              conflictAlgorithm: ConflictAlgorithm.replace);
          continue;
        }
        final kind = r.kind;
        final id = ids[const ['position', 'life', 'review'].contains(kind)
            ? 'book'
            : kind]?[r.id];
        if (r.deleted) {
          if (id != null) {
            if (kind == 'book' || kind == 'life') {
              await txn.update('tb_books', {'is_deleted': 1},
                  where: 'id=?', whereArgs: [id]);
            } else if (kind == 'group') {
              await txn.update('tb_groups', {'is_deleted': 1},
                  where: 'id=?', whereArgs: [id]);
            } else if (kind == 'review') {
              if (bookSyncAliasTarget(r) == null) {
                await txn.update('tb_books', {'review': ''},
                    where: 'id=?', whereArgs: [id]);
              }
            } else if (kind != 'position') {
              await txn.delete(_tables[kind]!, where: 'id=?', whereArgs: [id]);
            }
          }
        } else {
          if (id == null) throw const FormatException('同步记录缺少关联书籍');
          final values = Map<String, Object?>.from(r.data);
          if (kind == 'round') {
            // These local model fields are not part of the wire payload.
            final timestamp =
                DateTime.fromMillisecondsSinceEpoch(r.clock, isUtc: true)
                    .toIso8601String();
            values['create_time'] = values['start_time'] ?? timestamp;
            values['update_time'] = timestamp;
          }
          for (final ref in (_refs[kind] ?? const <String, String>{}).entries) {
            final key = values[ref.key];
            values[ref.key] = key == null ? null : ids[ref.value]?[key];
            if (key != null && values[ref.key] == null) {
              throw const FormatException('同步记录关联无效');
            }
          }
          await txn
              .update(_tables[kind]!, values, where: 'id=?', whereArgs: [id]);
        }
        await txn.insert(
            syncRecordsTable,
            {
              ...r.toMap(),
              'local_id':
                  r.deleted && kind != 'group' && kind != 'book' ? null : id,
              'dirty': 0
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      final maxClock = merged.fold<int>(0, (v, r) => v > r.clock ? v : r.clock);
      await txn.rawUpdate(
          'UPDATE $_control SET applying=0, clock=MAX(clock,?)', [maxClock]);
      return merged;
    });
  }

  // Repair only identity/index rows inside the same merge transaction. Keep
  // the oldest existing local book row (and its local reader settings), move
  // references to it, and soft-hide redundant rows; never delete book files.
  static Future<bool> _rebindBookAliases(
      Transaction txn, List<RowSyncRecord> merged) async {
    final groups = <String, List<String>>{};
    for (final r in merged.where((r) => r.kind == 'book')) {
      final target = bookSyncAliasTarget(r);
      if (target != null) groups.putIfAbsent(target, () => []).add(r.id);
    }
    if (groups.isEmpty) return false;
    final metadata = await txn.query(syncRecordsTable);
    final visibleBooks =
        (await txn.query('tb_books', columns: ['id'], where: 'is_deleted=0'))
            .map((r) => r['id'])
            .toSet();
    final byKey = {for (final r in merged) r.key: r};
    var changed = false;
    for (final entry in groups.entries) {
      final canonical = entry.key;
      final aliases = entry.value..sort();
      final members = {canonical, ...aliases};
      final related = metadata
          .where((r) =>
              const ['book', 'position', 'life', 'review']
                  .contains(r['kind']) &&
              members.contains(r['sync_id']))
          .toList();
      final needsRepair = related.any((r) =>
          aliases.contains(r['sync_id']) &&
          (bookSyncAliasTarget(RowSyncRecord.fromMap(r)) == null ||
              (r['kind'] == 'book' && visibleBooks.contains(r['local_id']))));
      if (!needsRepair) continue;
      final book = byKey['book/$canonical'];
      if (book == null || bookSyncAliasTarget(book) != null) {
        throw const FormatException('书籍同步关联缺少目标');
      }
      final localBooks = related
          .where((r) => r['kind'] == 'book' && r['local_id'] != null)
          .map((r) => r['local_id'] as int)
          .toSet()
          .toList()
        ..sort();
      if (localBooks.isEmpty) continue;
      final keep = localBooks.first;
      for (final id in localBooks.skip(1)) {
        for (final table in ['tb_notes', 'tb_reading_time']) {
          await txn.update(table, {'book_id': keep},
              where: 'book_id=?', whereArgs: [id]);
        }
        await txn.update('tb_styles', {'line_height': keep.toDouble()},
            where: 'font_size=2 AND line_height=?', whereArgs: [id]);
        await txn.update('tb_books', {'is_deleted': 1},
            where: 'id=?', whereArgs: [id]);
      }
      // Release the UNIQUE(kind, local_id) bindings before installing the
      // canonical identity. Local row IDs themselves are never rewritten.
      for (final row in related) {
        await txn.delete(syncRecordsTable,
            where: 'kind=? AND sync_id=?',
            whereArgs: [row['kind'], row['sync_id']]);
      }
      await txn.insert(syncRecordsTable, {
        ...book.toMap(),
        'local_id': keep,
        'dirty': 0,
      });
      final spare = localBooks.skip(1).toList();
      for (var i = 0; i < aliases.length; i++) {
        final marker = byKey['book/${aliases[i]}']!;
        await txn.insert(syncRecordsTable, {
          ...marker.toMap(),
          'local_id': i < spare.length ? spare[i] : null,
          'dirty': 0,
        });
      }
      changed = true;
    }
    // Composite IDs include the book identity. Remove superseded rows while
    // triggers are suppressed; their canonical winners are materialized above.
    for (final row in metadata.where((r) =>
        const ['tag_link', 'round'].contains(r['kind']) &&
        !byKey.containsKey('${r['kind']}/${r['sync_id']}'))) {
      final kind = row['kind'] as String;
      if (row['local_id'] != null) {
        await txn.delete(_tables[kind]!,
            where: kind == 'tag_link' ? 'id=? AND font_size=2' : 'id=?',
            whereArgs: [row['local_id']]);
      }
      await txn.delete(syncRecordsTable,
          where: 'kind=? AND sync_id=?', whereArgs: [kind, row['sync_id']]);
      changed = true;
    }
    return changed;
  }

  static void validate(RowSyncRecord r) {
    if (r.narration != null) {
      if (r.kind != 'position') {
        throw const FormatException('Narration must belong to a book position');
      }
      NarrationPosition.decode(r.narration!.encode());
    }
    bookSyncAliasTarget(r); // Validate reserved redirects before materializing.
    final fields = _fields[r.kind];
    if (fields == null ||
        r.id.isEmpty ||
        r.id.length > 4096 ||
        r.clock < 0 ||
        r.clock > 8640000000000000 ||
        r.revision.isEmpty) {
      throw const FormatException('不支持的同步记录');
    }
    if (r.data.keys.toSet().difference(fields.toSet()).isNotEmpty ||
        r.data.values.any((v) => v != null && v is! String && v is! num) ||
        r.data.values.whereType<num>().any((v) => !v.isFinite)) {
      throw const FormatException('同步字段类型无效');
    }
    if (r.deleted) return;
    if (fields.any((f) => !r.data.containsKey(f))) {
      throw const FormatException('同步字段无效');
    }
    for (final ref in (_refs[r.kind] ?? const <String, String>{}).keys) {
      final value = r.data[ref];
      if (value != null && value is! String) {
        throw const FormatException('关联标识无效');
      }
    }
    if (r.kind == 'position') {
      final progress = r.data['reading_percentage'];
      if (r.data['last_read_position'] is! String ||
          progress is! num ||
          !progress.isFinite ||
          progress < 0 ||
          progress > 1) {
        throw const FormatException('阅读位置无效');
      }
    }
    if (r.kind == 'life' && ![0, 1].contains(r.data['is_deleted'])) {
      throw const FormatException('删除状态无效');
    }
    if (r.kind == 'review' && r.data['review'] is! String) {
      throw const FormatException('书评内容无效');
    }
    for (final field in ['create_time', 'update_time', 'date', 'updated_at']) {
      final value = r.data[field];
      if (value != null &&
          (value is! String || DateTime.tryParse(value) == null)) {
        throw const FormatException('同步时间格式无效');
      }
    }
    if (r.kind == 'book') {
      if (r.data['file_md5'] != null && r.data['file_md5'] is! String) {
        throw const FormatException('书籍内容校验值无效');
      }
      final file = r.data['file_path'];
      final cover = r.data['cover_path'];
      if (file is! String || !file.startsWith('file/')) {
        throw const FormatException('书籍路径无效');
      }
      SyncPaths.data(file);
      if (cover != null && cover != '') {
        if (cover is! String || !cover.startsWith('cover/')) {
          throw const FormatException('封面路径无效');
        }
        SyncPaths.data(cover);
      }
    }
    if (r.kind == 'time' &&
        (r.data['reading_time'] is! int ||
            (r.data['reading_time'] as int) < 0)) {
      throw const FormatException('阅读时长无效');
    }
    if (r.kind == 'time' &&
        (r.data['round'] is! int || (r.data['round'] as int) < 1)) {
      throw const FormatException('阅读轮次无效');
    }
    if (r.kind == 'round') {
      final number = r.data['round_number'];
      final status = r.data['status'];
      if (number is! int ||
          number < 1 ||
          !const ['reading', 'finished', 'cancelled'].contains(status)) {
        throw const FormatException('轮次记录无效');
      }
      for (final field in ['start_percentage', 'end_percentage']) {
        final value = r.data[field];
        if (value is! num || !value.isFinite || value < 0 || value > 1) {
          throw const FormatException('轮次进度无效');
        }
      }
      final position = r.data['end_position'];
      if (position != null && position is! String) {
        throw const FormatException('轮次阅读位置无效');
      }
      for (final field in ['start_time', 'end_time']) {
        final value = r.data[field];
        if (value != null &&
            (value is! String || DateTime.tryParse(value) == null)) {
          throw const FormatException('轮次时间无效');
        }
      }
    }
    if (r.kind == 'secret') {
      final envelope = jsonDecode(r.data['encrypted_payload'] as String) as Map;
      if (envelope['algorithm'] != 'AES-256-GCM' ||
          envelope['ciphertext'] is! String ||
          envelope['mac'] is! String) {
        throw const FormatException('同步密钥必须加密');
      }
    }
  }
}
