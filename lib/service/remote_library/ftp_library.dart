import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:modu_reader/service/remote_library/webdav_library.dart';

enum FtpFailure {
  connection,
  authentication,
  notFound,
  invalidResponse,
  server
}

class FtpLibraryException implements Exception {
  const FtpLibraryException(this.failure, {this.code});
  final FtpFailure failure;
  final int? code;
}

final _controlCharacters = RegExp(r'[\x00-\x1f\x7f]');

bool _safePathSegment(String part) =>
    part != '.' &&
    part != '..' &&
    !part.contains('/') &&
    !part.contains('\\') &&
    !_controlCharacters.hasMatch(part);

bool _safeUri(Uri uri) {
  try {
    return uri.scheme == 'ftp' &&
        uri.hasAuthority &&
        uri.host.isNotEmpty &&
        !uri.authority.contains('@') &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        (!uri.hasPort || (uri.port > 0 && uri.port <= 65535)) &&
        uri.pathSegments.every(_safePathSegment);
  } on FormatException {
    return false;
  }
}

class FtpLibrary extends RemoteLibrary {
  FtpLibrary(this.root, {String username = '', String password = ''})
      : _username = username,
        _password = password {
    if (!_safeUri(root) || !root.path.endsWith('/')) {
      throw const FormatException('Invalid FTP root');
    }
    validateCredentials(username, password);
  }

  @override
  final Uri root;
  final String _username, _password;
  final _sessions = <_FtpSession>{};
  bool _closed = false;

  static Uri parseRoot(String address, [String directory = '']) {
    final input = address.trim();
    final url = input.contains('://') ? input : 'ftp://$input';
    final uri = Uri.tryParse(url);
    if (uri == null ||
        _controlCharacters.hasMatch(input) ||
        RegExp(r'\s').hasMatch(uri.authority) ||
        !_safeUri(uri)) {
      throw const FormatException('Invalid FTP address');
    }
    final parts = directory.isEmpty ? uri.pathSegments : directory.split('/');
    if (!parts.every(_safePathSegment)) {
      throw const FormatException('Invalid FTP directory');
    }
    return uri.replace(
        pathSegments: ['', ...parts.where((part) => part.isNotEmpty), '']);
  }

  static void validateCredentials(String username, String password) {
    if (_controlCharacters.hasMatch(username) ||
        _controlCharacters.hasMatch(password)) {
      throw const FormatException('Invalid FTP credentials');
    }
  }

  @override
  bool contains(Uri uri) =>
      _safeUri(uri) &&
      uri.host == root.host &&
      _ftpPort(uri) == _ftpPort(root) &&
      uri.path.startsWith(root.path);

  void _check(Uri uri) {
    if (!contains(uri)) {
      throw const FormatException('Outside configured library');
    }
  }

  static int _ftpPort(Uri uri) => uri.hasPort ? uri.port : 21;

  static String _path(Uri uri) => '/${uri.pathSegments.join('/')}';

  Future<T> _run<T>(CancelToken? cancelToken,
      Future<T> Function(_FtpSession session) operation) async {
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    if (_closed) throw const FtpLibraryException(FtpFailure.connection);
    final session = _FtpSession();
    _sessions.add(session);
    final cancellation = cancelToken?.whenCancel.asStream().listen((_) {
      session.close();
    });
    try {
      await session.open(root.host, _ftpPort(root), _username, _password);
      final result = await operation(session);
      session.checkOpen();
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      return result;
    } catch (error) {
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      if (error is SocketException || error is TimeoutException) {
        throw const FtpLibraryException(FtpFailure.connection);
      }
      rethrow;
    } finally {
      session.close();
      _sessions.remove(session);
      await cancellation?.cancel();
    }
  }

