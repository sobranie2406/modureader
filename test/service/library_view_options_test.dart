import 'package:anx_reader/service/remote_library/library_view_options.dart';
import 'package:anx_reader/service/remote_library/webdav_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

LibraryEntry entry(String name,
        {bool folder = false,
        int? size,
        DateTime? created,
        DateTime? modified}) =>
    LibraryEntry(
        Uri.https('host', '/dav/$name${folder ? '/' : ''}'), name, folder, size,
        createdAt: created, modifiedAt: modified);

void main() {
  final older = DateTime.utc(2026, 9, 1);
  final newer = DateTime.utc(2026, 9, 10);
  final entries = [
    entry('z-folder', folder: true),
    entry('A.epub', size: 100, created: newer, modified: older),
    entry('b.PDF', size: 20, created: older, modified: newer),
    entry('c.txt'),
    entry('image.png', size: 10),
  ];

  test('sorts by name in both directions without mutating source', () {
    final original = List.of(entries);
    expect(const LibraryViewOptions().apply(entries).map((e) => e.name),
        ['z-folder', 'A.epub', 'b.PDF', 'c.txt', 'image.png']);
    expect(
        const LibraryViewOptions(ascending: false)
            .apply(entries)
            .map((e) => e.name),
        ['z-folder', 'image.png', 'c.txt', 'b.PDF', 'A.epub']);
    expect(entries, original);
  });

  for (final sort in [
    LibrarySortField.createdAt,
    LibrarySortField.modifiedAt,
    LibrarySortField.size
  ]) {
    test('sorts $sort both ways, keeping folders first and missing values last',
        () {
      final files = entries.take(4).toList();
      final ascending = LibraryViewOptions(sort: sort)
          .apply(files)
          .map((e) => e.name)
          .toList();
      final descending = LibraryViewOptions(sort: sort, ascending: false)
          .apply(files)
          .map((e) => e.name)
          .toList();
      expect(ascending.first, 'z-folder');
      expect(descending.first, 'z-folder');
      expect(ascending.last, 'c.txt');
      expect(descending.last, 'c.txt');
      final expected = sort == LibrarySortField.modifiedAt
          ? ['A.epub', 'b.PDF']
          : ['b.PDF', 'A.epub'];
      expect(ascending.sublist(1, 3), expected);
      expect(descending.sublist(1, 3), expected.reversed);
    });
  }

  test('format filter combines with search and keeps folders navigable', () {
    expect(
        const LibraryViewOptions(filter: LibraryFileFilter.pdf)
            .apply(entries)
            .map((e) => e.name),
        ['z-folder', 'b.PDF']);
    expect(
        const LibraryViewOptions(filter: LibraryFileFilter.books)
            .apply(entries)
            .map((e) => e.name),
        ['z-folder', 'A.epub', 'b.PDF', 'c.txt']);
    expect(
        const LibraryViewOptions(filter: LibraryFileFilter.books)
            .apply(entries, query: ' A.EPUB ')
            .map((e) => e.name),
        ['A.epub']);
    expect(
        const LibraryViewOptions(filter: LibraryFileFilter.epub)
            .apply(entries, query: 'missing'),
        isEmpty);
  });

  test('same values have deterministic filename tie-breaking', () {
    final input = [
      entry('乙.epub', size: 10),
      entry('甲.epub', size: 10),
      entry('A.epub', size: 10)
    ];
    final options =
        const LibraryViewOptions(sort: LibrarySortField.size, ascending: false);
    expect(options.apply(input).map((e) => e.uri),
        options.apply(input.reversed).map((e) => e.uri));
  });

  test('view preferences persist locally with safe defaults for old data',
      () async {
    SharedPreferences.setMockInitialValues({});
    const options = LibraryViewOptions(
        sort: LibrarySortField.createdAt,
        ascending: false,
        filter: LibraryFileFilter.pdf);
    await LibraryViewOptionsStore.save(options);
    expect((await LibraryViewOptionsStore.load()).toJson(), options.toJson());
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {LibraryViewOptionsStore.key});
    await prefs.setString(LibraryViewOptionsStore.key, '{broken');
    expect((await LibraryViewOptionsStore.load()).sort, LibrarySortField.name);
    expect(
        LibraryViewOptions.fromJson(
                {'sort': 'future', 'ascending': 'false', 'filter': 'future'})
            .toJson(),
        const LibraryViewOptions().toJson());
  });

  test(
      'DAV timestamps parse independently; missing/invalid/denied dates stay unknown',
      () {
    final client =
        WebdavLibrary(const LibraryConnection(url: 'https://host/dav/'));
    addTearDown(client.close);
    String item(String name, String dates, {String denied = ''}) =>
        '<d:response><d:href>/dav/$name</d:href>'
        '<d:propstat><d:status>HTTP/1.1 200 OK</d:status><d:prop><d:resourcetype/>$dates</d:prop></d:propstat>'
        '$denied</d:response>';
    final xml = '<d:multistatus xmlns:d="DAV:">'
        '${item('a.epub', '<d:creationdate>2026-09-10T18:00:00+08:00</d:creationdate><d:getlastmodified>Wed, 09 Sep 2026 10:00:00 GMT</d:getlastmodified>')}'
        '${item('b.epub', '<d:creationdate>invalid</d:creationdate><d:getlastmodified>2026-09-10T10:00:00Z</d:getlastmodified>')}'
        '${item('c.epub', '', denied: '<d:propstat><d:status>HTTP/1.1 404 Not Found</d:status><d:prop><d:creationdate>2026-09-10T00:00:00Z</d:creationdate></d:prop></d:propstat>')}'
        '${item('d.epub', '<d:getlastmodified>not-a-date</d:getlastmodified>')}'
        '</d:multistatus>';
    final result = client.parseListing(xml, client.root);
    expect(result, hasLength(4));
    expect(result[0].createdAt, DateTime.utc(2026, 9, 10, 10));
    expect(result[0].modifiedAt, DateTime.utc(2026, 9, 9, 10));
    expect(result[1].createdAt, isNull);
    expect(result[1].modifiedAt, DateTime.utc(2026, 9, 10, 10));
    expect(result[2].createdAt, isNull);
    expect(result[3].modifiedAt, isNull);
  });
}
