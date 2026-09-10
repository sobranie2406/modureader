import 'dart:convert';

import 'package:anx_reader/service/remote_library/webdav_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LibrarySortField { name, createdAt, modifiedAt, size }

enum LibraryFileFilter { all, books, epub, pdf, txt, mobi, azw3, fb2 }

class LibraryViewOptions {
  const LibraryViewOptions({
    this.sort = LibrarySortField.name,
    this.ascending = true,
    this.filter = LibraryFileFilter.all,
  });
  final LibrarySortField sort;
  final bool ascending;
  final LibraryFileFilter filter;

  LibraryViewOptions copyWith(
          {LibrarySortField? sort,
          bool? ascending,
          LibraryFileFilter? filter}) =>
      LibraryViewOptions(
          sort: sort ?? this.sort,
          ascending: ascending ?? this.ascending,
          filter: filter ?? this.filter);

  List<LibraryEntry> apply(Iterable<LibraryEntry> entries,
      {String query = ''}) {
    final search = query.trim().toLowerCase();
    final result = entries.where((entry) {
      if (!entry.name.toLowerCase().contains(search)) return false;
      // Keep folders navigable even when only EPUB/PDF/etc. is selected.
      if (entry.isDirectory || filter == LibraryFileFilter.all) return true;
      if (filter == LibraryFileFilter.books) return entry.isBook;
      return entry.name.split('.').last.toLowerCase() == filter.name;
    }).toList();
    result.sort((a, b) {
      // Folder priority and unknown-last are independent of sort direction.
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      final comparison = switch (sort) {
        LibrarySortField.name =>
          _direction(a.name.toLowerCase().compareTo(b.name.toLowerCase())),
        LibrarySortField.createdAt =>
          _optional(a.createdAt, b.createdAt, (x, y) => x.compareTo(y)),
        LibrarySortField.modifiedAt =>
          _optional(a.modifiedAt, b.modifiedAt, (x, y) => x.compareTo(y)),
        LibrarySortField.size =>
          _optional(a.size, b.size, (x, y) => x.compareTo(y)),
      };
      if (comparison != 0) return comparison;
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0
          ? byName
          : a.uri.toString().compareTo(b.uri.toString());
    });
    return result;
  }

  int _direction(int value) => ascending ? value : -value;
  int _optional<T>(T? a, T? b, int Function(T, T) compare) {
    if (a == null) return b == null ? 0 : 1;
    if (b == null) return -1;
    return _direction(compare(a, b));
  }

  Map<String, Object> toJson() =>
      {'sort': sort.name, 'ascending': ascending, 'filter': filter.name};
  factory LibraryViewOptions.fromJson(Map<String, dynamic> json) =>
      LibraryViewOptions(
        sort: LibrarySortField.values
                .where((e) => e.name == json['sort'])
                .firstOrNull ??
            LibrarySortField.name,
        ascending: json['ascending'] is bool ? json['ascending'] as bool : true,
        filter: LibraryFileFilter.values
                .where((e) => e.name == json['filter'])
                .firstOrNull ??
            LibraryFileFilter.all,
      );
}

/// Device-only presentation preferences; never part of the WebDAV data.
class LibraryViewOptionsStore {
  static const key = 'remoteLibraryViewOptions';
  static Future<LibraryViewOptions> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw != null) {
      try {
        final value = jsonDecode(raw);
        if (value is Map<String, dynamic>) {
          return LibraryViewOptions.fromJson(value);
        }
      } on FormatException {
        // Corrupt/old view preferences do not block connecting to a library.
      }
    }
    return const LibraryViewOptions();
  }

  static Future<void> save(LibraryViewOptions options) async {
    final saved = await (await SharedPreferences.getInstance())
        .setString(key, jsonEncode(options.toJson()));
    if (!saved) throw StateError('Cannot save library view preferences');
  }
}