  @override
  Future<List<LibraryEntry>> list(Uri directory, {CancelToken? cancelToken}) {
    _check(directory);
    final folder = directory.path.endsWith('/')
        ? directory
        : directory.replace(path: '${directory.path}/');
    return _run(cancelToken, (session) async {
      session.require(await session.command('CWD ${_path(folder)}'), {250});
      final bytes = BytesBuilder(copy: false);
      Future<void> readListing(Stream<Uint8List> stream) async {
        await for (final chunk in stream) {
          if (bytes.length + chunk.length > WebdavLibrary.maxListingBytes) {
            throw const LibraryListingException('tooLarge');
          }
          bytes.add(chunk);
        }
      }

      var machineReadable = true;
      try {
        await session.receive('MLSD', readListing);
      } on FtpLibraryException catch (error) {
        if (bytes.length != 0 ||
            !{500, 501, 502, 504, 550}.contains(error.code)) {
          rethrow;
        }
        machineReadable = false;
        await session.receive('LIST', readListing);
      }
      return compute(
          _parseListing, (bytes.takeBytes(), folder, machineReadable));
    });
  }

  @override
  Future<void> download(LibraryEntry entry, File target, CancelToken cancel,
      void Function(int received, int total) onProgress) async {
    _check(entry.uri);
    if (!entry.isBook ||
        entry.uri.path.endsWith('/') ||
        (entry.size ?? 0) > WebdavLibrary.maxBookBytes) {
      throw const FormatException('Unsupported file or file too large');
    }
    final partial = File('${target.path}.part');
    if (await target.exists() || await partial.exists()) {
      throw StateError('Download staging file already exists');
    }
    RandomAccessFile? output;
    var ownsPartial = false;
    try {
      await _run(cancel, (session) async {
        final path = _path(entry.uri);
        final size = await session.command('SIZE $path');
        final sizeText =
            size.text.length > 4 ? size.text.substring(4).trim() : '';
        final total = (size.code == 213 ? int.tryParse(sizeText) : null) ??
            entry.size ??
            -1;
        if (total > WebdavLibrary.maxBookBytes) {
          throw const FormatException('File too large');
        }
        await partial.create(exclusive: true);
        ownsPartial = true;
        final file = await partial.open(mode: FileMode.write);
        output = file;
        var received = 0;
        await session.receive('RETR $path', (stream) async {
          await for (final chunk in stream) {
            session.checkOpen();
            received += chunk.length;
            if (received > WebdavLibrary.maxBookBytes) {
              throw const FormatException('File too large');
            }
            await file.writeFrom(chunk);
            onProgress(received, total);
          }
        });
        if (received == 0 || (total >= 0 && received != total)) {
          throw const FormatException('Incomplete download');
        }
      });
      await output!.close();
      output = null;
      if (cancel.isCancelled) throw cancel.cancelError!;
      if (_closed) throw const FtpLibraryException(FtpFailure.connection);
      await partial.rename(target.path);
      ownsPartial = false;
    } finally {
      await output?.close();
      if (ownsPartial && await partial.exists()) await partial.delete();
    }
  }

  @override
  void close() {
    _closed = true;
    for (final session in _sessions) {
      session.close();
    }
  }
}

typedef _FtpReply = ({int code, String text});

class _FtpSession {
  static const _connectTimeout = Duration(seconds: 15);
  static const _ioTimeout = Duration(seconds: 30);
  static const _maxReplyBytes = 64 * 1024;
  static final _replyPattern = RegExp(r'^(\d{3})([ -]|$)');
  static final _epsvPattern = RegExp(r'\((.)(?:\1){2}(\d{1,5})\1\)');
  static final _pasvPattern =
      RegExp(r'(?:\d{1,3},\s*){4}(\d{1,3}),\s*(\d{1,3})');
  static const _badResponse = FtpLibraryException(FtpFailure.invalidResponse);
  static const _connectionError = FtpLibraryException(FtpFailure.connection);
  final _stopped = Completer<void>();
  Socket? _control, _data;
  StreamIterator<Uint8List>? _reader;
  List<int> _buffer = const [];
  int _position = 0;

  void checkOpen() {
    if (_stopped.isCompleted) throw _connectionError;
  }

  Future<Socket> _connect(Object host, int port) async {
    checkOpen();
    return Future.any([
      Socket.connect(host, port, timeout: _connectTimeout).then((socket) {
        if (_stopped.isCompleted) {
          socket.destroy();
          throw _connectionError;
        }
        socket.done.ignore();
        return socket;
      }),
      _stopped.future.then<Socket>((_) => throw _connectionError),
    ]);
  }

