import 'dart:io';
import 'package:anx_reader/service/book_player/reader_file_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('modu-file-access-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test('only explicitly registered opaque tokens can read a book', () async {
    final book = await File('${root.path}/book.pdf').writeAsString('fixture');
    final registry = ReaderFileAccess();
    final token = registry.register(book);
    expect(token, matches(RegExp(r'^[a-f0-9]{64}\.pdf$')));
    expect(registry.resolve(book.path), isNull);
    expect(registry.resolve(Uri.encodeComponent(book.path)), isNull);
    expect(await registry.resolve(token)!.readAsString(), 'fixture');
    expect(registry.register(book), token);
    final temporary = registry.register(book, reuse: false);
    registry.revoke(temporary);
    expect(registry.resolve(temporary), isNull);
    expect(registry.resolve(token), isNotNull);
  });
  test('directory containment rejects traversal and escaping symlinks',
      () async {
    final inside = await Directory('${root.path}/inside').create();
    await File('${inside.path}/safe').writeAsString('safe');
    final outside = await File('${root.path}/outside').writeAsString('private');
    await Link('${inside.path}/link').create(outside.path);
    expect(ReaderFileAccess.within(inside, 'safe'), isNotNull);
    expect(ReaderFileAccess.within(inside, '../outside'), isNull);
    expect(ReaderFileAccess.within(inside, outside.path), isNull);
    expect(ReaderFileAccess.within(inside, 'link'), isNull);
  });
  test('replacing a registered file with an escaping symlink invalidates it',
      () async {
    final book = await File('${root.path}/book').writeAsString('book');
    final private = await File('${root.path}/private').writeAsString('private');
    final registry = ReaderFileAccess();
    final token = registry.register(book);
    await book.delete();
    await Link(book.path).create(private.path);
    expect(registry.resolve(token), isNull);
  });
}
