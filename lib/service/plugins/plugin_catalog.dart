import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/plugin_trust.dart';
import 'package:modu_reader/service/plugins/plugin_catalog_signature.dart';
import 'package:modu_reader/utils/get_path/get_cache_dir.dart';
import 'package:pub_semver/pub_semver.dart';

class PluginCatalogFailure implements Exception {
  const PluginCatalogFailure(this.code);
  final String code;
  @override
  String toString() => 'PluginCatalogFailure($code)';
}

class PluginCatalogEntry {
  const PluginCatalogEntry._({
    required this.id,
    required this.version,
    required this.name,
    required this.description,
    required this.minAppVersion,
    required this.packagePath,
    required this.sha256,
    required this.files,
    required this.hostApi,
    required this.capabilities,
    required this.supported,
  });
  final String id, version, minAppVersion, packagePath, sha256;
  final PluginText name, description;
  final Map<String, String> files;
  final int hostApi;
  final Set<String> capabilities;
  final bool supported;

  bool requiresAppUpdate(String appVersion) {
    if (!supported) return true;
    try {
      return Version.parse(appVersion.split('+').first) <
          Version.parse(minAppVersion);
    } on FormatException {
      return true;
    }
  }
}

class PluginCatalogDownload {
  PluginCatalogDownload(this.file, this._cleanup);
  final File file;
  final Future<void> Function() _cleanup;
  Future<void> dispose() => _cleanup();
}

class PluginCatalog {
  PluginCatalog(
      {http.Client Function()? clientFactory,
      Future<Directory> Function()? cacheDirectory,
      PluginCatalogSignature? signatureVerifier,
      String sourceId = 'github',
      this.timeout = const Duration(seconds: 20)})
      : _clientFactory = clientFactory ?? http.Client.new,
        _cacheDirectory = cacheDirectory ?? getAnxCacheDir,
        _signatureVerifier = signatureVerifier ?? PluginCatalogSignature(),
        _sourceId = _validatedSource(sourceId);

  static const sources = {
    'github':
        'https://raw.githubusercontent.com/sobranie2406/modu-plugin/main/',
    'gitee': 'https://gitee.com/sobranie2406/modu-plugin/raw/main/',
  };
  static const source =
      'https://raw.githubusercontent.com/sobranie2406/modu-plugin/main/';
  static const maxCatalogBytes = 256 * 1024;
  final http.Client Function() _clientFactory;
  final Future<Directory> Function() _cacheDirectory;
  final PluginCatalogSignature _signatureVerifier;
  final Duration timeout;
  final _clients = <http.Client>{};
  final _temporary = <Directory>{};
  int _generation = 0;
  bool _disposed = false;
  Completer<void> _cancelled = Completer<void>();
  String? _signedCatalog;
  List<PluginCatalogEntry> _verifiedEntries = const [];
  String _sourceId;
  String get sourceId => _sourceId;
  String get _baseUrl => sources[_sourceId]!;

  String get signedCatalog =>
      _signedCatalog ?? (throw const PluginCatalogFailure('catalog'));

  Future<List<PluginCatalogEntry>> load() async {
    final generation = _generation;
    final bytes = await _readFile('catalog.json', maxCatalogBytes);
    try {
      final signed = utf8.decode(bytes);
      final decoded = await _signatureVerifier.decode(signed);
      final entries = parse(jsonEncode(decoded));
      _check(generation);
      _signedCatalog = signed;
      _verifiedEntries = entries;
      return entries;
    } on PluginCatalogFailure {
      rethrow;
    } catch (_) {
      throw const PluginCatalogFailure('catalog');
    }
  }