  Future<void> open(String host, int port, String user, String password) async {
    _control = await _connect(host, port);
    checkOpen();
    _control!.setOption(SocketOption.tcpNoDelay, true);
    _reader = StreamIterator(_control!);
    final greeting = await _readReply();
    require(greeting.code == 120 ? await _readReply() : greeting, {220});
    final login = await command('USER ${user.isEmpty ? 'anonymous' : user}');
    require(
      login.code == 331
          ? await command(
              'PASS ${user.isEmpty && password.isEmpty ? 'anonymous@' : password}')
          : login,
      {202, 230},
      FtpFailure.authentication,
    );
    await command('OPTS UTF8 ON');
    require(await command('TYPE I'), {200});
  }

  Future<_FtpReply> command(String message) async {
    checkOpen();
    _control!.add(utf8.encode('$message\r\n'));
    await _control!.flush().timeout(_ioTimeout);
    return _readReply();
  }

  Future<String> _line() async {
    final line = BytesBuilder(copy: false);
    while (true) {
      checkOpen();
      if (_position == _buffer.length) {
        if (!await _reader!.moveNext()) throw _connectionError;
        _buffer = _reader!.current;
        _position = 0;
      }
      final newline = _buffer.indexOf(10, _position);
      final end = newline < 0 ? _buffer.length : newline;
      if (line.length + end - _position > _maxReplyBytes) throw _badResponse;
      line.add(_buffer.sublist(_position, end));
      _position = end;
      if (newline >= 0) {
        _position++;
        final bytes = line.takeBytes();
        final length = bytes.isNotEmpty && bytes.last == 13
            ? bytes.length - 1
            : bytes.length;
        return utf8.decode(Uint8List.sublistView(bytes, 0, length),
            allowMalformed: true);
      }
    }
  }

  Future<_FtpReply> _readReply() => _readReplyLines().timeout(_ioTimeout);

  Future<_FtpReply> _readReplyLines() async {
    var line = await _line();
    final match = _replyPattern.firstMatch(line);
    if (match == null) throw _badResponse;
    final code = int.parse(match[1]!);
    if (match[2] == '-') {
      final end = '$code ';
      var remaining = _maxReplyBytes;
      do {
        remaining -= line.length + 1;
        if (remaining <= 0) throw _badResponse;
        line = await _line();
      } while (!line.startsWith(end));
    }
    return (code: code, text: line);
  }

  void require(_FtpReply reply, Set<int> expected, [FtpFailure? onError]) {
    if (expected.contains(reply.code)) return;
    final failure = onError ??
        switch (reply.code) {
          530 => FtpFailure.authentication,
          550 => FtpFailure.notFound,
          _ => FtpFailure.server,
        };
    throw FtpLibraryException(failure, code: reply.code);
  }

  Future<Socket> _passiveSocket() async {
    final peer = _control!.remoteAddress;
    final extended = await command('EPSV');
    int? port;
    if (extended.code == 229) {
      port = int.tryParse(_epsvPattern.firstMatch(extended.text)?[2] ?? '');
    } else {
      if (peer.type != InternetAddressType.IPv4) require(extended, {229});
      final passive = await command('PASV');
      require(passive, {227});
      final fields = _pasvPattern.firstMatch(passive.text);
      if (fields != null) {
        final high = int.parse(fields[1]!);
        final low = int.parse(fields[2]!);
        if (high <= 255 && low <= 255) port = high * 256 + low;
      }
    }
    if (port == null || port < 1 || port > 65535) throw _badResponse;
    // PASV can advertise a different host. Keep data on the control peer.
    return _connect(peer, port);
  }

  Future<void> receive(
      String request, Future<void> Function(Stream<Uint8List>) read) async {
    final data = await _passiveSocket();
    _data = data;
    try {
      require(await command(request), {125, 150});
      await read(data.timeout(_ioTimeout));
      require(await _readReply(), {226, 250});
    } finally {
      data.destroy();
      _data = null;
    }
  }

