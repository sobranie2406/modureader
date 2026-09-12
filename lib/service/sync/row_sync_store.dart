import 'dart:convert';
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
  'time': ['book_id', 'date', 'reading_time'],
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
  'note': 'tb_notes',
  'time': 'tb_reading_time',
  'tag': 'tb_styles',
  'tag_link': 'tb_styles',
  'secret': 'tb_sync_secrets',
};
const _refs = <String, Map<String, String>>{
  'group': {'parent_id': 'group'},
  'book': {'group_id': 'group'},
  'note': {'book_id': 'book'},
  'time': {'book_id': 'book'},
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
      PRIMARY KEY(kind, sync_id), UNIQUE(kind, local_id))''');
    await db.execute('''CREATE TABLE IF NOT EXISTS tb_sync_secrets (
      id TEXT PRIMARY KEY NOT NULL, encrypted_payload TEXT NOT NULL, updated_at TEXT NOT NULL)''');

    final identities = <String, Map<int, String>>{};
    for (final kind in _tables.keys) {
      if (kind == 'secret') continue; // Secret row has a fixed string ID.
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
    for (final kind in _tables.keys.where((k) => k != 'secret')) {
      await _installTriggers(db, kind);
    }
    await db.execute(
        'UPDATE $_control SET clock=COALESCE((SELECT MAX(clock) FROM $syncRecordsTable),0)');
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

  /// Merge into live rows in one transaction, including changes made while
  /// the network request was in flight. No closing/replacing the live DB.
  Future<List<RowSyncRecord>> merge(List<RowSyncRecord> remote) async {
    remote = remote.map(normalizeSyncReadingPosition).toList();
    for (final record in remote) {
      validate(record);
    }
    return db.transaction((txn) async {
      final local = await _snapshot(txn);
      final merged = mergeSyncRecords(local, remote);
      for (final record in merged) {
        validate(record);
      }
      final old = {for (final r in local) r.key: jsonEncode(r.toMap())};
      await txn.update(_control, {'applying': 1});
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
      for (final kind in ['group', 'book', 'note', 'time', 'tag', 'tag_link']) {
        final map = ids.putIfAbsent(kind, () => {});
        for (final r in merged.where((r) =>
            r.kind == kind &&
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
            (const ['position', 'life'].contains(r.kind) &&
                allocated.contains('book/${r.id}'));
        if (old[r.key] == jsonEncode(r.toMap()) && !rebind) continue;
        if (r.kind == 'secret') {
          await txn.insert('tb_sync_secrets', {'id': r.id, ...r.data},
              conflictAlgorithm: ConflictAlgorithm.replace);
          continue;
        }
        final kind = r.kind;
        final id =
            ids[kind == 'position' || kind == 'life' ? 'book' : kind]?[r.id];
        if (r.deleted) {
          if (id != null) {
            if (kind == 'book' || kind == 'life') {
              await txn.update('tb_books', {'is_deleted': 1},
                  where: 'id=?', whereArgs: [id]);
            } else if (kind == 'group') {
              await txn.update('tb_groups', {'is_deleted': 1},
                  where: 'id=?', whereArgs: [id]);
            } else if (kind != 'position') {
              await txn.delete(_tables[kind]!, where: 'id=?', whereArgs: [id]);
            }
          }
        } else {
          if (id == null) throw const FormatException('同步记录缺少关联书籍');
          final values = Map<String, Object?>.from(r.data);
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

  static void validate(RowSyncRecord r) {
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
    for (final field in ['create_time', 'update_time', 'date', 'updated_at']) {
      final value = r.data[field];
      if (value != null &&
          (value is! String || DateTime.tryParse(value) == null)) {
        throw const FormatException('同步时间格式无效');
      }
    }
    if (r.kind == 'book') {
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
