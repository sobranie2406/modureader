// Local, read-only source audit. Only the app-owned imported test copy is written.
import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/service/dictionary/local_dictionary.dart';
import 'package:dict_reader/dict_reader.dart';
import 'package:sqlite3/sqlite3.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError(
        'Usage: dart run scripts/audit_local_dictionary.dart source.mdx test-root');
  }
  final reader = DictReader(args[0]);
  try {
    await reader.initDict();
    final cache = await reader.exportCache();
    final keys = cache['keyList'] as List;
    final chinese = keys
        .where((row) => RegExp(r'[\u3400-\u9fff]').hasMatch(row[1] as String))
        .toList();
    var sharedOffsets = 0;
    for (var i = 1; i < keys.length; i++) {
      if (keys[i - 1][0] == keys[i][0]) sharedOffsets++;
    }
    print(jsonEncode({
      'title': reader.header['Title'],
      'version': reader.header['GeneratedByEngineVersion'],
      'encoding': reader.header['Encoding'],
      'entries': reader.numEntries,
      'chineseHeadwords': chinese.length,
      'sharedOffsets': sharedOffsets,
      'sampleHeadwords': chinese.take(12).map((row) => row[1]).toList(),
    }));
  } finally {
    await reader.close();
  }
  final store = LocalDictionaryStore(args[1]);
  final watch = Stopwatch()..start();
  if ((await store.list()).isEmpty) {
    await store.importFiles([args[0]], 'User-supplied bilingual dictionary');
  }
  print(jsonEncode({
    'importMs': watch.elapsedMilliseconds,
    'entryCount': (await store.list()).single.count
  }));
  final files = Directory(args[1])
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.sqlite'));
  final db = sqlite3.open(files.single.path, mode: OpenMode.readOnly);
  try {
    print(jsonEncode({
      'emptyBodies': db
          .select("SELECT count(*) AS n FROM entries WHERE body='' ")
          .single['n'],
      'chineseExamples': db
          .select(
              "SELECT word, length(body) AS size FROM entries WHERE word GLOB '*[一-龥]*' LIMIT 12")
          .map((row) => Map<String, dynamic>.from(row))
          .toList()
    }));
  } finally {
    db.dispose();
  }
  for (final word in [
    '苹果',
    '中国',
    '世界',
    '革命',
    '和平',
    '学习',
    'apple',
    'china',
    'hello'
  ]) {
    watch
      ..reset()
      ..start();
    final found = await store.lookup(word);
    print(jsonEncode({
      'query': word,
      'matches': found.length,
      'lookupMs': watch.elapsedMilliseconds,
      'results': found
          .take(2)
          .map((row) => {
                'headword': row.word,
                'definitionLength': row.definition.length,
                'preview': row.definition.substring(
                    0, row.definition.length < 90 ? row.definition.length : 90)
              })
          .toList()
    }));
  }
}
