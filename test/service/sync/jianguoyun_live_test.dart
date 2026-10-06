import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/service/sync/webdav_client.dart';
import 'package:anx_reader/service/sync/webdav_request_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'row_sync_test.dart' show fixture, bookRow, noteRow;

// Explicitly authorized live test only. All mutations go below a fresh UUID
// directory, never /dav/modu. A local relay counts actual outbound requests and
// enforces the scope even if production code builds an unexpected path.
void main() {
  final raw = Platform.environment['MODU_JIANGUOYUN_LIVE_CONFIG'];
  test('read-only directory trailing-slash compatibility on Jianguoyun',
      () async {
    final config = jsonDecode(raw!) as Map;
    final parent = config['testParent'] as String;
    expect(RegExp(r'^modutest-[0-9a-f]{12}$').hasMatch(parent), isTrue);
    final client = WebdavClient(
        url: 'https://dav.jianguoyun.com/dav/',
        username: config['username'] as String,
        password: config['password'] as String);
    try {
      for (final path in [parent, '$parent/']) {
        expect(await client.readSyncDirectory(path), isEmpty);
      }
      print('LIVE real_endpoint_directory_slash_probe=passed writes=0');
    } catch (error) {
      fail(
          'Read-only directory probe failed: ${error.runtimeType}; private details omitted');
    }
  }, skip: raw == null);
  test('isolated Jianguoyun transport, migration and two-device convergence',
      () async {
    final config = jsonDecode(raw!) as Map;
    final parent = config['testParent'] as String?;
    if (parent != null &&
        !RegExp(r'^modutest-[0-9a-f]{12}$').hasMatch(parent)) {
      fail('Invalid isolated test parent');
    }
    final token = const Uuid().v4().replaceAll('-', '').substring(0, 12);
    final root = parent == null ? 'modutest-$token' : '$parent/run-$token';
    final prefix = '/dav/$root';
    final auth =
        'Basic ${base64Encode(utf8.encode('${config['username']}:${config['password']}'))}';
    final relay = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final transport = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    var calls = 0;
    var busy = false;
    var cleaning = false;
    var created = false;
    final methods = <String, int>{};
    relay.listen((incoming) async {
      final response = incoming.response;
      try {
        final path = incoming.uri.path;
        if (path != prefix && !path.startsWith('$prefix/')) {
          response.statusCode = 403;
          await response.close();
          return;
        }
        // Negotiate Basic locally just like the real endpoint. The relay uses
        // the authorized account upstream, never the dummy local credentials.
        if (incoming.headers.value('authorization') == null) {
          response.statusCode = 401;
          response.headers
              .set('www-authenticate', 'Basic realm="isolated-test"');
          await response.close();
          return;
        }
        if (busy || (!cleaning && calls >= 180)) {
          response.statusCode = 503;
          await response.close();
          return;
        }
        calls++;
        methods.update(incoming.method, (n) => n + 1, ifAbsent: () => 1);
        final request = await transport.openUrl(
            incoming.method,
            Uri.https(
                'dav.jianguoyun.com',
                path,
                incoming.uri.queryParameters.isEmpty
                    ? null
                    : incoming.uri.queryParameters));
        request.followRedirects = false;
        incoming.headers.forEach((name, values) {
          if (![
            'host',
            'authorization',
            'connection',
            'content-length',
            'transfer-encoding'
          ].contains(name.toLowerCase())) {
            request.headers.set(name, values);
          }
        });
        request.headers.set('authorization', auth);
        request.contentLength =
            incoming.contentLength >= 0 ? incoming.contentLength : 0;
        await request.addStream(incoming);
        final remote =
            await request.close().timeout(const Duration(seconds: 40));
        print('LIVE HTTP ${incoming.method} ${remote.statusCode}');
        if (incoming.method == 'MKCOL' &&
            path.replaceFirst(RegExp(r'/$'), '') == prefix &&
            remote.statusCode == 201) created = true;
        if ([429, 503].contains(remote.statusCode)) busy = true;
        response.statusCode = remote.statusCode;
        remote.headers.forEach((name, values) {
          if (![
            'connection',
            'transfer-encoding',
            'content-length',
            'content-encoding'
          ].contains(name.toLowerCase())) {
            response.headers.set(name, values);
          }
        });
        await response.addStream(remote);
        await response.close();
      } catch (error) {
        print('LIVE relay_error=${error.runtimeType}');
        response.statusCode = 502;
        await response.close();
      }
    });
    final client = WebdavClient(
        url: 'http://127.0.0.1:${relay.port}/dav/$root',
        username: 'isolated-test',
        password: 'relay-only');
    client.requestPolicy = WebdavRequestPolicy(jianguoyun: true);
    // A setup client addresses only the fresh root through the same relay.
    final setup = WebdavClient(
        url: 'http://127.0.0.1:${relay.port}/dav',
        username: 'isolated-test',
        password: 'relay-only');
    final temp = await Directory.systemTemp.createTemp('modu-live-jgy-');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final a = await fixture(install: false, path: '${temp.path}/a.db');
    final b = await fixture(install: false, path: '${temp.path}/b.db');
    try {
      print('LIVE test_directory=$root');
      expect(await setup.readProps(root), isNull);
      await setup.mkdirAll(root);
      created = true;
      print('LIVE isolated_directory_created=true');
      await client.ping();
      await client.mkdirAll('modu/data/file');
      await client.mkdirAll('modu/data/cover');
      // Synthetic bytes test WebDAV transport, not ebook parser support.
      for (final extension in [
        'txt',
        'md',
        'epub',
        'mobi',
        'azw3',
        'fb2',
        'pdf'
      ]) {
        final source = File('${temp.path}/asset.$extension');
        await source.writeAsString('Synthetic sync fixture 中文 $extension\n');
        final path = 'modu/data/file/测试书籍.$extension';
        await client.uploadFile(source.path, path);
        final copy = '${temp.path}/copy.$extension';
        await client.downloadFile(path, copy);
        expect(await File(copy).readAsString(), await source.readAsString());
      }
      expect((await client.readDir('modu/data/file')).length, 7);
      print('LIVE seven_asset_extensions_roundtrip=passed');

      // Publish an actual legacy version-7 SQLite database in the test folder.
      final legacy =
          await fixture(install: false, path: '${temp.path}/legacy.db');
      await legacy.insert('tb_notes', noteRow(1, 'legacy-note'));
      await legacy.close();
      final legacyBytes = await File('${temp.path}/legacy.db').readAsBytes();
      await client.uploadFile('${temp.path}/legacy.db', 'modu/database7.db');
      for (final db in [a, b]) {
        await db.delete('tb_books');
        await db.transaction((txn) => RowSyncStore.install(txn));
      }
      final sa = RowSyncStore(a), sb = RowSyncStore(b);
      final cacheA = await Directory('${temp.path}/cache-a').create();
      final cacheB = await Directory('${temp.path}/cache-b').create();
      Future<RowSyncOutcome> sync(RowSyncStore store, Directory cache) =>
          RowSyncEngine(store: store, client: client, cache: cache)
              .synchronize();
      await sync(sa, cacheA);
      expect((await a.query('tb_books')).length, 1);
      expect((await a.query('tb_notes')).length, 1);
      await sync(sb, cacheB);
      expect((await b.query('tb_books')).length, 1);
      print('LIVE legacy_migration_and_empty_device_discovery=passed');

      final aId = (await a.query('tb_books')).single['id'] as int;
      final bId = (await b.query('tb_books')).single['id'] as int;
      await a.insert('tb_notes', noteRow(aId, 'device-a'));
      await b.insert('tb_notes', noteRow(bId, 'device-b'));
      await b.insert('tb_books', bookRow(bId + 1, md5: 'device-b-new-book'));
      await sync(sa, cacheA);
      await sync(sb, cacheB);
      await sync(sa, cacheA);
      expect((await a.query('tb_books')).length, 2);
      expect((await a.query('tb_notes')).length, 3);
      expect(sameSyncRecords(await sa.snapshot(), await sb.snapshot()), isTrue);
      print('LIVE offline_edits_and_new_book_convergence=passed');
      final before = calls;
      expect(await sync(sa, cacheA), RowSyncOutcome.unchanged);
      print('LIVE unchanged_sync_requests=${calls - before}');
      await client.downloadFile(
          'modu/database7.db', '${temp.path}/legacy-after.db');
      expect(await File('${temp.path}/legacy-after.db').readAsBytes(),
          legacyBytes);
      print('LIVE legacy_cloud_file_preserved=passed');
      print('LIVE workload_requests=$calls methods=$methods');
    } catch (error, stack) {
      fail(
          'Live isolated test failed: ${error.runtimeType} status=${error is DioException ? error.response?.statusCode : null}; private details omitted\n$stack');
    } finally {
      if (created && !busy) {
        cleaning = true;
        try {
          // Jianguoyun can reject deletion of a nonempty collection, and
          // forbids deleting its top-level sync folder through WebDAV. Remove
          // only children below our verified UUID root first; never fall back
          // to any parent or the user's production modu directory.
          Future<void> removeChildren(String directory) async {
            final children = await setup.readSyncDirectory('$directory/');
            for (final child in children) {
              final name = child.name;
              if (name == null ||
                  name.isEmpty ||
                  name.contains('/') ||
                  name.contains('\\') ||
                  name == '.' ||
                  name == '..') {
                throw StateError('Unsafe cleanup child');
              }
              final path = '$directory/$name';
              if (child.isDir == true) await removeChildren(path);
              await setup.remove(child.isDir == true ? '$path/' : path);
            }
          }

          await removeChildren(root);
          expect(await setup.readSyncDirectory('$root/'), isEmpty);
          print('LIVE test_contents_removed=true');
          await setup.remove(root);
          expect(await setup.readProps(root), isNull);
          print('LIVE isolated_directory_removed=true');
        } catch (_) {
          print('LIVE cleanup_pending=$root');
        }
      } else if (created) {
        print('LIVE cleanup_deferred_for_server_cooldown=$root');
      }
      print('LIVE requests=$calls methods=$methods server_busy=$busy');
      await a.close();
      await b.close();
      await temp.delete(recursive: true);
      await relay.close(force: true);
      transport.close(force: true);
    }
  }, skip: raw == null, timeout: const Timeout(Duration(minutes: 12)));
}
