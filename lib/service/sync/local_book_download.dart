import 'dart:io';
import 'package:crypto/crypto.dart';

/// Publish a complete file once; parallel callers share the same transfer.
class LocalBookDownload {
  final Map<String, Future<void>> _pending = {};

  Future<void> ensure(File target,
      {String? expectedMd5,
      required Future<void> Function(File temporary) download}) async {
    final key = target.absolute.path;
    final pending = _pending[key];
    if (pending != null) {
      await pending;
      return ensure(target, expectedMd5: expectedMd5, download: download);
    }
    final task = _receive(target, expectedMd5, download);
    _pending[key] = task;
    try {
      await task;
    } finally {
      if (identical(_pending[key], task)) _pending.remove(key);
    }
  }

  Future<bool> _valid(File file, String? expected) async {
    if (!await file.exists() || await file.length() == 0) return false;
    if (expected == null || !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(expected)) {
      return true;
    }
    return (await md5.bind(file.openRead()).first).toString() ==
        expected.toLowerCase();
  }

  Future<void> _receive(File target, String? expected,
      Future<void> Function(File) download) async {
    if (await _valid(target, expected)) return;
    await target.parent.create(recursive: true);
    final staging = await target.parent.createTemp('.modu-download-');
    try {
      final temporary = File('${staging.path}/book');
      await download(temporary);
      if (!await _valid(temporary, expected)) {
        throw const FormatException(
            'Downloaded book checksum or size is invalid');
      }
      await temporary.rename(target.path);
    } finally {
      await staging.delete(recursive: true);
    }
  }
}
