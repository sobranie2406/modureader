import 'dart:io';

import 'package:anx_reader/service/dictionary/local_dictionary.dart';
import 'package:flutter_test/flutter_test.dart';

// Opt-in local fixture: never redistribute the user's commercial dictionary.
void main() {
  final source = Platform.environment['MODU_DICTIONARY_TEST_FILE'];
  test(
      'supplied English MDX preserves native headwords without definition reverse lookup',
      () async {
    final directory = await Directory.systemTemp.createTemp('modu-real-mdx-');
    try {
      final store = LocalDictionaryStore(directory.path);
      await store.importFiles([source!], 'Chinese-English audit');
      expect((await store.list()).single.count, greaterThan(200000));
      for (final word in ['apple', 'China', 'hello']) {
        final results = await store.lookup(word);
        expect(results, isNotEmpty, reason: word);
        expect(
            results
                .any((entry) => entry.word.toLowerCase() == word.toLowerCase()),
            true);
      }
      for (final word in ['苹果', '中国', '世界', '和平']) {
        expect(await store.lookup(word), isEmpty,
            reason: 'No native headword for $word');
      }
    } finally {
      await directory.delete(recursive: true);
    }
  }, skip: source == null, timeout: const Timeout(Duration(minutes: 3)));
}