  // Structural parsing does not grant download authority; only load verifies it.
  static List<PluginCatalogEntry> parse(String sourceText) {
    try {
      if (utf8.encode(sourceText).length > maxCatalogBytes) {
        throw const FormatException();
      }
      final raw = jsonDecode(sourceText);
      if (raw is! Map ||
          raw['schemaVersion'] != 1 ||
          raw['repository'] != PluginTrust.projectSource ||
          raw['plugins'] is! List ||
          (raw['plugins'] as List).length > 100) {
        throw const FormatException();
      }
      final result = <PluginCatalogEntry>[];
      final seen = <String>{};
      for (final item in raw['plugins'] as List) {
        if (item is! Map) throw const FormatException();
        if (item['status'] != 'reviewed') continue;
        final id = item['id'],
            version = item['version'],
            minVersion = item['minAppVersion'];
        if (id is! String ||
            !pluginIdPattern.hasMatch(id) ||
            version is! String ||
            !_version.hasMatch(version) ||
            minVersion is! String ||
            !_version.hasMatch(minVersion) ||
            !seen.add('$id@$version')) {
          throw const FormatException();
        }
        Version.parse(version);
        Version.parse(minVersion);
        final hostApi = item['hostApi'], rawCapabilities = item['capabilities'];
        if (hostApi is! int ||
            hostApi < 1 ||
            rawCapabilities is! List ||
            rawCapabilities.length > 20) {
          throw const FormatException();
        }
        final capabilities = <String>{};
        for (final capability in rawCapabilities) {
          if (capability is! String ||
              !_capability.hasMatch(capability) ||
              !capabilities.add(capability)) {
            throw const FormatException();
          }
        }
        final artifact = item['package'],
            rawFiles = item['files'],
            review = item['review'];
        if (artifact is! Map ||
            artifact['path'] != 'dist/$id-$version.moduplugin' ||
            artifact['sha256'] is! String ||
            !_digest.hasMatch(artifact['sha256'] as String) ||
            rawFiles is! Map ||
            rawFiles.isEmpty ||
            rawFiles.length > PluginLimits.maxEntries ||
            review is! Map ||
            review['reviewer'] is! String ||
            (review['reviewer'] as String).isEmpty ||
            review['kind'] is! String ||
            review['reviewedAt'] is! String ||
            DateTime.tryParse(review['reviewedAt'] as String) == null) {
          throw const FormatException();
        }
        final files = <String, String>{};
        for (final file in rawFiles.entries) {
          if (file.key is! String ||
              !_safePath(file.key as String) ||
              file.value is! String ||
              !_digest.hasMatch(file.value as String)) {
            throw const FormatException();
          }
          files[file.key as String] = file.value as String;
        }
        if (!files.containsKey('manifest.json')) throw const FormatException();
        final approved = PluginTrust.approved['$id@$version'];
        if (approved != null &&
            (approved.length != files.length ||
                approved.entries
                    .any((entry) => files[entry.key] != entry.value))) {
          throw const FormatException();
        }
        result.add(PluginCatalogEntry._(
          id: id,
          version: version,
          name: PluginText.parse(item['name'],
              field: 'name', maxLength: PluginLimits.maxDisplayNameLength),
          description: item['description'] == null
              ? const PluginText({})
              : PluginText.parse(item['description'], field: 'description'),
          minAppVersion: minVersion,
          packagePath: artifact['path'] as String,
          sha256: artifact['sha256'] as String,
          files: Map.unmodifiable(files),
          hostApi: hostApi,
          capabilities: Set.unmodifiable(capabilities),
          supported: hostApi == PluginManifest.supportedHostApi &&
              capabilities.every(kP1SupportedCapabilities.contains),
        ));
      }
      return List.unmodifiable(result);
    } catch (_) {
      throw const PluginCatalogFailure('catalog');
    }
  }

  Future<PluginCatalogDownload> download(PluginCatalogEntry entry) async {
    if (!entry.supported || !_verifiedEntries.contains(entry)) {
      throw const PluginCatalogFailure('unapproved');
    }
    final generation = _generation;
    final bytes =
        await _readFile(entry.packagePath, PluginLimits.maxPackageBytes);
    _check(generation);
    if (sha256.convert(bytes).toString() != entry.sha256) {
      throw const PluginCatalogFailure('checksum');
    }
    Directory? directory;
    try {
      directory =
          await (await _cacheDirectory()).createTemp('modu-plugin-download-');
      _temporary.add(directory);
      _check(generation);
      final file = File('${directory.path}/package.moduplugin');
      await file.writeAsBytes(bytes, flush: true);
      _check(generation);
      final saved = directory;
      return PluginCatalogDownload(file, () => _remove(saved));
    } catch (_) {
      if (directory != null) await _remove(directory);
      rethrow;
    }
  }

  Future<Uint8List> _readFile(String path, int maxBytes) async {
    final generation = _generation;
    final elapsed = Stopwatch()..start();
    Duration remaining() {
      final value = timeout - elapsed.elapsed;
      if (value <= Duration.zero) throw const PluginCatalogFailure('network');
      return value;
    }

    try {
      return await _read(Uri.parse('$_baseUrl$path'), maxBytes,
          budget: remaining());
    } on PluginCatalogFailure catch (error) {
      if (error.code != 'network' || _sourceId != 'gitee') rethrow;
      _check(generation);
      final uri = Uri.https(
          'gitee.com',
          '/api/v5/repos/sobranie2406/modu-plugin/contents/$path',
          {'ref': 'main'});
      final encodedLimit = ((maxBytes + 2) ~/ 3) * 4;
      final wrapper =
          await _read(uri, encodedLimit + 64 * 1024, budget: remaining());
      _check(generation);
      try {
        final value = jsonDecode(utf8.decode(wrapper));
        if (value is! Map ||
            value['path'] != path ||
            value['encoding'] != 'base64' ||
            value['size'] is! int ||
            (value['size'] as int) < 0 ||
            value['content'] is! String) {
          throw const FormatException();
        }
        if ((value['size'] as int) > maxBytes) {
          throw const PluginCatalogFailure('size');
        }
        final content =
            (value['content'] as String).replaceAll(RegExp(r'[\r\n]'), '');
        if (content.length > encodedLimit) {
          throw const PluginCatalogFailure('size');
        }
        final bytes = base64Decode(content);
        if (bytes.length > maxBytes) throw const PluginCatalogFailure('size');
        if (bytes.length != value['size'] || base64Encode(bytes) != content) {
          throw const FormatException();
        }
        return bytes;
      } on PluginCatalogFailure {
        rethrow;
      } catch (_) {
        throw const PluginCatalogFailure('catalog');
      }
    }
  }

