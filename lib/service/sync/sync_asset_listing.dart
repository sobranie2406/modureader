import 'dart:convert';

import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:anx_reader/service/sync/sync_paths.dart';

/// A hint for one synchronization only. Never cache database/log listings.
/// Re-read a directory if local/merged asset references change during the run.
class SyncAssetListing {
  SyncAssetListing(this.client) : _endpoint = _identity(client);
  final SyncClientBase client;
  final String _endpoint;
  final _references = <String, Set<String>>{};
  final _names = <String, Set<String>>{};

  static String _identity(SyncClientBase client) => jsonEncode(client.syncIdentity);

  void _checkEndpoint() {
    if (_identity(client) != _endpoint) {
      throw StateError('Sync endpoint changed during asset synchronization');
    }
  }

  Future<Set<String>> read(
      String directory, Iterable<String> references) async {
    _checkEndpoint();
    if (directory != SyncPaths.books && directory != SyncPaths.covers) {
      throw ArgumentError('Only book and cover listings may be reused');
    }
    final paths = references.toSet();
    final previous = _references[directory];
    if (previous == null ||
        previous.length != paths.length ||
        !previous.containsAll(paths)) {
      final files = await client.safeReadDir(directory);
      _checkEndpoint();
      final prefix = directory == SyncPaths.books ? 'file' : 'cover';
      _names[directory] = {for (final file in files) '$prefix/${file.name!}'};
      _references[directory] = paths;
    }
    return Set.of(_names[directory]!);
  }

  void uploaded(String relativePath) {
    _checkEndpoint();
    final directory =
        relativePath.startsWith('file/') ? SyncPaths.books : SyncPaths.covers;
    _names[directory]?.add(relativePath);
  }

  List<String>? get bookNames {
    _checkEndpoint();
    return _names[SyncPaths.books]?.map((p) => p.substring(5)).toList();
  }
}
