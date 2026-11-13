import 'dart:async';
import 'dart:io';

import 'package:modu_reader/service/book_formats.dart';
import 'package:modu_reader/service/book_import_source.dart';
import 'package:modu_reader/service/receive_file/external_book_inbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('modu-open-test-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
      'every supported format accepts local paths and file URLs, case insensitive',
      () async {
    for (final extension in allowBookExtensions) {
      final book =
          await File(p.join(root.path, '中文 book.${extension.toUpperCase()}'))
              .writeAsString(extension);
      final entries = await externalBookEntries(
          [book.path, book.uri.toString(), book.path]);
      expect(entries, hasLength(1));
      expect(await File(entries.single.id).readAsString(), extension);
    }
    for (final raw in [
      'https://site/book.pdf',
      'content://provider/book.pdf',
      'modu://read?file=book.epub',
      'file://evil/book.pdf',
      'relative.epub',
      '/tmp/image.png'
    ]) {
      expect(externalBookPath(raw), isNull, reason: raw);
    }
  });

  test('a directory named PDF is rejected rather than recursively imported',
      () async {
    final directory =
        await Directory(p.join(root.path, 'National-Post-23-october.pdf'))
            .create();
    await File(p.join(directory.path, 'hidden.epub')).writeAsString('nested');
    await expectLater(externalBookEntries([directory.path]),
        throwsA(isA<FileSystemException>()));
    expect(directory.existsSync(), isTrue);
  });

  test(
      'same-name books are isolated and importer deletion never touches originals',
      () async {
    final originals = <File>[];
    for (final name in ['first', 'second']) {
      final folder = await Directory(p.join(root.path, name)).create();
      originals
          .add(await File(p.join(folder.path, 'book.pdf')).writeAsString(name));
    }
    // Reproduce the conflicting old public-cache directory.
    await Directory(p.join(root.path, 'book.pdf')).create();
    final staged = await stageBookImportFiles(
        await externalBookEntries(originals.map((file) => file.path).toList()),
        root);
    expect(staged.map((file) => file.path).toSet(), hasLength(2));
    expect(await staged[0].readAsString(), 'first');
    expect(await staged[1].readAsString(), 'second');
    for (final file in staged) {
      await file.delete();
    }
    expect(await originals[0].readAsString(), 'first');
    expect(await originals[1].readAsString(), 'second');
  });

  test(
      'cold requests queue all documents; initial/stream duplicates import once',
      () async {
    final inbox = ExternalBookInbox();
    final first = p.join(root.path, 'one.epub');
    final second = p.join(root.path, 'two.pdf');
    final seen = <List<String>>[];
    final release = Completer<void>();
    inbox.add([first]);
    inbox.add([first, second]);
    inbox.attach((paths) async {
      seen.add(paths);
      if (seen.length == 1) await release.future;
    });
    inbox.add([first]);
    expect(seen, [
      [first]
    ]);
    release.complete();
    await Future<void>.delayed(Duration.zero);
    expect(seen, [
      [first],
      [second]
    ]);
    inbox.add([first]); // A later explicit request is allowed (MD5 skips it).
    await Future<void>.delayed(Duration.zero);
    expect(seen, [
      [first],
      [second],
      [first]
    ]);
  });

  test('detaching keeps pending books until the next navigator attaches',
      () async {
    final inbox = ExternalBookInbox();
    final seen = <List<String>>[];
    final release = Completer<void>();
    inbox.attach((paths) async {
      seen.add(paths);
      await release.future;
    });
    inbox.add([p.join(root.path, 'a.pdf')]);
    inbox.add([p.join(root.path, 'b.epub')]);
    inbox.detach();
    release.complete();
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(1));
    inbox.attach((paths) async {
      seen.add(paths);
    });
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(2));
  });
  test('a failed request does not block later books', () async {
    final inbox = ExternalBookInbox();
    final seen = <String>[];
    inbox.add([p.join(root.path, 'bad.pdf')]);
    inbox.add([p.join(root.path, 'good.epub')]);
    inbox.attach((paths) async {
      seen.add(paths.single);
      if (seen.length == 1) throw const FileSystemException('unreadable');
    });
    await Future<void>.delayed(Duration.zero);
    expect(seen.map(p.basename), ['bad.pdf', 'good.epub']);
  });
}
