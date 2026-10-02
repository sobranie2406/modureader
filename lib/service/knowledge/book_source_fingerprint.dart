import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:anx_reader/models/book.dart';
import 'package:crypto/crypto.dart';

class _DigestValue implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

final _contentFingerprints =
    <String, Future<({String identity, String md5})>>{};

String _statKey(String path, FileStat stat) =>
    '$path:${stat.size}:${stat.modified.microsecondsSinceEpoch}:${stat.changed.microsecondsSinceEpoch}';

Future<String> bookSourceFingerprint(Book book) async {
  return (await _bookDigests(book)).identity;
}

Future<({String identity, String md5})> _bookDigests(Book book) async {
  final file = File(book.fileFullPath);
  final stat = await file.stat();
  if (stat.type != FileSystemEntityType.file) {
    throw const FileSystemException('书籍文件不可用');
  }
  final path = file.absolute.path;
  final key = _statKey(path, stat);
  if (_contentFingerprints.length > 128) _contentFingerprints.clear();
  // Metadata only avoids repeated hashing within this process. It never forms
  // the persisted identity: copies, storage migrations and upgrades retain the
  // same identity when their actual bytes are unchanged.
  final pending = _contentFingerprints[key] ??= Isolate.run(() async {
    final strongValue = _DigestValue(), legacyValue = _DigestValue();
    final strong = sha256.startChunkedConversion(strongValue);
    final legacy = md5.startChunkedConversion(legacyValue);
    await for (final chunk in File(path).openRead()) {
      strong.add(chunk);
      legacy.add(chunk);
    }
    strong.close();
    legacy.close();
    return (
      identity: 'sha256:${strongValue.value!}',
      md5: legacyValue.value!.toString()
    );
  });
  try {
    final result = await pending;
    if (_statKey(path, await file.stat()) != key) {
      throw const FileSystemException('书籍文件在校验期间发生变化');
    }
    return result;
  } on Object {
    if (identical(_contentFingerprints[key], pending)) {
      _contentFingerprints.remove(key);
    }
    rethrow;
  }
}

/// Recognize old indexes only when the original metadata identity still
/// matches. A mismatch requires local text verification, never blind adoption.
Future<String?> legacyBookSourceFingerprint(Book book) async {
  // Old metadata only proves unchanged content if the imported MD5 still
  // matches the actual bytes. Same-size/timestamp replacements must not pass.
  if (book.md5 == null ||
      !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(book.md5!) ||
      (await _bookDigests(book)).md5 != book.md5!.toLowerCase()) {
    return null;
  }
  final stat = await File(book.fileFullPath).stat();
  if (stat.type != FileSystemEntityType.file) {
    throw const FileSystemException('书籍文件不可用');
  }
  return sha256
      .convert(utf8.encode(jsonEncode([
        book.filePath,
        book.md5,
        stat.size,
        stat.modified.microsecondsSinceEpoch,
      ])))
      .toString();
}
