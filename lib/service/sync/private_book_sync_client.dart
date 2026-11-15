import 'package:dio/dio.dart';
import 'package:modu_reader/models/remote_file.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/service/sync/sync_client_base.dart';

class PrivateBookSyncBlocked implements Exception {
  const PrivateBookSyncBlocked();
  @override
  String toString() => 'Private book synchronization is disabled';
}

/// Rechecks a book's local policy across asynchronous transfer boundaries.
class PrivateBookSyncClient extends SyncClientBase {
  PrivateBookSyncClient(this.delegate, this.allowed);
  final SyncClientBase delegate;
  final bool Function() allowed;

  void check() {
    if (!allowed()) throw const PrivateBookSyncBlocked();
  }

  Future<T> _run<T>(Future<T> Function() operation) async {
    check();
    final result = await operation();
    check();
    return result;
  }

  @override
  List<Object?> get syncIdentity => delegate.syncIdentity;
  @override
  String get protocolName => delegate.protocolName;
  @override
  Map<String, dynamic> get config => delegate.config;
  @override
  bool get isConfigured => delegate.isConfigured;
  @override
  void updateConfig(Map<String, dynamic> config) =>
      delegate.updateConfig(config);
  @override
  Future<bool> supportsAtomicSyncWrites() =>
      _run(delegate.supportsAtomicSyncWrites);
  @override
  Future<void> ping() => _run(delegate.ping);
  @override
  Future<void> testFullCapabilities() => _run(delegate.testFullCapabilities);
  @override
  Future<void> mkdirAll(String path) => _run(() => delegate.mkdirAll(path));
  @override
  Future<List<RemoteFile>> readDir(String path) =>
      _run(() => delegate.readDir(path));
  @override
  Future<List<RemoteFile>> safeReadDir(String path) =>
      _run(() => delegate.safeReadDir(path));
  @override
  Future<List<RemoteFile>> readSyncDirectory(String path) =>
      _run(() => delegate.readSyncDirectory(path));
  @override
  Future<RemoteFile?> readProps(String path) =>
      _run(() => delegate.readProps(path));
  @override
  Future<bool> isExist(String path) => _run(() => delegate.isExist(path));
  @override
  Future<void> remove(String path) => _run(() => delegate.remove(path));
  @override
  Future<void> uploadFileConditionally(String localPath, String remotePath,
          {String? expectedETag, bool createOnly = false}) =>
      _run(() => delegate.uploadFileConditionally(localPath, remotePath,
          expectedETag: expectedETag, createOnly: createOnly));

  @override
  Future<void> uploadFile(String local, String remote,
      {bool replace = true,
      void Function(int, int)? onProgress,
      CancelToken? cancelToken}) async {
    check();
    final token = cancelToken ?? CancelToken();
    void changed() {
      if (!allowed()) token.cancel(const PrivateBookSyncBlocked());
    }

    PrivateLibrary.instance.addListener(changed);
    try {
      await _run(() => delegate.uploadFile(local, remote,
              replace: replace, cancelToken: token, onProgress: (sent, total) {
            check();
            onProgress?.call(sent, total);
          }));
    } finally {
      PrivateLibrary.instance.removeListener(changed);
    }
  }

  @override
  Future<void> downloadFile(String remote, String local,
          {void Function(int, int)? onProgress}) =>
      _run(() =>
          delegate.downloadFile(remote, local, onProgress: (received, total) {
            check();
            onProgress?.call(received, total);
          }));
}
