import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/service/remote_library/ftp_library.dart';

void main() {
  test('accepts an FTP server address and rejects unsafe roots and credentials',
      () {
    expect(FtpLibrary.parseRoot('nas.local:2121', '/有 空格/#书').toString(),
        'ftp://nas.local:2121/%E6%9C%89%20%E7%A9%BA%E6%A0%BC/%23%E4%B9%A6/');
    expect(FtpLibrary.parseRoot('ftp://nas.local/ebooks').path, '/ebooks/');
    expect(FtpLibrary.parseRoot('nas.local').path, '/');
    for (final address in [
      'https://nas.local',
      'ftp://user:secret@nas.local',
      'ftp://nas.local:65536',
      'ftp://nas.local/books?other=1',
      'ftp://nas.local/books%2Fmore/',
      'ftp://nas.local/books/%0Acmd',
    ]) {
      expect(() => FtpLibrary.parseRoot(address), throwsFormatException);
    }
    expect(() => FtpLibrary.parseRoot('nas.local', '/books/../secret'),
        throwsFormatException);
    expect(() => FtpLibrary.validateCredentials('reader', 'pass\r\nSTOR x'),
        throwsFormatException);
    final client = FtpLibrary(FtpLibrary.parseRoot('nas.local', '/books'));
    addTearDown(client.close);
    for (final url in [
      'ftp://nas.local/secret/file.epub',
      'ftp://nas.local:2121/books/file.epub',
      'ftp://nas.local/books/sub%2Ffile.epub',
      'ftp://nas.local/books/%FF.epub',
      'ftp://example.com/books/file.epub',
    ]) {
      expect(client.contains(Uri.parse(url)), isFalse);
    }
  });

  test('lists UTF-8 books and folders, scans nested books and downloads bytes',
      () async {
    final server = await _FtpFixture.start();
    addTearDown(server.close);
    final root = FtpLibrary.parseRoot('127.0.0.1:${server.port}', '/books');
    final client = FtpLibrary(root, username: 'reader', password: ' 字#% ');
    addTearDown(client.close);
    final entries = await client.list(root);
    expect(
        entries.map((entry) => entry.name), ['sub', 'cover.png', '中文 #%.epub']);
    final book = entries.singleWhere((entry) => entry.isBook);
    expect(book.uri.pathSegments.last, '中文 #%.epub');
    expect(book.modifiedAt, DateTime.utc(2026, 10, 31, 12, 34, 56));
    final books = await client.discoverBooks(root, cancelToken: CancelToken());
    expect(books.map((entry) => entry.name), ['中文 #%.epub', 'a.txt']);

    final temporary = await Directory.systemTemp.createTemp('modu-ftp-test');
    addTearDown(() => temporary.delete(recursive: true));
    final file = File('${temporary.path}/book.epub');
    final progress = <(int, int)>[];
    await client.download(book, file, CancelToken(),
        (received, total) => progress.add((received, total)));
    expect(await file.readAsBytes(), _FtpFixture.book);
    expect(progress.last, (_FtpFixture.book.length, _FtpFixture.book.length));
    expect(server.commands, contains('PASS  字#% '));
    expect(server.commands, contains('RETR /books/中文 #%.epub'));
    expect(
        server.commands.every((command) => {
              'USER',
              'PASS',
              'OPTS',
              'TYPE',
              'CWD',
              'EPSV',
              'MLSD',
              'SIZE',
              'RETR'
            }.contains(command.split(' ').first)),
        isTrue);
  });

  test('falls back to legacy lists and connects PASV only to its control peer',
      () async {
    final server = await _FtpFixture.start(legacy: true);
    addTearDown(server.close);
    final client =
        FtpLibrary(FtpLibrary.parseRoot('127.0.0.1:${server.port}', '/books'));
    addTearDown(client.close);
    final entries = await client.list(client.root);
    expect(entries.map((entry) => entry.name),
        ['sub', 'windows folder', 'old name.pdf', '中文 #%.epub']);
    expect(entries.where((entry) => entry.isBook).map((entry) => entry.name),
        ['old name.pdf', '中文 #%.epub']);
    expect(server.commands, contains('USER anonymous'));
    expect(server.commands, contains('PASS anonymous@'));
    expect(server.commands,
        containsAllInOrder(['EPSV', 'PASV', 'MLSD', 'EPSV', 'PASV', 'LIST']));
  });

  test('cancel and incomplete transfers discard staging files', () async {
    final temporary = await Directory.systemTemp.createTemp('modu-ftp-test');
    addTearDown(() => temporary.delete(recursive: true));
    for (final cancelTransfer in [true, false]) {
      final server = await _FtpFixture.start(
          blockDownload: cancelTransfer, wrongSize: !cancelTransfer);
      addTearDown(server.close);
      final client = FtpLibrary(
          FtpLibrary.parseRoot('127.0.0.1:${server.port}', '/books'));
      addTearDown(client.close);
      final token = CancelToken();
      final file = File('${temporary.path}/book.epub');
      final book =
          (await client.list(client.root)).singleWhere((e) => e.isBook);
      final transfer = client.download(book, file, token, (_, __) {});
      final failed = expectLater(
          transfer,
          cancelTransfer
              ? throwsA(isA<DioException>()
                  .having((e) => e.type, 'type', DioExceptionType.cancel))
              : throwsFormatException);
      if (cancelTransfer) {
        await server.downloadStarted.future;
        token.cancel();
      }
      await failed.timeout(const Duration(seconds: 3));
      expect(await file.exists(), isFalse);
      expect(await File('${file.path}.part').exists(), isFalse);
    }
  });
}

