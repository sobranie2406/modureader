// Synthetic host-only comparison. This does not reproduce an Android OS kill.
// Run each mode in a fresh Dart process with the repository package config.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:anx_reader/service/knowledge/knowledge_engine.dart';

Future<void> main(List<String> args) async {
  final legacy = args.single == 'legacy';
  final directory = await Directory.systemTemp.createTemp('modu-memory-probe-');
  try {
    void sample(String stage) => stdout.writeln(jsonEncode({
          'mode': legacy ? 'legacy' : 'bounded',
          'stage': stage,
          'rssMiB': ProcessInfo.currentRss / 1048576,
          'peakMiB': ProcessInfo.maxRss / 1048576,
        }));
    sample('start');
    const count = 5000, dimensions = 512;
    final chunks = List.generate(
        count,
        (i) => KnowledgeChunk(
              id: 'fixture:$i',
              bookId: 'fixture',
              chapterId: 'chapter',
              text: '合成测试文本$i ${'阅读测试' * 195}',
            ));
    final vectors = chunks.map((c) {
      final values = List<double>.generate(dimensions, (i) => (i + 1) / 1024);
      return VectorEntry(
          chunk: c, vector: legacy ? values : Float64List.fromList(values));
    }).toList();
    final snapshot = KnowledgeIndexSnapshot(
        bookId: 'fixture',
        contentHash: 'fixture',
        chunks: chunks,
        vectors: vectors);
    final file = File('${directory.path}/index.json');
    final store = FileKnowledgeIndexStore(file);
    sample('vectors-retained');
    if (legacy) {
      await file.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
    } else {
      await store.save(snapshot);
    }
    sample('saved');
    if (legacy) {
      if (await store.load('fixture') == null)
        throw StateError('Restore failed');
    } else {
      if (await store.summary('fixture') == null)
        throw StateError('Summary failed');
    }
    sample('badge-refreshed');
    stdout.writeln(
        'rows=${snapshot.vectors.length} dimensions=$dimensions bytes=${await file.length()}');
  } finally {
    await directory.delete(recursive: true);
  }
}
