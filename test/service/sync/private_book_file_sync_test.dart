import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/custom_css_profile.dart';
import 'package:modu_reader/models/remote_file.dart';
import 'package:modu_reader/providers/sync_status.dart';
import 'package:modu_reader/service/ocr/document_reflow_store.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/service/sync/book_cloud_deletions.dart';
import 'package:modu_reader/service/sync/book_file_sync.dart';
import 'package:modu_reader/service/sync/converted_book_checksum.dart';
import 'package:modu_reader/service/sync/document_reflow_sync.dart';
import 'package:modu_reader/service/sync/knowledge_index_sync.dart';
import 'package:modu_reader/service/sync/private_book_sync_client.dart';
import 'package:modu_reader/service/sync/replaced_book_files.dart';
import 'package:modu_reader/service/sync/row_sync_store.dart';
import 'package:modu_reader/service/sync/sync_paths.dart';
import 'package:modu_reader/service/sync/weread_metadata_sync.dart';
import 'package:modu_reader/service/weread/weread_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'document_reflow_sync_test.dart' show OcrClient;
import 'row_sync_test.dart' show fixture, bookRow;

class _Client extends OcrClient {
  final operations = <String>[];
  Future<void> Function(String)? beforeProps;
  @override
  Future<RemoteFile?> readProps(String path) async {
    operations.add('props:$path');
    await beforeProps?.call(path);
    return super.readProps(path);
  }

  @override
  Future<void> mkdirAll(String path) {
    operations.add('mkdir:$path');
    return super.mkdirAll(path);
  }

  @override
  Future<void> remove(String path) {
    operations.add('remove:$path');
    return super.remove(path);
  }
}