class _FtpFixture {
  _FtpFixture(
      this._controlServer, this.legacy, this.blockDownload, this.wrongSize);

  static const book = [65, 31, 0, 255];
  static const _rootListing = 'type=cdir; .\r\n'
      'type=pdir; ..\r\n'
      'type=dir; sub\r\n'
      'type=file;size=4;modify=20261031123456; 中文 #%.epub\r\n'
      'type=file; cover.png\r\n'
      'type=file; ../outside.epub\r\n'
      'type=OS.unix=slink; link.epub\r\n';
  static const _legacyListing = 'total 2\r\n'
      'drwxr-xr-x 1 nobody wheel 0 Oct 31 13:20 sub\r\n'
      'lrwxrwxrwx 1 nobody wheel 9 Oct 31 13:20 escape -> /somewhere\r\n'
      '-r--r--r-- 1 nobody wheel 4 Oct 31 2026 中文 #%.epub\r\n'
      '11-01-26  01:20PM       <DIR>          windows folder\r\n'
      '11-01-26  01:20PM           4          old name.pdf\r\n';

  final ServerSocket _controlServer;
  final bool legacy, blockDownload, wrongSize;
  final commands = <String>[];
  final _connections = <Socket>{};
  final _passiveServers = <ServerSocket>{};
  final downloadStarted = Completer<void>();
  int get port => _controlServer.port;

  static Future<_FtpFixture> start(
      {bool legacy = false,
      bool blockDownload = false,
      bool wrongSize = false}) async {
    final control = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = _FtpFixture(control, legacy, blockDownload, wrongSize);
    control.listen(fixture._serve);
    return fixture;
  }

  Future<void> _serve(Socket control) async {
    _connections.add(control);
    control.done.ignore();
    final lines = control
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    Future<Socket>? dataConnection;
    var directory = '/';
    try {
      control.write('220-Test FTP\r\nBanner text\r\n220 Ready\r\n');
      await for (final command in lines) {
        commands.add(command);
        switch (command.split(' ').first) {
          case 'USER':
            control.write('331 Password required\r\n');
          case 'PASS':
            control.write('230 Logged on\r\n');
          case 'OPTS':
            control.write('200 UTF-8 enabled\r\n');
          case 'TYPE':
            control.write('200 Binary\r\n');
          case 'CWD':
            directory = command.substring(4);
            control.write('250 Directory changed\r\n');
          case 'EPSV' when legacy:
            control.write('500 Not implemented\r\n');
          case 'EPSV' || 'PASV':
            final server =
                await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
            _passiveServers.add(server);
            final accepted = Completer<Socket>();
            server.listen((socket) {
              _connections.add(socket);
              socket.done.ignore();
              accepted.complete(socket);
            });
            dataConnection = accepted.future;
            final port = server.port;
            control.write(command == 'EPSV'
                ? '229 Entering Extended Passive Mode (|||$port|)\r\n'
                : '227 Entering Passive Mode (203,0,113,1,${port ~/ 256},${port % 256})\r\n');
          case 'MLSD' when legacy:
            final data = await dataConnection!;
            data.destroy();
            control.write('500 Not implemented\r\n');
          case 'MLSD' || 'LIST' || 'RETR':
            final data = await dataConnection!;
            control.write('150 Data ready\r\n');
            if (command.startsWith('RETR ')) {
              data.add(book);
              if (blockDownload) {
                await data.flush();
                downloadStarted.complete();
                continue;
              }
            } else {
              data.write(command == 'LIST'
                  ? _legacyListing
                  : directory == '/books/'
                      ? _rootListing
                      : 'type=file;size=4; a.txt\r\n');
            }
            await data.close();
            data.destroy();
            control.write('226 Transfer complete\r\n');
          case 'SIZE':
            control.write('213 ${book.length + (wrongSize ? 1 : 0)}\r\n');
          default:
            control.write('502 Not implemented\r\n');
        }
      }
    } on SocketException {
      // Client disconnects also end cancelled transfers.
    } finally {
      control.destroy();
    }
  }

  Future<void> close() async {
    await _controlServer.close();
    for (final socket in _connections) {
      socket.destroy();
    }
    for (final server in _passiveServers) {
      await server.close();
    }
  }
}