  void close() {
    if (!_stopped.isCompleted) _stopped.complete();
    _control?.destroy();
    _data?.destroy();
    _reader?.cancel().ignore();
  }
}

final _unixList = RegExp(
    r'^([d\-lcbps])[rwxStTs-]{9}[+@.]?\s+\d+\s+\S+\s+\S+\s+(\d+)\s+\S+\s+\d{1,2}\s+(?:\d{1,2}:\d{2}|\d{4})\s(.+)$');
final _dosList = RegExp(
    r'^[\d/-]+\s+\d{1,2}:\d{2}(?:\s*[AP]M)?\s+(<DIR>|\d+)\s+(.+)$',
    caseSensitive: false);
final _listTotal = RegExp(r'^total\s+\d+\s*$');
final _ftpDate = RegExp(r'^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(?:\.(\d+))?$');

DateTime? _parseDate(String? value) {
  final match = value == null ? null : _ftpDate.firstMatch(value);
  if (match == null) return null;
  final fraction = match[7] == null ? '' : '.${match[7]}';
  return DateTime.tryParse(
      '${match[1]}-${match[2]}-${match[3]}T${match[4]}:${match[5]}:${match[6]}${fraction}Z');
}

typedef _ListRow = ({
  String name,
  bool? directory,
  int? size,
  DateTime? created,
  DateTime? modified,
});

_ListRow? _machineRow(String line) {
  final space = line.indexOf(' ');
  if (space < 0) return null;
  final facts = <String, String>{};
  for (final field in line.substring(0, space).split(';')) {
    final equals = field.indexOf('=');
    if (equals < 1) continue;
    facts[field.substring(0, equals).toLowerCase()] =
        field.substring(equals + 1);
  }
  final type = facts['type']?.toLowerCase();
  if (type == null) return null;
  return (
    name: line.substring(space + 1),
    directory: switch (type) { 'dir' => true, 'file' => false, _ => null },
    size: int.tryParse(facts['size'] ?? ''),
    created: _parseDate(facts['create']),
    modified: _parseDate(facts['modify']),
  );
}

_ListRow? _legacyRow(String line) {
  final unix = _unixList.firstMatch(line);
  if (unix != null) {
    return (
      name: unix[3]!,
      directory: switch (unix[1]) { 'd' => true, '-' => false, _ => null },
      size: int.tryParse(unix[2]!),
      created: null,
      modified: null,
    );
  }
  final dos = _dosList.firstMatch(line);
  if (dos == null) return null;
  return (
    name: dos[2]!,
    directory: dos[1]!.toUpperCase() == '<DIR>',
    size: int.tryParse(dos[1]!),
    created: null,
    modified: null,
  );
}

List<LibraryEntry> _parseListing((Uint8List, Uri, bool) input) {
  final (bytes, folder, machineReadable) = input;
  final entries = <String, LibraryEntry>{};
  final parent = folder.pathSegments.where((segment) => segment.isNotEmpty);
  var unrecognized = false;
  var recognized = false;
  for (final line
      in LineSplitter.split(utf8.decode(bytes, allowMalformed: true))) {
    if (line.trim().isEmpty ||
        (!machineReadable && _listTotal.hasMatch(line))) {
      continue;
    }
    final row = machineReadable ? _machineRow(line) : _legacyRow(line);
    if (row == null) {
      unrecognized = true;
      continue;
    }
    recognized = true;
    final name = row.name, isDirectory = row.directory;
    if (isDirectory == null ||
        name.isEmpty ||
        name.contains('\uFFFD') ||
        !_safePathSegment(name)) {
      continue;
    }
    final uri = folder
        .replace(pathSegments: ['', ...parent, name, if (isDirectory) '']);
    entries[name] = LibraryEntry(
        uri, name, isDirectory, (row.size ?? -1) >= 0 ? row.size : null,
        createdAt: row.created, modifiedAt: row.modified);
  }
  if (unrecognized && !recognized) {
    throw const LibraryListingException('invalid');
  }
  return entries.values.toList()
    ..sort((a, b) => a.isDirectory != b.isDirectory
        ? (a.isDirectory ? -1 : 1)
        : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}