  Future<Uint8List> _read(Uri uri, int maxBytes,
      {required Duration budget}) async {
    final generation = _generation;
    _check(generation);
    final client = _clientFactory();
    _clients.add(client);
    try {
      final operation = (() async {
        final request = http.Request('GET', uri)..followRedirects = false;
        var response = await client.send(request);
        _check(generation);
        if (response.statusCode == 302 &&
            uri.toString().startsWith(sources['gitee']!)) {
          final redirected = _giteeRedirect(uri, response.headers['location']);
          if (redirected == null) throw const PluginCatalogFailure('network');
          await response.stream.listen((_) {}).cancel();
          _check(generation);
          response = await client
              .send(http.Request('GET', redirected)..followRedirects = false);
          _check(generation);
        }
        if (response.statusCode != 200) {
          throw const PluginCatalogFailure('network');
        }
        if ((response.contentLength ?? 0) > maxBytes) {
          throw const PluginCatalogFailure('size');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          _check(generation);
          if (chunk.length > maxBytes - bytes.length) {
            throw const PluginCatalogFailure('size');
          }
          bytes.add(chunk);
        }
        _check(generation);
        return bytes.takeBytes();
      })()
          .timeout(budget);
      return await Future.any([
        operation,
        _cancelled.future.then<Uint8List>(
            (_) => throw const PluginCatalogFailure('cancelled')),
      ]);
    } on PluginCatalogFailure {
      rethrow;
    } catch (_) {
      _check(generation);
      throw const PluginCatalogFailure('network');
    } finally {
      _clients.remove(client);
      client.close();
    }
  }

  void _check(int generation) {
    if (_disposed || generation != _generation) {
      throw const PluginCatalogFailure('cancelled');
    }
  }

  Future<void> _remove(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
      _temporary.remove(directory);
    } on FileSystemException {
      // A preview can briefly hold the file on Windows; its finally retries.
    }
  }

  Future<void> cancel() async {
    _generation++;
    _cancelled.complete();
    _cancelled = Completer<void>();
    for (final client in _clients.toList()) {
      client.close();
    }
    await Future.wait(_temporary.toList().map(_remove));
  }

  Future<void> changeSource(String value) {
    final next = _validatedSource(value);
    if (_disposed) throw const PluginCatalogFailure('cancelled');
    if (next == _sourceId) return Future.value();
    final cleanup = cancel();
    _sourceId = next;
    _signedCatalog = null;
    _verifiedEntries = const [];
    return cleanup;
  }

  Future<void> dispose() async {
    _disposed = true;
    await cancel();
  }

  static final _version = RegExp(r'^\d+\.\d+\.\d+$');
  static final _digest = RegExp(r'^[a-f0-9]{64}$');
  static Uri? _giteeRedirect(Uri origin, String? location) {
    try {
      if (location == null || location.length > 8192) return null;
      final target = Uri.parse(location);
      final query = target.queryParametersAll;
      final signature = query['signature'];
      if (target.scheme != 'https' ||
          target.host != 'raw.giteeusercontent.com' ||
          target.port != 443 ||
          target.userInfo.isNotEmpty ||
          target.hasFragment ||
          target.path != origin.path ||
          query.length != 1 ||
          signature == null ||
          signature.length != 1 ||
          signature.single.isEmpty ||
          signature.single.length > 4096 ||
          signature.single.runes.any((rune) => rune <= 0x20 || rune == 0x7f)) {
        return null;
      }
      return target;
    } on FormatException {
      return null;
    }
  }

  static String _validatedSource(String value) {
    if (!sources.containsKey(value)) {
      throw ArgumentError.value(value, 'sourceId');
    }
    return value;
  }

  static final _capability = RegExp(r'^[a-z][a-z0-9-]*:[a-z][a-z0-9-]*$');
  static bool _safePath(String path) =>
      path.length <= 256 &&
      RegExp(r'^[A-Za-z0-9_./-]+$').hasMatch(path) &&
      !path.startsWith('/') &&
      !path
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..');
}
