import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';
import 'package:anx_reader/models/remote_file.dart';
import 'sync_client_base.dart';
import 's3_config.dart';
import 's3_signer.dart';

/// Native HTTP transport, no WebView/CORS workarounds and no bundled cloud SDK.
/// Architecture reference: ReadAny's s3-backend.ts / s3-paths.ts (GPL-3.0+).
/// Listings fail closed: errors or incomplete pagination NEVER mean an empty
/// library. Unlike WebDAV, directories are virtual prefixes, not MKCOL objects.
class S3SyncClient extends SyncClientBase {
  S3SyncClient(Map<String, dynamic> config,
      {Dio? dio, DateTime Function()? now})
      : _settings = S3Config(config),
        _dio = dio ?? Dio(),
        _now = now ?? DateTime.now {
    _dio.options.connectTimeout = const Duration(seconds: 12);
  }
  S3Config _settings;
  final Dio _dio;
  final DateTime Function() _now;
  DateTime? _coolUntil;
  static const maxObjectBytes = 5 * 1024 * 1024 * 1024;
  static const maxListingBytes = 8 * 1024 * 1024;

  @override
  String get protocolName => 'S3';
  @override
  Map<String, dynamic> get config => Map.of(_settings.values);
  @override
  List<Object?> get syncIdentity => _settings.identity;
  @override
  bool get isConfigured => _settings.configured;
  @override
  void updateConfig(Map<String, dynamic> newConfig) {
    _settings = S3Config(newConfig);
    _coolUntil = null;
  }

  // Keep immutable content-addressed sync batches. A provider calling itself
  // S3-compatible is not proof of reliable If-Match PUT support. Never plain-PUT
  // the shared database8.db. The existing engine verifies every published batch.
  @override
  Future<bool> supportsAtomicSyncWrites() async => false;

  Future<Response<ResponseBody>> _request(
    String method,
    String? key, {
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
    File? source,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
  }) async {
    final settings =
        _settings; // Freeze config for the duration of this request.
    if (!settings.configured)
      throw const FormatException('S3 credentials are required');
    final safeRequest = RequestOptions(path: '', method: method);
    if (_coolUntil != null && _now().isBefore(_coolUntil!)) {
      throw DioException(
          requestOptions: safeRequest,
          type: DioExceptionType.badResponse,
          response: Response(
              requestOptions: safeRequest,
              statusCode: 503,
              headers: Headers.fromMap({
                'retry-after': [
                  '${_coolUntil!.difference(_now()).inSeconds + 1}'
                ]
              })));
    }
    final uri = s3Uri(settings, key, query);
    final length = source == null ? 0 : await source.length();
    if (length > maxObjectBytes)
      throw const FormatException('S3 single upload exceeds 5 GiB');
    final payloadHash = source == null
        ? sha256.convert(const []).toString()
        : (await sha256.bind(source.openRead()).first).toString();
    final signed = signS3Request(
        config: settings,
        method: method,
        uri: uri,
        key: key,
        payloadHash: payloadHash,
        now: _now(),
        headers: {
          ...headers,
          if (source != null) 'content-length': '$length',
          if (source != null) 'content-type': 'application/octet-stream',
          if (source != null && settings.signature == 'v2')
            'content-md5':
                base64Encode((await md5.bind(source.openRead()).first).bytes),
        });
    try {
      final response = await _dio.requestUri<ResponseBody>(uri,
          data: source?.openRead(),
          cancelToken: cancelToken,
          onSendProgress: onSendProgress,
          options: Options(
              method: method,
              headers: signed,
              responseType: ResponseType.stream,
              followRedirects: false,
              sendTimeout: const Duration(minutes: 10),
              receiveTimeout: const Duration(seconds: 60),
              validateStatus: (s) => s != null && s >= 200 && s < 300));
      return response;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final retry = e.response?.headers.value('retry-after');
      if (status == 429 || status == 503) {
        final seconds = int.tryParse(retry ?? '');
        DateTime? date;
        try {
          date = retry == null ? null : HttpDate.parse(retry);
        } catch (_) {}
        final delay = seconds ?? date?.difference(_now()).inSeconds ?? 60;
        _coolUntil = _now().add(Duration(seconds: delay.clamp(1, 86400)));
      }
      // Dispose the failed stream, but never expose signed headers, object keys
      // or XML server bodies through existing exception/logging code.
      final data = e.response?.data;
      if (data is ResponseBody) await data.stream.listen(null).cancel();
      throw DioException(
          requestOptions: safeRequest,
          type: e.type,
          response: status == null
              ? null
              : Response(
                  requestOptions: safeRequest,
                  statusCode: status,
                  headers: Headers.fromMap({
                    if (retry != null) 'retry-after': [retry]
                  })),
          message:
              'S3 request failed; check endpoint, region, signature and permissions');
    }
  }

