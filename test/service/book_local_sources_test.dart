import 'dart:io';
import 'package:anx_reader/service/book_local_sources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late BookLocalSources sources;
  const md5 = '1234567890abcdef1234567890abcdef';
  setUp(() async {
    root = await Directory.systemTemp.createTemp('modu-sources-');
    sources = BookLocalSources(File('${root.path}/book_sources.json'));
    await sources.load();
  });
  tearDown(() => root.delete(recursive: true));
  test('same content retains local source after remote asset path changes',
      () async {
    await sources.save(md5, 'file/a.epub',
        kind: 'linked', locator: '/original/book.epub');
    expect(sources.read(md5.toUpperCase(), 'file/remote.epub')?['locator'],
        '/original/book.epub');
    final reloaded = BookLocalSources(sources.file);
    await reloaded.load();
    expect(reloaded.read(md5, 'file/another.epub')?['kind'], 'linked');
    expect(reloaded.read('abcdef1234567890abcdef1234567890', 'file/a.epub'),
        isNull);
  });
  test('serial writes preserve different books and remove only target binding',
      () async {
    await Future.wait([
      sources.save(md5, 'file/a.pdf',
          kind: 'internal', locator: 'file/local.pdf'),
      sources.save(null, 'file/legacy.pdf',
          kind: 'linked', locator: 'content://books/1'),
    ]);
    await sources.remove(md5, 'file/remote.pdf');
    expect(sources.read(md5, 'file/a.pdf'), isNull);
    expect(
        sources.read(null, 'file/legacy.pdf')?['locator'], 'content://books/1');
  });
  test('invalid owned paths cannot point cleanup outside internal storage', () {
    for (final path in [
      '../original.epub',
      'file/../../original.epub',
      '/original.epub',
      'file/..'
    ]) {
      expect(
          () =>
              sources.save(md5, 'file/a.epub', kind: 'internal', locator: path),
          throwsFormatException);
    }
  });
  test('corrupt state is reported without overwriting it', () async {
    await sources.file.writeAsString('{broken');
    await expectLater(sources.load(), throwsFormatException);
    expect(await sources.file.readAsString(), '{broken');
  });
}
