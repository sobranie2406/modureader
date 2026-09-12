import 'dart:io' as io;

import 'package:anx_reader/models/remote_file.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:anx_reader/service/sync/sync_paths.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:dio/dio.dart';
import 'package:webdav_client/webdav_client.dart';
import 'package:xml/xml.dart';

class WebdavClient extends SyncClientBase {
  late Client _client;
  late Map<String, dynamic> _config;

  WebdavClient({
    required String url,
    required String username,
    required String password,
  }) {
    _config = {
      'url': url,
      'username': username,
      'password': password,
    };
    _initClient();
  }

  void _initClient() {
    _client = newClient(
      _config['url'],
      user: _config['username'],
      password: _config['password'],
      debug: false,
    )
      ..setHeaders({
        'accept-charset': 'utf-8',
        'Content-Type': 'application/octet-stream'
      })
      ..setConnectTimeout(8000);
  }

  @override
  Future<void> ping() async {
    // Automatic startup probes are retried with backoff by SyncPreflight.
    // Do not stack three immediate retries (or log private request URLs).
    // Bound only the probe, not large book uploads on slow connections.
    final response =
        await _client.c.req(_client, 'OPTIONS', '/', optionsHandler: (options) {
      options.headers?['depth'] = '0';
      options.receiveTimeout = const Duration(seconds: 12);
      options.sendTimeout = const Duration(seconds: 12);
    });
    if (response.statusCode != 200) {
      throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse);
    }
  }

  @override
  Future<void> testFullCapabilities() async {
    const testDir = SyncPaths.connectionTest;
    const testFile = '$testDir/test.txt';
    io.File? localTestFile;
    io.File? downloadTestFile;

    try {
      AnxLog.info('WebDAV full test: Starting comprehensive test');

      // 1. Create local temporary test file
      final tempDir = await getAnxTempDir();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      localTestFile = io.File('${tempDir.path}/webdav_test_$timestamp.txt');

      final testContent = 'Modu WebDAV Test\n'
          'Test Time: ${DateTime.now()}\n'
          'Platform: ${AnxPlatform.type.name}\n'
          'Timestamp: $timestamp\n';

      await localTestFile.writeAsString(testContent);
      AnxLog.info('WebDAV full test: Created local test file');

      // 2. Create remote test directory
      try {
        await mkdirAll(testDir);
        AnxLog.info('WebDAV full test: Created remote directory');
      } catch (e) {
        AnxLog.severe('WebDAV full test: Failed to create directory: $e');
        throw Exception('Failed to create test directory');
      }

      // 3. Upload test file
      try {
        await uploadFile(localTestFile.path, testFile, replace: true);
        AnxLog.info('WebDAV full test: Uploaded test file');
      } catch (e) {
        AnxLog.severe('WebDAV full test: Failed to upload file: $e');
        throw Exception('Failed to upload test file');
      }

      // 4. Download and verify content
      try {
        downloadTestFile =
            io.File('${tempDir.path}/webdav_download_test_$timestamp.txt');
        await downloadFile(testFile, downloadTestFile.path);
        final downloadedContent = await downloadTestFile.readAsString();
        AnxLog.info('WebDAV full test: Downloaded test file');

        if (downloadedContent != testContent) {
          AnxLog.severe(
              'WebDAV full test: Content mismatch\nExpected: $testContent\nGot: $downloadedContent');
          throw Exception('Test file content mismatch, data integrity issue');
        }
        AnxLog.info('WebDAV full test: Content verification passed');
      } catch (e) {
        if (e.toString().contains('content mismatch')) {
          rethrow;
        }
        AnxLog.severe('WebDAV full test: Failed to download file: $e');
        throw Exception('Failed to download test file');
      }

      // 5. Delete remote test file
      try {
        await remove(testFile);
        AnxLog.info('WebDAV full test: Deleted remote test file');
      } catch (e) {
        AnxLog.warning('WebDAV full test: Failed to delete test file: $e');
        // Don't throw here, test is essentially successful
      }

      // 6. Try to delete test directory (may fail if not empty, that's ok)
      try {
        await remove(testDir);
        AnxLog.info('WebDAV full test: Deleted test directory');
      } catch (e) {
        AnxLog.info(
            'WebDAV full test: Could not delete test directory (may not be empty)');
        // Ignore error - directory might not be empty or already deleted
      }

      // 7. Clean up local files
      if (await localTestFile.exists()) {
        await localTestFile.delete();
      }
      if (await downloadTestFile.exists()) {
        await downloadTestFile.delete();
      }

      AnxLog.info('WebDAV full test: All tests passed successfully');
    } catch (e) {
      // Clean up resources on error
      try {
        if (localTestFile != null && await localTestFile.exists()) {
          await localTestFile.delete();
        }
        if (downloadTestFile != null && await downloadTestFile.exists()) {
          await downloadTestFile.delete();
        }
      } catch (cleanupError) {
        AnxLog.warning('WebDAV full test: Cleanup error: $cleanupError');
      }
      rethrow;
    }
  }

  @override
  Future<void> mkdirAll(String path) async {
    await _client.mkdirAll(path);
  }

  @override
  Future<bool> isExist(String path) async {
    return (await readProps(path)) != null;
  }

  @override
  Future<List<RemoteFile>> readDir(String path) async {
    return (await _client.readDir(path))
        .map((file) => file.toRemoteFile())
        .toList();
  }

  @override
  Future<RemoteFile?> readProps(String path) async {
    var receivedProperties = false;
    try {
      // Client.readProps calls fixSlashes(), turning database7.db into
      // database7.db/. Strict servers reject that file-as-directory request.
      // Use the same authenticated transport, but preserve the exact path and
      // request only this resource (Depth: 0).
      final response = await _client.c.wdPropfind(
        _client,
        _safeEncodePath(path),
        false,
        '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/>'
        '<d:getcontentlength/><d:getlastmodified/><d:getetag/>'
        '</d:prop></d:propfind>',
      );
      receivedProperties = true;
      final document = XmlDocument.parse(response.data as String);
      final resources = document.findAllElements('response', namespace: 'DAV:');
      if (resources.length != 1) {
        throw const FormatException('WebDAV 未返回有效的单文件元数据');
      }
      final resource = resources.single;
      final resourceStatus =
          resource.getElement('status', namespace: 'DAV:')?.innerText;
      if (resourceStatus != null) {
        if (RegExp(r'\s404(?:\s|$)').hasMatch(resourceStatus)) return null;
        if (!RegExp(r'\s200(?:\s|$)').hasMatch(resourceStatus)) {
          throw const FormatException('WebDAV 资源读取失败，不是空书库');
        }
      }
      final props = resource
          .findElements('propstat', namespace: 'DAV:')
          .where((entry) => RegExp(r'\s200(?:\s|$)').hasMatch(
              entry.getElement('status', namespace: 'DAV:')?.innerText ?? ''))
          .expand((entry) => entry.findElements('prop', namespace: 'DAV:'))
          .toList();
      if (props.isEmpty) throw const FormatException('WebDAV 文件属性读取失败');
      String? value(String name) {
        for (final prop in props) {
          final element = prop.getElement(name, namespace: 'DAV:');
          if (element != null) return element.innerText;
        }
        return null;
      }

      final modified = value('getlastmodified');
      final isDirectory = props.any((prop) =>
          prop.findAllElements('collection', namespace: 'DAV:').isNotEmpty);
      final name = Uri.decodeComponent(
          path.replaceFirst(RegExp(r'/$'), '').split('/').last);
      var eTag = value('getetag')?.trim();
      if (!isDirectory &&
          RegExp(r'^database\d+\.db$').hasMatch(name) &&
          !isStrongETag(eTag)) {
        // PROPFIND's response ETag identifies the XML, not the database.
        // Ask HEAD for THIS file instead; never invent a validator from dates
        // or promote a weak ETag. RowSyncEngine compares metadata before/after
        // downloading and still uses If-Match on the resulting strong tag.
        final head = await _client.c.req(_client, 'HEAD', _safeEncodePath(path),
            optionsHandler: (options) {
          options.followRedirects = false;
          options.validateStatus =
              (status) => status != null && (status < 300 || status >= 400);
          options.headers!['cache-control'] = 'no-cache';
        });
        if (head.statusCode == 200) {
          final candidate = head.headers.value('etag')?.trim();
          if (isStrongETag(candidate)) eTag = candidate;
        } else if (![405, 501].contains(head.statusCode)) {
          throw DioException(
              requestOptions: head.requestOptions,
              response: head,
              type: DioExceptionType.badResponse);
        }
      }
      return RemoteFile(
        path: path,
        name: name,
        isDir: isDirectory,
        size: int.tryParse(value('getcontentlength') ?? ''),
        mTime: modified == null || modified.isEmpty
            ? null
            : io.HttpDate.parse(modified),
        eTag: eTag,
      );
    } on DioException catch (e) {
      // Authentication, network and server failures are not an empty library.
      if (!receivedProperties && e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  static bool isStrongETag(String? value) =>
      value != null && RegExp(r'^"[\x21\x23-\x7E\x80-\xFF]*"$').hasMatch(value);

  @override
  Future<void> uploadFileConditionally(String localPath, String remotePath,
      {String? expectedETag, bool createOnly = false}) async {
    if (!createOnly && !isStrongETag(expectedETag)) {
      throw MissingSyncValidatorException();
    }
    // Replayable bytes preserve the body across a Digest authentication retry.
    final bytes = await io.File(localPath).readAsBytes();
    final response = await _client.c
        .req(_client, 'PUT', _safeEncodePath(remotePath), data: bytes,
            optionsHandler: (options) {
      // Do not forward a conditional database upload (or its credentials) to
      // a different location supplied in a redirect response.
      options.followRedirects = false;
      options.validateStatus =
          (status) => status != null && (status < 300 || status >= 400);
      options.headers!['content-length'] = bytes.length;
      options.headers!['content-type'] = 'application/octet-stream';
      options.headers![createOnly ? 'if-none-match' : 'if-match'] =
          createOnly ? '*' : expectedETag;
    });
    if (![200, 201, 204].contains(response.statusCode)) {
      throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse);
    }
  }

  @override
  Future<void> remove(String path) async {
    await _client.remove(path);
  }

  @override
  Future<void> uploadFile(
    String localPath,
    String remotePath, {
    bool replace = true,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // WebDAV PUT replaces an existing resource. Deleting first would destroy
    // the last cloud database if the subsequent upload fails.
    await _client.writeFromFile(
      localPath,
      _safeEncodePath(remotePath),
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  @override
  Future<void> downloadFile(
    String remotePath,
    String localPath, {
    void Function(int received, int total)? onProgress,
  }) async {
    await _client.read2File(
      _safeEncodePath(remotePath),
      localPath,
      onProgress: onProgress,
    );
  }

  @override
  Future<List<RemoteFile>> safeReadDir(String path) async {
    try {
      return await readDir(path);
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 404) {
        await mkdirAll(path);
        return [];
      }
      rethrow;
    }
  }

  @override
  String get protocolName => 'WebDAV';

  @override
  Map<String, dynamic> get config => Map.from(_config);

  @override
  void updateConfig(Map<String, dynamic> newConfig) {
    _config.addAll(newConfig);
    _initClient();
  }

  @override
  bool get isConfigured {
    return _config.containsKey('url') &&
        _config.containsKey('username') &&
        _config.containsKey('password') &&
        _config['url']?.isNotEmpty == true &&
        _config['username']?.isNotEmpty == true &&
        _config['password']?.isNotEmpty == true;
  }

  String _safeEncodePath(String path) {
    return Uri.encodeComponent(path).replaceAll('%2F', '/');
  }
}
