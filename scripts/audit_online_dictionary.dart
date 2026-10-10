// Opt-in network smoke test: public sample words only; no book or account data.
import 'dart:convert';
import 'dart:io';
import 'package:anx_reader/service/dictionary/online_dictionary.dart';

Future<void> main() async {
  final service = OnlineDictionaryService();
  try {
    for (final source in OnlineDictionary.values) {
      final word = source == OnlineDictionary.wiktionaryZh ? '苹果' : 'hello';
      try {
        final result = await service.lookup(source, word);
        if (result.isEmpty ||
            result.first.definition.isEmpty ||
            result.first.sourceUri == null ||
            result.first.licenseUri == null) {
          throw StateError('Missing definition or attribution');
        }
        print(jsonEncode({
          'source': source.name,
          'entries': result.length,
          'characters': result.first.definition.length,
          'license': result.first.license,
          'ok': true
        }));
      } catch (e) {
        print(jsonEncode({
          'source': source.name,
          'error': e.runtimeType.toString(),
          'ok': false
        }));
        exitCode = 1;
      }
    }
  } finally {
    service.close();
  }
}
