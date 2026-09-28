part of 'row_sync_record.dart';

// A redirect is an ordinary deleted book record on the wire. Older readers
// understand it as a tombstone; current readers also retain its identity edge.
// No fields/kinds are added to the database8 transport or encrypted settings.
const _bookAliasPrefix = 'modu-book-alias-v1:';

String? bookSyncAliasTarget(RowSyncRecord record) {
  if (!const ['book', 'position', 'life'].contains(record.kind) ||
      !record.deleted ||
      !record.revision.startsWith(_bookAliasPrefix)) {
    return null;
  }
  try {
    final target = utf8.decode(
        base64Url.decode(record.revision.substring(_bookAliasPrefix.length)));
    // Edges always point downwards, so corrupt input cannot create cycles.
    if (target.isNotEmpty &&
        target.length <= 4096 &&
        target.compareTo(record.id) < 0) {
      return target;
    }
  } catch (_) {}
  throw const FormatException('书籍同步关联标识无效');
}

List<RowSyncRecord> _normalizeBookIdentities(List<RowSyncRecord> records) {
  final parents = <String, String>{};
  String root(String id) {
    var current = id;
    final path = <String>[];
    while (parents[current] != null && parents[current] != current) {
      path.add(current);
      current = parents[current]!;
    }
    for (final item in path) {
      parents[item] = current;
    }
    return current;
  }

  void join(String a, String b) {
    a = root(a);
    b = root(b);
    if (a == b) return;
    if (a.compareTo(b) < 0) {
      parents[b] = a;
    } else {
      parents[a] = b;
    }
  }

  final books = <String, RowSyncRecord>{};
  final life = <String, RowSyncRecord>{};
  final aliases = <RowSyncRecord>[];
  for (final record in records) {
    final target = bookSyncAliasTarget(record);
    if (target != null) {
      aliases.add(record);
      join(record.id, target);
    } else if (record.kind == 'book' || record.kind == 'life') {
      final map = record.kind == 'book' ? books : life;
      final previous = map[record.id];
      map[record.id] = previous == null ? record : _winner(previous, record);
    }
  }
  // Resolve already-known aliases before comparing current book contents.
  // Never compare historical file hashes against a newer replacement.
  Map<String, RowSyncRecord> resolve(Map<String, RowSyncRecord> source) {
    final result = <String, RowSyncRecord>{};
    for (final record in source.values) {
      final id = root(record.id);
      final previous = result[id];
      result[id] = previous == null ? record : _winner(previous, record);
    }
    return result;
  }

  final currentBooks = resolve(books);
  final currentLife = resolve(life);
  final digests = <String, List<String>>{};
  final paths = <String, List<String>>{};
  String digest(RowSyncRecord r) =>
      (r.data['file_md5'] as String? ?? '').trim().toLowerCase();
  for (final entry in currentBooks.entries) {
    final record = entry.value;
    final alive = currentLife[entry.key];
    // Do not turn a deliberate delete/reimport into deletion of the live copy.
    if (record.deleted ||
        alive?.deleted == true ||
        alive?.data['is_deleted'] == 1) {
      continue;
    }
    final hash = digest(record);
    if (hash.isNotEmpty) digests.putIfAbsent(hash, () => []).add(entry.key);
    final path = record.data['file_path'];
    if (path is String && path.startsWith('file/')) {
      paths.putIfAbsent(path, () => []).add(entry.key);
    }
  }
  for (final ids in digests.values) {
    for (final id in ids.skip(1)) {
      join(ids.first, id);
    }
  }
  for (final ids in paths.values) {
    final known = ids
        .map((id) => digest(currentBooks[id]!))
        .where((hash) => hash.isNotEmpty)
        .toSet();
    // Same title is NEVER evidence. Same path is evidence only if no known
    // content hashes conflict (including the missing-MD5 migration case).
    if (known.length <= 1) {
      for (final id in ids.skip(1)) {
        join(ids.first, id);
      }
    }
  }
  if (parents.isEmpty) return records;

  final output = <RowSyncRecord>[];
  final retiredBooks = {...books};
  for (final alias in aliases.where((r) => r.kind == 'book')) {
    final previous = retiredBooks[alias.id];
    retiredBooks[alias.id] =
        previous == null ? alias : _winner(previous, alias);
  }
  final clocks = <String, int>{};
  final members = <String>{
    ...books.keys,
    ...parents.keys,
    ...aliases.map((r) => r.id)
  };
  for (final record in records
      .where((r) => const ['book', 'position', 'life'].contains(r.kind))) {
    final id = root(record.id);
    final previous = clocks[id] ?? 0;
    if (record.clock > previous) clocks[id] = record.clock;
  }
  for (final record in records) {
    if (bookSyncAliasTarget(record) != null) continue;
    var id = record.id;
    var data = record.data;
    if (const ['book', 'position', 'life'].contains(record.kind)) {
      id = root(id);
    } else {
      final field = switch (record.kind) {
        'note' || 'time' => 'book_id',
        'tag_link' => 'line_height',
        _ => null,
      };
      if (field != null && data[field] is String) {
        final old = data[field] as String;
        final canonical = root(old);
        if (canonical != old) {
          data = {...data, field: canonical};
          if (record.kind == 'tag_link') {
            id = '$canonical:${data['letter_spacing']}';
          }
        }
      }
    }
    output.add(RowSyncRecord(
        record.kind, id, record.clock, record.revision, record.deleted, data));
  }
  for (final id in members) {
    final canonical = root(id);
    if (id == canonical) continue;
    // Companion tombstones stop older clients' independent 'life' records
    // from making a retired alias visible again. New clients recognize these
    // as redirects, never as a deletion of the canonical book.
    for (final kind in ['book', 'position', 'life']) {
      output.add(RowSyncRecord(
          kind,
          id,
          clocks[canonical] ?? 0,
          '$_bookAliasPrefix${base64Url.encode(utf8.encode(canonical))}',
          true,
          kind == 'book' ? retiredBooks[id]?.data ?? const {} : const {}));
    }
  }
  return output;
}
