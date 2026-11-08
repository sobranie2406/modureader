import 'dart:convert';
import 'dart:io';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/book_local_sources.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'row_sync_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
      'linked and copied sources survive repeated bidirectional metadata merges',
      () async {
    const hash = '1234567890abcdef1234567890abcdef';
    final root = await Directory.systemTemp.createTemp('modu-source-merge-');
    final aDir = await Directory('${root.path}/a').create();
    final bDir = await Directory('${root.path}/b').create();
    final original =
        await File('${root.path}/original.epub').writeAsString('original');
    final copy = File('${bDir.path}/file/copy.epub');
    await copy.parent.create();
    await original.copy(copy.path);
    final a = await fixture();
    final b = await fixture(bookId: 77);
    final oldPath = documentPath;
    try {
      await a.update(
          'tb_books', {'file_md5': hash, 'file_path': 'file/linked.epub'});
      await b.update(
          'tb_books', {'file_md5': hash, 'file_path': 'file/copy.epub'});
      await a
          .insert('tb_notes', {'book_id': 1, 'cfi': 'note', 'content': 'kept'});
      await BookSources.initialize(aDir);
      await BookSources.store!.save(hash, 'file/linked.epub',
          kind: 'linked', locator: original.path);
      for (var round = 0; round < 3; round++) {
        documentPath = bDir.path;
        await BookSources.initialize(bDir);
        await RowSyncStore(b).merge(await RowSyncStore(a).snapshot());
        final localB = Book.fromDb(
            (await b.query('tb_books', where: 'is_deleted=0')).single);
        expect(localB.fileFullPath, copy.path);
        expect(localB.isLinked, isFalse);
        documentPath = aDir.path;
        await BookSources.initialize(aDir);
        await RowSyncStore(a).merge(await RowSyncStore(b).snapshot());
        final localA = Book.fromDb(
            (await a.query('tb_books', where: 'is_deleted=0')).single);
        expect(localA.fileFullPath, original.path);
        expect(localA.isLinked, isTrue);
        final payload = jsonEncode(
            (await RowSyncStore(a).snapshot()).map((r) => r.toMap()).toList());
        expect(payload, isNot(contains(root.path)));
      }
      expect((await b.query('tb_notes')).single['content'], 'kept');
      expect(await original.readAsString(), 'original');
      expect(await copy.readAsString(), 'original');
    } finally {
      documentPath = oldPath;
      await a.close();
      await b.close();
      await root.delete(recursive: true);
    }
  });
}