class _WaitingUpload extends _Client {
  final started = Completer<void>();
  CancelToken? token;
  @override
  Future<void> uploadFile(String localPath, String remotePath,
      {bool replace = true,
      void Function(int, int)? onProgress,
      CancelToken? cancelToken}) async {
    token = cancelToken;
    started.complete();
    throw await cancelToken!.whenCancel;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final privacy = PrivateLibrary.instance;
  final book = Book.mock().copyWith(
      id: 2,
      md5: 'a' * 32,
      filePath: 'file/private.epub',
      coverPath: 'cover/private.jpg');
  final publicBook = Book.mock().copyWith(
      id: 3,
      md5: 'b' * 32,
      filePath: 'file/public.epub',
      coverPath: 'cover/public.jpg');
  late Directory temporary;
  late _Client client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    privacy.setPluginActive(true);
    await privacy.unlock();
    temporary = await Directory.systemTemp.createTemp('private-file-sync-');
    client = _Client();
  });
  tearDown(() async {
    privacy.setPluginActive(false);
    await temporary.delete(recursive: true);
  });

  Future<void> mark() => privacy.setBooksPrivate([book], true);

  test(
      'book assets exclude private owners independently of lock and plugin state',
      () async {
    await mark();
    await privacy.setEnabled(false);
    privacy.setPluginActive(false);
    expect(canSyncBookAsset([book, publicBook], book.filePath), false);
    expect(canSyncBookAsset([book, publicBook], book.coverPath), false);
    expect(canSyncBookAsset([book, publicBook], publicBook.filePath), true);
    expect(
        canSyncBookAsset([book, publicBook], 'cover/unattributed.jpg'), false);
    expect(
        canSyncBookAsset([book, publicBook.copyWith(coverPath: book.coverPath)],
            book.coverPath),
        false);
    expect(syncingBookIds([book, publicBook], 'private.epub'), isEmpty);
    expect(syncingBookIds([book, publicBook], 'public.epub'), [publicBook.id]);
  });

  test('mixed ordinary and private files upload only the ordinary book',
      () async {
    await mark();
    for (final path in [book.filePath, publicBook.filePath]) {
      final file = File('${temporary.path}/$path');
      await file.parent.create(recursive: true);
      await file.writeAsBytes([1, 2, 3]);
    }
    await syncBookFiles(
        client: client,
        currentPaths: [book.filePath, publicBook.filePath],
        listedPaths: {},
        localFile: (path) => File('${temporary.path}/$path'),
        canSyncPath: (path) => canSyncBookAsset([book, publicBook], path),
        upload: (local, remote) => client.uploadFile(local, remote));
    expect(client.uploaded, [SyncPaths.data(publicBook.filePath)]);
    expect(
        client.operations.any((path) => path.contains('private.epub')), false);
  });

  test('a private scoped transfer cannot read, upload, download or delete',
      () async {
    await mark();
    final guarded =
        PrivateBookSyncClient(client, () => privacy.canSyncBook(book));
    for (final operation in <Future<void> Function()>[
      () async {
        await guarded.readProps('private');
      },
      () => guarded.uploadFile('local', 'private'),
      () => guarded.downloadFile('private', 'local'),
      () => guarded.remove('private'),
    ]) {
      await expectLater(operation(), throwsA(isA<PrivateBookSyncBlocked>()));
    }
    expect(client.operations, isEmpty);
    expect(client.uploaded, isEmpty);
    expect(client.downloads, 0);
  });

  test('marking a book cancels its in-flight upload token', () async {
    final waiting = _WaitingUpload();
    final guarded =
        PrivateBookSyncClient(waiting, () => privacy.canSyncBook(book));
    final outgoing = guarded.uploadFile('local', 'remote');
    final rejected = expectLater(
        outgoing,
        throwsA(isA<DioException>()
            .having((error) => error.type, 'type', DioExceptionType.cancel)));
    await waiting.started.future;
    await mark();
    expect(waiting.token!.isCancelled, true);
    await rejected;
  });

  test(
      'private OCR, WeRead and legacy index transfer return before any request',
      () async {
    await mark();
    final pending = File('${temporary.path}/pending-keep');
    await pending.writeAsString('local private material');
    await DocumentReflowSync(
            client: client,
            cache: Directory('${temporary.path}/ocr-cache'),
            durableDirectory: temporary,
            store: (_) =>
                throw StateError('Private OCR store must not be opened'))
        .sync([book]);
    await WereadMetadataSync(
            client: client,
            cache: Directory('${temporary.path}/weread-cache'),
            durableDirectory: temporary,
            store: (_) =>
                throw StateError('Private WeRead store must not be opened'))
        .sync([book]);
    await KnowledgeIndexSync(
            client: client,
            cache: temporary,
            sourceFile: (_) =>
                throw StateError('Private source must not be read'))
        .sync([book], enabled: () => true);
    expect(client.operations, isEmpty);
    expect(client.uploaded, isEmpty);
    expect(client.downloads, 0);
    expect(await pending.readAsString(), 'local private material');
  });

  for (final kind in ['ocr', 'weread']) {
    test(
        '$kind downloaded just before a private mark never merges into the local store',
        () async {
      final first = await Directory('${temporary.path}/first').create();
      final second = await Directory('${temporary.path}/second').create();
      DocumentReflowStore ocr(Directory root) =>
          DocumentReflowStore(customCssBookKey(book), directory: root);
      WereadStore weread(Directory root) => WereadStore(customCssBookKey(book),
          directory: Directory('${root.path}/data'));
      Future<void> sync(Directory root) => kind == 'ocr'
          ? DocumentReflowSync(
              client: client,
              cache: Directory('${root.path}/cache'),
              durableDirectory: root,
              store: (_) => ocr(root)).sync([book])
          : WereadMetadataSync(
              client: client,
              cache: Directory('${root.path}/cache'),
              durableDirectory: root,
              store: (_) => weread(root)).sync([book]);
      if (kind == 'ocr') {
        await ocr(first).save(
            DocumentReflowPage(
                page: 0, ocr: true, rawText: 'Remote page content'),
            '',
            onlyIfAbsent: true);
      } else {
        await weread(first)
            .bind({'bookId': 'remote-book', 'intro': 'Remote data'});
      }
      await sync(first);
      final uploads = client.uploaded.length;
      client.afterDownload = mark;
      await expectLater(sync(second), throwsA(isA<PrivateBookSyncBlocked>()));
      if (kind == 'ocr') {
        expect(await ocr(second).read(0, ''), isNull);
      } else {
        expect(WereadData.bookId(await weread(second).read()), isNull);
      }
      expect(client.uploaded.length, uploads);
      expect(client.removed, isEmpty);
    });
  }

  test(
      'new and previously queued private deletions leave all cloud objects untouched',
      () async {
    final queue = BookCloudDeletions(File('${temporary.path}/deletions.json'));
    await queue.enqueue(client, [book]);
    await mark();
    client.files[SyncPaths.data(book.filePath)] = [1];
    client.files[SyncPaths.data(book.coverPath)] = [2];
    await queue.apply(client, [book.copyWith(isDeleted: true)]);
    expect(client.removed, isEmpty);
    expect(client.operations, isEmpty);
    final newQueue =
        BookCloudDeletions(File('${temporary.path}/new-deletions.json'));
    await newQueue.enqueue(client, [book]);
    expect(await newQueue.file.readAsString(), '[]');
    expect(client.files, hasLength(2));
  });

  test('a cover marked private during its deletion probe remains in the cloud',
      () async {
    final queue = BookCloudDeletions(File('${temporary.path}/deletions.json'));
    final selected = publicBook.copyWith(coverPath: book.coverPath);
    await queue.enqueue(client, [selected]);
    client.files[SyncPaths.data(selected.filePath)] = [1];
    client.files[SyncPaths.data(book.coverPath)] = [2];
    client.beforeProps = (path) async {
      if (path == SyncPaths.data(book.coverPath)) await mark();
    };
    await queue.apply(client,
        [selected.copyWith(isDeleted: true), book.copyWith(isDeleted: true)]);
    expect(client.removed, [SyncPaths.data(selected.filePath)]);
    expect(client.files[SyncPaths.data(book.coverPath)], [2]);
  });

  test(
      'private marks defer all historical cloud reclamation without touching existing bytes',
      () async {
    await mark();
    final db = await fixture();
    addTearDown(db.close);
    client.files[SyncPaths.data(book.filePath)] = [1, 2, 3];
    final reclaimed = await ReplacedBookFiles(
            store: RowSyncStore(db),
            client: client,
            cache: temporary,
            durableDirectory: temporary)
        .reclaim();
    expect(reclaimed, 0);
    expect(client.operations, isEmpty);
    expect(client.downloads, 0);
    expect(client.removed, isEmpty);
    expect(client.files[SyncPaths.data(book.filePath)], [1, 2, 3]);
  });

  test('legacy checksum maintenance cannot change a private book identity',
      () async {
    final db = await fixture();
    addTearDown(db.close);
    await db.insert('tb_books',
        {...bookRow(book.id, md5: book.md5!), 'file_path': book.filePath});
    await mark();
    final count =
        await ConvertedBookChecksum(db).repairLocalBooks(localFile: (path) {
      expect(path, isNot(book.filePath));
      return File('${temporary.path}/absent-public-file');
    });
    expect(count, 0);
    expect(
        (await db.query('tb_books', where: 'id=?', whereArgs: [book.id]))
            .single['file_md5'],
        book.md5);
  });

  test('damaged privacy settings block every book asset instead of guessing',
      () async {
    SharedPreferences.setMockInitialValues({PrivateLibrary.storageKey: '{'});
    await Prefs().initPrefs();
    expect(privacy.corrupt, true);
    expect(canSyncBookAsset([publicBook], publicBook.filePath), false);
    expect(canSyncBookAsset([publicBook], publicBook.coverPath), false);
    await DocumentReflowSync(
            client: client, cache: temporary, durableDirectory: temporary)
        .sync([publicBook]);
    await WereadMetadataSync(
            client: client, cache: temporary, durableDirectory: temporary)
        .sync([publicBook]);
    expect(client.operations, isEmpty);
    expect(client.downloads, 0);
    expect(client.uploaded, isEmpty);
  });
}
