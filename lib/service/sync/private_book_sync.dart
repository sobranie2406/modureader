import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/service/sync/row_sync_record.dart';

/// A transport view, never a rewrite of local or previously published records.
class PrivateBookSyncFilter {
  PrivateBookSyncFilter(Iterable<RowSyncRecord> records,
      {PrivateLibrary? library}) {
    library ??= PrivateLibrary.instance;
    final all = records.toList();
    if (!library.hasSyncExclusions) return;
    _enabled = true;
    _corrupt = library.corrupt;
    _books.addAll(library.syncExcludedBookIds);
    final localIds = library.syncExcludedLocalBookIds;
    for (final r in all.where((r) => r.kind == 'book')) {
      if (localIds.contains(r.localId) ||
          !library.canSyncSource(
              md5: r.data['file_md5'] as String?,
              filePath: r.data['file_path'] as String?) ||
          (r.id.startsWith('md5:') &&
              !library.canSyncSource(md5: r.id.substring(4))) ||
          (r.id.startsWith('path:') &&
              !library.canSyncSource(filePath: r.id.substring(5)))) {
        _books.add(r.id);
      }
    }
    // Historical aliases/replacements and duplicate identities belong to the
    // same protected source, even when their current payload changed.
    var changed = true;
    while (changed) {
      changed = false;
      final hashes = <String>{}, paths = <String>{};
      for (final r
          in all.where((r) => r.kind == 'book' && _books.contains(r.id))) {
        final hash = r.data['file_md5'];
        final path = r.data['file_path'];
        if (hash is String && hash.isNotEmpty) hashes.add(hash.toLowerCase());
        if (path is String && path.isNotEmpty) paths.add(path);
      }
      for (final r in all) {
        final target = bookSyncAliasTarget(r);
        if (target != null &&
            (_books.contains(r.id) || _books.contains(target))) {
          changed = _books.add(r.id) || changed;
          changed = _books.add(target) || changed;
        }
        if (r.kind == 'book' &&
            (hashes.contains(
                    (r.data['file_md5'] as String? ?? '').toLowerCase()) ||
                paths.contains(r.data['file_path']))) {
          changed = _books.add(r.id) || changed;
        }
      }
    }
    final privateGroups = <String>{}, publicGroups = <String>{};
    final privateTags = <String>{}, publicTags = <String>{};
    for (final r in all) {
      if (r.kind == 'book' && r.data['group_id'] is String) {
        (_books.contains(r.id) ? privateGroups : publicGroups)
            .add(r.data['group_id'] as String);
      }
      if (r.kind == 'tag_link' && r.data['letter_spacing'] is String) {
        (_books.contains(r.data['line_height']) ? privateTags : publicTags)
            .add(r.data['letter_spacing'] as String);
      }
    }
    void ancestors(Set<String> ids) {
      var added = true;
      while (added) {
        added = false;
        for (final r in all.where((r) => r.kind == 'group')) {
          if (ids.contains(r.id) && r.data['parent_id'] is String) {
            added = ids.add(r.data['parent_id'] as String) || added;
          }
        }
      }
    }

    ancestors(privateGroups);
    ancestors(publicGroups);
    _groups.addAll(privateGroups.difference(publicGroups)..remove('root'));
    _tags.addAll(privateTags.difference(publicTags));
    for (final r in all) {
      if (_blocked(r)) _keys.add(r.key);
    }
  }

  bool _enabled = false, _corrupt = false;
  final _books = <String>{}, _groups = <String>{}, _tags = <String>{};
  final _keys = <String>{};

  bool _blocked(RowSyncRecord r) {
    if (!_enabled) return false;
    if (_corrupt) return r.kind != 'secret';
    switch (r.kind) {
      case 'book':
      case 'position':
      case 'life':
      case 'review':
        return _books.contains(r.id);
      case 'note':
      case 'time':
      case 'round':
        // Older delete triggers did not retain ownership before first sync.
        // Defer unowned tombstones instead of guessing a private source.
        return _books.contains(r.data['book_id']) ||
            (r.deleted && r.data['book_id'] == null && _books.isNotEmpty);
      case 'tag_link':
        return _books.contains(r.data['line_height']) ||
            (r.deleted && r.data['line_height'] == null && _books.isNotEmpty);
      case 'group':
        return _groups.contains(r.id);
      case 'tag':
        return _tags.contains(r.id);
    }
    return false;
  }

  bool allows(RowSyncRecord r) => !_keys.contains(r.key) && !_blocked(r);

  List<RowSyncRecord> allowedRecords(Iterable<RowSyncRecord> records) =>
      records.where(allows).toList();

  List<RowSyncRecord> protectedRecords(Iterable<RowSyncRecord> records) =>
      records.where((r) => !allows(r)).toList();
}
