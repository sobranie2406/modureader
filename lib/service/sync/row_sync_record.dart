import 'dart:convert';
import 'package:anx_reader/models/narration_position.dart';
import 'package:anx_reader/utils/reading_progress.dart';

part 'book_sync_identity.dart';

// An intentional new-round reset is an operation, not an unread legacy row.
const syncPositionResetPrefix = 'modu-position-reset-v1:';

/// Portable identity and operation clock; never a device-local integer row ID.
class RowSyncRecord {
  const RowSyncRecord(
      this.kind, this.id, this.clock, this.revision, this.deleted, this.data,
      {this.narration});

  final String kind;
  final String id;
  final int clock;
  final String revision;
  final bool deleted;
  final Map<String, Object?> data;
  final NarrationPosition? narration;
  String get key => '$kind/$id';

  Map<String, Object?> toMap() => {
        'kind': kind,
        'sync_id': id,
        'clock': clock,
        'revision': revision,
        'deleted': deleted ? 1 : 0,
        'payload': jsonEncode(data),
        'narration': narration?.encode(),
      };

  factory RowSyncRecord.fromMap(Map<String, Object?> row) {
    return normalizeRoundFields(normalizeSyncReadingPosition(RowSyncRecord(
      row['kind'] as String,
      row['sync_id'] as String,
      row['clock'] as int,
      row['revision'] as String,
      row['deleted'] == 1,
      Map<String, Object?>.from(jsonDecode(row['payload'] as String) as Map),
      narration: NarrationPosition.decode(row['narration']),
    )));
  }
}

/// Defaults added by sync schema v9, without changing local `modu_sync_records`
/// rows owned by older clients.
///
/// - `time.round` defaults to 1: every session written before reading rounds
///   existed belongs to the first round.
/// - `round` records always carry the full field set so strict validation and
///   older payloads cannot drop nullable fields.
RowSyncRecord normalizeRoundFields(RowSyncRecord record) {
  if (record.deleted) return record;
  if (record.kind == 'time') {
    if (record.data.containsKey('round')) return record;
    return RowSyncRecord(record.kind, record.id, record.clock, record.revision,
        false, {...record.data, 'round': 1},
        narration: record.narration);
  }
  if (record.kind == 'round') {
    final data = {...record.data};
    data['round_number'] ??= 1;
    data['status'] ??= 'reading';
    data['start_percentage'] ??= 0;
    data['end_percentage'] ??= 0;
    if (!data.containsKey('start_time')) data['start_time'] = null;
    if (!data.containsKey('end_time')) data['end_time'] = null;
    if (!data.containsKey('end_position')) data['end_position'] = null;
    return RowSyncRecord(record.kind, record.id, record.clock, record.revision,
        record.deleted, data,
        narration: record.narration);
  }
  return record;
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
      record.deleted, data,
      narration: record.narration);
}

bool _hasReadingPosition(RowSyncRecord record) =>
    record.revision.startsWith(syncPositionResetPrefix) ||
    (record.data['last_read_position'] is String &&
        (record.data['last_read_position'] as String).isNotEmpty) ||
    (record.data['reading_percentage'] is num &&
        (record.data['reading_percentage'] as num) > 0);

/// Commutative/idempotent union. Independent book attributes (position and
/// deletion state) have independent records, so unrelated edits cannot move
/// the reading cursor or undo deletion.
List<RowSyncRecord> mergeSyncRecords(
    Iterable<RowSyncRecord> local, Iterable<RowSyncRecord> remote,
    {bool reconcileBookIdentities = true}) {
  final result = <String, RowSyncRecord>{};
  final input = [...local, ...remote];
  for (final raw
      in reconcileBookIdentities ? _normalizeBookIdentities(input) : input) {
    final record = normalizeRoundFields(normalizeSyncReadingPosition(raw));
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

/// How records that exist on BOTH devices with different content are resolved.
///
/// `newest` keeps the operation clock ordering used by every other merge path.
/// The two explicit choices only apply to [divergentSyncKeys]; records that
/// exist on one side alone are always merged normally, so a preference can
/// never delete a book, note or session that only one device knows about.
enum SyncConflictResolution { newest, preferLocal, preferRemote }

/// Keys that both sides published with different CONTENT.
///
/// Clock and revision are deliberately ignored: an unchanged record whose clock
/// merely advanced (a re-stamp or a legacy migration) is not a conflict. This
/// is the set a user is asked about BEFORE a merge. Encrypted AI/service
/// settings are excluded (opaque envelopes differ on every re-encryption), as
/// is the fixed root group row.
Set<String> divergentSyncKeys(
    Iterable<RowSyncRecord> local, Iterable<RowSyncRecord> remote) {
  // Sort payload keys before encoding: identical content written by clients of
  // different ages can carry a different JSON member order.
  String content(RowSyncRecord record) {
    final entries = record.data.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return jsonEncode([
      record.deleted,
      {for (final entry in entries) entry.key: entry.value},
      record.narration?.encode(),
    ]);
  }

  final index = {for (final record in local) record.key: record};
  final keys = <String>{};
  for (final record in remote) {
    final existing = index[record.key];
    if (existing == null ||
        existing.kind == 'secret' ||
        existing.key == 'group/root') {
      continue;
    }
    if (content(existing) != content(record)) keys.add(record.key);
  }
  return keys;
}

/// Replaces the winning side for every divergent key. Callers pass the union
/// produced by [mergeSyncRecords] so unrelated records are untouched.
List<RowSyncRecord> resolveSyncConflicts({
  required Iterable<RowSyncRecord> local,
  required Iterable<RowSyncRecord> remote,
  required Iterable<RowSyncRecord> merged,
  required SyncConflictResolution resolution,
}) {
  final records = merged.toList();
  if (resolution == SyncConflictResolution.newest) return records;
  final keys = divergentSyncKeys(local, remote);
  if (keys.isEmpty) return records;
  final preferred = {
    for (final record in resolution == SyncConflictResolution.preferLocal
        ? local
        : remote)
      record.key: record
  };
  return [
    for (final record in records)
      keys.contains(record.key) && preferred.containsKey(record.key)
          ? preferred[record.key]!
          : record
  ];
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
  // Old clients relay the same revision without this optional extension.
  if (comparison == 0) {
    comparison =
        (a.narration?.encode() ?? '').compareTo(b.narration?.encode() ?? '');
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