  Future<String> _text(Response<ResponseBody> response) async {
    final bytes = <int>[];
    await for (final part in response.data!.stream) {
      if (bytes.length + part.length > maxListingBytes) {
        throw const FormatException('S3 listing exceeds safety limit');
      }
      bytes.addAll(part);
    }
    return utf8.decode(bytes);
  }

  @override
  Future<void> ping() async {
    await _list('modu', probe: true);
  }

  @override
  Future<void> mkdirAll(String path) async {
    _settings.key(path);
  }

  @override
  Future<List<RemoteFile>> safeReadDir(String path) => readDir(path);
  @override
  Future<List<RemoteFile>> readDir(String path) async => (await _list(path)).files;

  Future<({List<RemoteFile> files, bool exists})> _list(String path,
      {bool probe = false}) async {
    final raw = _settings.key(path);
    final prefix = raw.endsWith('/') ? raw : '$raw/';
    final seenTokens = <String>{};
    final result = <String, RemoteFile>{};
    var hasMarker = false;
    String? token;
    for (var page = 0; page < 10000; page++) {
      final v2 = _settings.listVersion == 'v2';
      final response = await _request('GET', null, query: {
        if (v2) 'list-type': '2',
        'prefix': prefix,
        'delimiter': '/',
        if (_settings.useEncodedListingNames) 'encoding-type': 'url',
        'max-keys': probe ? '1' : '1000',
        if (token != null) (v2 ? 'continuation-token' : 'marker'): token,
      });
      final document = XmlDocument.parse(await _text(response)).rootElement;
      String? value(XmlElement element, String name) => element.childElements
          .where((e) => e.name.local == name)
          .firstOrNull
          ?.innerText;
      if (document.name.local != 'ListBucketResult' ||
          !['true', 'false'].contains(value(document, 'IsTruncated'))) {
        throw const FormatException('Invalid or incomplete S3 listing');
      }
      final encoded = value(document, 'EncodingType') == 'url';
      String decode(String? text) {
        if (text == null) throw const FormatException('Missing S3 object name');
        return encoded ? Uri.decodeComponent(text) : text;
      }

      if (decode(value(document, 'Prefix')) != prefix) {
        throw const FormatException('S3 server returned an unexpected prefix');
      }
      for (final item in document.childElements) {
        final directory = item.name.local == 'CommonPrefixes';
        if (!directory && item.name.local != 'Contents') continue;
        final key = decode(value(item, directory ? 'Prefix' : 'Key'));
        if (key == prefix) {
          // A marker proves that the directory exists; it is not a child.
          // RainYun may return only this object for max-keys=1 with
          // IsTruncated=false, even when the directory has real children.
          final size = int.tryParse(value(item, 'Size') ?? '');
          if (directory || size == null || size < 0) {
            throw const FormatException('Invalid S3 directory marker');
          }
          hasMarker = true;
          continue;
        }
        if (!key.startsWith(prefix))
          throw const FormatException('S3 object outside requested prefix');
        var name = key.substring(prefix.length);
        if (directory && name.endsWith('/'))
          name = name.substring(0, name.length - 1);
        if (name.isEmpty || name.contains('/'))
          throw const FormatException('Invalid S3 directory entry');
        final size = directory ? 0 : int.tryParse(value(item, 'Size') ?? '');
        if (size == null || size < 0)
          throw const FormatException('Invalid S3 object size');
        final logical = _settings.logicalPath(key);
        final file = RemoteFile(
            path: logical,
            name: name,
            isDir: directory,
            size: size,
            eTag: value(item, 'ETag'),
            mTime: DateTime.tryParse(value(item, 'LastModified') ?? ''));
        if (result.containsKey(logical))
          throw const FormatException('Repeated S3 listing entry');
        result[logical] = file;
      }
      final exists = hasMarker || result.isNotEmpty;
      if ((probe && exists) || value(document, 'IsTruncated') == 'false') {
        return (files: result.values.toList(), exists: exists);
      }
      token = v2
          ? value(document, 'NextContinuationToken')
          : decode(value(document, 'NextMarker'));
      if (token == null || token.isEmpty || !seenTokens.add(token)) {
        throw const FormatException(
            'S3 listing truncated without a new page token');
      }
    }
    throw const FormatException('S3 listing page limit exceeded');
  }

