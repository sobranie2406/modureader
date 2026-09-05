import 'dart:convert';
import 'dart:io';
import 'package:anx_reader/models/book.dart';
import 'package:crypto/crypto.dart';

Future<String> bookSourceFingerprint(Book book) async {
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
