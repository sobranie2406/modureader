import 'dart:io';
import 'package:modu_reader/service/dictionary/local_dictionary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

// Local opt-in fixture only; never copy a user's dictionary into the repository.
void main() {
  final source = Platform.environment['MODU_DICTIONARY_TEST_DIRECTORY'];
  test('real dictionary imports entries and companion image resources',
      () async {
    final root = await Directory.systemTemp.createTemp('modu-real-bundle-');
    try {
      final paths = Directory(source!)
          .listSync()
          .whereType<File>()
          .map((file) => file.path)
          .toList();
      final store = LocalDictionaryStore(root.path);
      await store.importFiles(paths, 'Local fixture');
      final dictionary = (await store.list()).single;
      expect(dictionary.count, greaterThan(0));
      final db = sqlite3.open('${root.path}/${dictionary.id}.sqlite');
      try {
        final rows =
            db.select('SELECT path, length(data) AS size FROM resources');
        expect(rows.where((row) => (row['path'] as String).endsWith('.css')),
            isNotEmpty);
        final picture = rows.firstWhere((row) =>
            RegExp(r'\.(png|jpg|jpeg|gif)$', caseSensitive: false)
                .hasMatch(row['path'] as String));
        expect(
            (await store.resource(dictionary.id, picture['path'] as String))!
                .length,
            picture['size']);
        final word = db.select(
            'SELECT word FROM entries WHERE body != ? LIMIT 1',
            ['']).single['word'] as String;
        expect(await store.lookup(word), isNotEmpty);
      } finally {
        db.dispose();
      }
    } finally {
      await root.delete(recursive: true);
    }
  }, skip: source == null, timeout: const Timeout(Duration(minutes: 10)));
}