  @override
  Future<RemoteFile?> readProps(String path) async {
    if (path.endsWith('/') || path == 'modu') {
      final listing = await _list(path, probe: true);
      return !listing.exists
          ? null
          : RemoteFile(path: path, name: path.split('/').last, isDir: true);
    }
    try {
      final response = await _request('HEAD', _settings.key(path));
      await response.data?.stream.listen(null).cancel();
      return RemoteFile(
          path: path,
          name: path.split('/').last,
          isDir: false,
          size: int.tryParse(response.headers.value('content-length') ?? ''),
          eTag: response.headers.value('etag'));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // Engines ask for logical directories without a trailing slash too.
        // HEAD only tests an exact object; an S3 prefix need not have a marker.
        final listing = await _list(path, probe: true);
        return !listing.exists
            ? null
            : RemoteFile(path: path, name: path.split('/').last, isDir: true);
      }
      rethrow;
    }
  }

  @override
  Future<bool> isExist(String path) async => await readProps(path) != null;
  @override
  Future<void> remove(String path) async {
    if (path == 'modu' || path.endsWith('/')) {
      throw const FormatException('Recursive S3 deletion is not supported');
    }
    final response = await _request('DELETE', _settings.key(path));
    await response.data?.stream.listen(null).cancel();
  }

  @override
  Future<void> uploadFile(
    String localPath,
    String remotePath, {
    bool replace = true,
    void Function(int, int)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final response = await _request('PUT', _settings.key(remotePath),
        source: File(localPath),
        headers: {if (!replace) 'if-none-match': '*'},
        cancelToken: cancelToken,
        onSendProgress: onProgress);
    await response.data?.stream.listen(null).cancel();
  }

  @override
  Future<void> downloadFile(
    String remotePath,
    String localPath, {
    void Function(int, int)? onProgress,
  }) async {
    final target = File(localPath);
    await target.parent.create(recursive: true);
    final work = await target.parent.createTemp('.modu-s3-download-');
    final temp = File('${work.path}/incoming');
    IOSink? sink;
    try {
      final response = await _request('GET', _settings.key(remotePath));
      final total =
          int.tryParse(response.headers.value('content-length') ?? '') ?? -1;
      var received = 0;
      sink = temp.openWrite();
      // addStream propagates both file-system and network errors.
      await sink.addStream(response.data!.stream.map((bytes) {
        received += bytes.length;
        if (received > maxObjectBytes)
          throw const FormatException('S3 object too large');
        onProgress?.call(received, total);
        return bytes;
      }));
      await sink.flush();
      await sink.close();
      sink = null;
      if (total >= 0 && received != total)
        throw const FormatException('Incomplete S3 download');
      await temp.rename(target.path);
    } finally {
      await sink?.close();
      if (await work.exists()) await work.delete(recursive: true);
    }
  }

  @override
  Future<void> testFullCapabilities() async {
    await ping();
    final work = await Directory.systemTemp.createTemp('modu-s3-probe-');
    final remote = 'modu/.test/${const Uuid().v4()}.txt';
    var attempted = false;
    try {
      final original = File('${work.path}/source');
      final content = 'Modu S3 probe ${const Uuid().v4()}';
      await original.writeAsString(content, flush: true);
      attempted = true;
      await uploadFile(original.path, remote);
      await downloadFile(remote, '${work.path}/result');
      if (await File('${work.path}/result').readAsString() != content) {
        throw const FormatException('S3 probe integrity check failed');
      }
      await remove(remote);
      attempted = false;
      if (await isExist(remote))
        throw const FormatException('S3 probe deletion failed');
    } finally {
      if (attempted) {
        try {
          await remove(remote);
        } catch (_) {}
      }
      await work.delete(recursive: true);
    }
  }
}
