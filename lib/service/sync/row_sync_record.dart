import 'dart:convert';
import 'package:anx_reader/utils/reading_progress.dart';

/// Portable identity and operation clock; never a device-local integer row ID.
class RowSyncRecord {
  const RowSyncRecord(
      this.kind, this.id, this.clock, this.revision, this.deleted, this.data);

  final String kind;
  final String id;
  final int clock;
  final String revision;
  final bool deleted;
  final Map<String, Object?> data;
  String get key => '$kind/$id';

  Map<String, Object?> toMap() => {
        'kind': kind,
        'sync_id': id,
        'clock': clock,
        'revision': revision,
        'deleted': deleted ? 1 : 0,
        'payload': jsonEncode(data),
      };

  factory RowSyncRecord.fromMap(Map<String, Object?> row) {
    return normalizeSyncReadingPosition(RowSyncRecord(
      row['kind'] as String,
      row['sync_id'] as String,
      row['clock'] as int,
      row['revision'] as String,
      row['deleted'] == 1,
      Map<String, Object?>.from(jsonDecode(row['payload'] as String) as Map),
    ));
  }
}

/// Canonicalize only the two legacy nullable position fields. Keep identities,
/// clocks and revisions unchanged: compatibility repair is not a new read.
/// Missing keys, wrong types and extra fields are left for strict validation.
RowSyncRecord normalizeSyncReadingPosition(RowSyncRecord record) {
  if (record.kind != 'position' || record.deleted) return record;
  final data = {...record.data};
  if (data.containsKey('last_read_position') &&
      data['last_read_position'] == null) {
    data['last_read_position'] = '';
  }
  if (data.containsKey('reading_percentage')) {
    final progress = data['reading_percentage'];
    if (progress == null || progress is num) {
      data['reading_percentage'] = normalizeReadingProgress(progress as num?);
    }
  }
  return RowSyncRecord(record.kind, record.id, record.clock, record.revision,
      record.deleted, data);
}

bool _hasReadingPosition(RowSyncRecord record) =>
    (record.data['last_read_position'] is String &&
        (record.data['last_read_position'] as String).isNotEmpty) ||
    (record.data['reading_percentage'] is num &&
        (record.data['reading_percentage'] as num) > 0);

/// Commutative/idempotent union. Independent book attributes (position and
/// deletion state) have independent records, so unrelated edits cannot move
/// the reading cursor or undo deletion.
List<RowSyncRecord> mergeSyncRecords(
    Iterable<RowSyncRecord> local, Iterable<RowSyncRecord> remote) {
  final result = <String, RowSyncRecord>{};
  for (final raw in [...local, ...remote]) {
    final record = normalizeSyncReadingPosition(raw);
    final previous = result[record.key];
    result[record.key] = previous == null ? record : _winner(previous, record);
  }
  // A tag deleted on one device also removes links newly added by an offline
  // device. Keep the tombstone rather than leaving an unresolvable foreign key.
  for (final r in result.values.toList()) {
    if (r.kind != 'tag_link' || r.deleted) continue;
    final tag = result['tag/${r.data['letter_spacing']}'];
    if (tag?.deleted == true) {
      result[r.key] = RowSyncRecord(
          r.kind,
          r.id,
          r.clock > tag!.clock ? r.clock : tag.clock,
          tag.revision,
          true,
          r.data);
    }
  }
  final keys = result.keys.toList()..sort();
  return [for (final key in keys) result[key]!];
}

bool sameSyncRecords(Iterable<RowSyncRecord> a, Iterable<RowSyncRecord> b) {
  Map<String, String> indexed(Iterable<RowSyncRecord> records) => {
        for (final r in records) r.key: jsonEncode(r.toMap()),
      };
  final x = indexed(a);
  final y = indexed(b);
  return x.length == y.length && x.entries.every((e) => y[e.key] == e.value);
}

RowSyncRecord _winner(RowSyncRecord a, RowSyncRecord b) {
  // Legacy unread rows have no reading-operation timestamp. Their book metadata
  // may be newer than a real read on another device; do not reset that cursor.
  // Reading backwards still wins by clock when both records have a location.
  if (a.kind == 'position') {
    final aUnknown = !a.deleted && !_hasReadingPosition(a);
    final bUnknown = !b.deleted && !_hasReadingPosition(b);
    // Tombstones belong to the known-operation tier too. Treating deletion
    // separately here would create ordering cycles across three devices.
    if (aUnknown != bUnknown) return aUnknown ? b : a;
  }
  // A hard-deleted annotation/session is never revived by an offline edit.
  // Creating it again allocates a fresh identity. Book restore is represented
  // by a newer, independent 'life' operation instead.
  if (a.deleted != b.deleted &&
      const ['note', 'time', 'tag'].contains(a.kind)) {
    return a.deleted ? a : b;
  }
  var comparison = a.clock.compareTo(b.clock);
  if (comparison == 0) {
    comparison = a.deleted == b.deleted ? 0 : (a.deleted ? 1 : -1);
  }
  if (comparison == 0) comparison = a.revision.compareTo(b.revision);
  if (comparison == 0) {
    comparison = jsonEncode(a.data).compareTo(jsonEncode(b.data));
  }
  final winner = comparison >= 0 ? a : b;
  if (a.kind == 'time' &&
      a.id.startsWith('legacy:') &&
      !a.deleted &&
      !b.deleted) {
    final x = a.data['reading_time'] as int;
    final y = b.data['reading_time'] as int;
    return RowSyncRecord(winner.kind, winner.id, winner.clock, winner.revision,
        false, {...winner.data, 'reading_time': x > y ? x : y});
  }
  return winner;
}
