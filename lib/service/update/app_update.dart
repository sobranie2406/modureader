import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:anx_reader/utils/app_version.dart';

const moduReleasePage = 'https://github.com/sobranie2406/modureader/releases';
const moduReleaseApi =
    'https://api.github.com/repos/sobranie2406/modureader/releases/latest';
const moduMirrorReleasePage =
    'https://gitee.com/sobranie2406/modureader/releases';
// Published only after the mirrored installers have been verified. A missing
// manifest is normal before mirror deployment and must fall back to GitHub.
const moduMirrorManifest =
    'https://gitee.com/sobranie2406/modureader/raw/master/updates/latest.json';

void _checkCancelled(CancelToken token) {
  if (token.isCancelled) throw token.cancelError!;
}

/// Match the running application ABI, never guess from the OS's marketing name.
String? updateAssetName(String version, String platform, String abi) {
  final arch = abi.endsWith('_arm64')
      ? 'arm64'
      : abi.endsWith('_x64')
          ? 'x64'
          : null;
  if (arch == null) return null;
  final suffix = switch (platform) {
    'android' => '.apk',
    'macos' => '.dmg',
    'windows' => '-setup.exe',
    'linux' => '.deb',
    'ios' when arch == 'arm64' => '.ipa',
    _ => null,
  };
  return suffix == null ? null : 'Modu-$version-$platform-$arch$suffix';
}

bool isNewerRelease(String remote, String installed) {
  final stable = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(remote);
  final local =
      RegExp(r'^(\d+)\.(\d+)\.(\d+)(-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$')
          .firstMatch(installed);
  if (stable == null || local == null) {
    throw const FormatException('Invalid update version');
  }
  for (var i = 1; i <= 3; i++) {
    final comparison = int.parse(stable[i]!).compareTo(int.parse(local[i]!));
    if (comparison != 0) return comparison > 0;
  }
  return local[4] != null;
}

class UpdateAsset {
  const UpdateAsset(this.name, this.url, this.size, this.digest,
      {this.mirrorUrl});
  final String name, url, digest;
  final String? mirrorUrl;
  final int size;
}

class UpdateRelease {
  const UpdateRelease(this.version, this.notes, this.asset,
      {this.fromMirror = false});
  final String version, notes;
  final UpdateAsset? asset;
  final bool fromMirror;
  String get url =>
      '${fromMirror ? moduMirrorReleasePage : moduReleasePage}/tag/v$version';

  factory UpdateRelease.parse(Map<String, dynamic> json,
      {required String platform,
      required String abi,
      bool fromMirror = false}) {
    final tag = json['tag_name'];
    if (json['draft'] != false ||
        json['prerelease'] != false ||
        tag is! String ||
        !RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag)) {
      throw const FormatException('Not a stable Modu release');
    }
    final version = tag.substring(1);
    final expected = updateAssetName(version, platform, abi);
    if (json['assets'] is! List) {
      throw const FormatException('Invalid release assets');
    }
    final matches = (json['assets'] as List)
        .whereType<Map>()
        .where((a) => a['name'] == expected)
        .toList();
    UpdateAsset? asset;
    if (expected != null && matches.length == 1) {
      final a = matches.single;
      final digest = a['digest'];
      final size = a['size'];
      final url = '$moduReleasePage/download/$tag/$expected';
      if (a['state'] == 'uploaded' &&
          a['browser_download_url'] == url &&
          size is int &&
          size > 0 &&
          size <= 2 * 1024 * 1024 * 1024 &&
          digest is String &&
          RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)) {
        asset = UpdateAsset(
            expected, url, size, digest.substring(7).toLowerCase(),
            mirrorUrl: '$moduMirrorReleasePage/download/$tag/$expected');
      }
    }
    return UpdateRelease(
        version, json['body'] is String ? json['body'] as String : '', asset,
        fromMirror: fromMirror);
  }
}

/// Only official HTTPS release endpoints. No user account, library or keys sent.
class UpdateTransport {
  UpdateTransport(
      {Dio? dio,
      this.mirrorCheckTimeout = const Duration(seconds: 8),
      this.githubCheckTimeout = const Duration(seconds: 12)})
      : dio = dio ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
                headers: {
                  'User-Agent': 'Modu-Updater',
                  'Accept': 'application/vnd.github+json'
                }));
  final Dio dio;
  final Duration mirrorCheckTimeout, githubCheckTimeout;

  static bool trustedUrl(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      const {
        'api.github.com',
        'github.com',
        'release-assets.githubusercontent.com',
        'objects.githubusercontent.com',
        'gitee.com',
        'foruda.gitee.com',
      }.contains(uri.host);

  Future<ResponseBody> _get(String url, CancelToken cancel,
      {bool mirror = false}) async {
    var uri = Uri.parse(url);
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (!trustedUrl(uri) ||
          (mirror &&
              !((uri.host == 'gitee.com' &&
                      uri.path.startsWith('/sobranie2406/modureader/')) ||
                  (uri.host == 'foruda.gitee.com' &&
                      uri.path.startsWith('/attach_file/')))) ||
          (!mirror &&
              (uri.host == 'gitee.com' || uri.host == 'foruda.gitee.com'))) {
        throw const FormatException('Untrusted update URL');
      }
      final response = await dio.get<ResponseBody>(uri.toString(),
          cancelToken: cancel,
          options: Options(
              headers: {
                'Accept': mirror
                    ? 'application/json, application/octet-stream'
                    : 'application/vnd.github+json'
              },
              receiveTimeout: mirror ? const Duration(seconds: 15) : null,
              responseType: ResponseType.stream,
              followRedirects: false,
              validateStatus: (s) => s != null && s >= 200 && s < 400));
      final body = response.data!;
      if (response.statusCode == 200) return body;
      await body.stream.listen(null).cancel();
      final location = response.headers.value('location');
      if (location == null) {
        throw const FormatException('Missing update redirect');
      }
      uri = uri.resolve(location);
    }
    throw const FormatException('Too many update redirects');
  }

  Future<UpdateRelease> latest(String platform, String abi) async {
    UpdateRelease? mirrored;
    try {
      mirrored = await _latestFrom(platform, abi, mirror: true);
    } on Exception {
      // Missing, rate-limited, malformed or unreachable mirror: use upstream.
    }
    // Compare upstream when reachable so a lagging mirror cannot hide a release.
    // A healthy mirror remains usable when GitHub is blocked or unavailable.
    try {
      final upstream = await _latestFrom(platform, abi, mirror: false);
      if (mirrored == null ||
          isNewerRelease(upstream.version, mirrored.version) ||
          (upstream.version == mirrored.version &&
              (upstream.asset?.digest != mirrored.asset?.digest ||
                  upstream.asset?.size != mirrored.asset?.size))) {
        return upstream;
      }
    } on Exception {
      if (mirrored == null) rethrow;
    }
    return mirrored;
  }

  Future<UpdateRelease> _latestFrom(String platform, String abi,
      {required bool mirror}) async {
    final cancel = CancelToken();
    final timer = Timer(mirror ? mirrorCheckTimeout : githubCheckTimeout,
        () => cancel.cancel('Update check timed out'));
    try {
      final response = await _get(
          mirror ? moduMirrorManifest : moduReleaseApi, cancel,
          mirror: mirror);
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > 1024 * 1024) {
          cancel.cancel();
          throw const FormatException('Release metadata too large');
        }
        bytes.addAll(chunk);
      }
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, dynamic> ||
          (mirror && json['modu_update_schema'] != 1)) {
        throw const FormatException('Invalid update manifest');
      }
      final release = UpdateRelease.parse(json,
          platform: platform, abi: abi, fromMirror: mirror);
      if (mirror &&
          updateAssetName(release.version, platform, abi) != null &&
          release.asset == null) {
        throw const FormatException('Mirror asset not ready');
      }
      return release;
    } finally {
      timer.cancel();
    }
  }

  Future<File> download(UpdateAsset asset, Directory directory,
      CancelToken cancel, void Function(int, int) progress) async {
    if (asset.name.contains('/') ||
        asset.name.contains('\\') ||
        !asset.name.startsWith('Modu-') ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(asset.digest) ||
        asset.size <= 0 ||
        asset.size > 2 * 1024 * 1024 * 1024) {
      throw const FormatException('Invalid update asset');
    }
    await directory.create(recursive: true);
    final file = File('${directory.path}/${asset.name}');
    final part = File('${file.path}.part');
    _checkCancelled(cancel);
    if (await file.exists()) {
      if (await verify(file, asset)) {
        _checkCancelled(cancel);
        return file;
      }
      await file.delete();
    }
    // Every attempt starts a fresh file and verifies against the SAME digest.
    // Never concatenate a partial mirror response with an upstream response.
    if (asset.mirrorUrl != null) {
      try {
        return await _downloadFrom(
            asset, file, part, asset.mirrorUrl!, cancel, progress,
            mirror: true);
      } on Exception catch (e) {
        _checkCancelled(cancel);
        if (e is FileSystemException) rethrow;
        if (e is! DioException &&
            e is! FormatException &&
            e is! IOException &&
            e is! TimeoutException) {
          rethrow;
        }
        progress(0, asset.size);
      }
    }
    _checkCancelled(cancel);
    return _downloadFrom(asset, file, part, asset.url, cancel, progress,
        mirror: false);
  }

  Future<File> _downloadFrom(UpdateAsset asset, File file, File part,
      String url, CancelToken cancel, void Function(int, int) progress,
      {required bool mirror}) async {
    IOSink? sink;
    try {
      final body = await _get(url, cancel, mirror: mirror);
      sink = part.openWrite();
      var received = 0;
      await for (final chunk
          in body.stream.timeout(const Duration(seconds: 30))) {
        _checkCancelled(cancel);
        received += chunk.length;
        if (received > asset.size) {
          throw const FormatException('Update size mismatch');
        }
        sink.add(chunk);
        // Backpressure bounds memory even on slow disks.
        await sink.flush();
        progress(received, asset.size);
      }
      await sink.close();
      sink = null;
      _checkCancelled(cancel);
      if (received != asset.size || !await verify(part, asset)) {
        throw const FormatException('Update checksum mismatch');
      }
      _checkCancelled(cancel);
      return await part.rename(file.path);
    } finally {
      try {
        await sink?.close();
      } finally {
        if (await part.exists()) await part.delete();
      }
    }
  }

  Future<bool> verify(File file, UpdateAsset asset) async =>
      await file.exists() &&
      await file.length() == asset.size &&
      (await sha256.bind(file.openRead()).first).toString() == asset.digest;
}

enum UpdatePhase {
  idle,
  checking,
  current,
  available,
  downloading,
  ready,
  installing,
  error
}

class AppUpdateController extends ChangeNotifier {
  AppUpdateController(
      {UpdateTransport? transport,
      String? platform,
      String? abi,
      Future<String> Function()? installedVersion,
      Future<Directory> Function()? directory})
      : transport = transport ?? UpdateTransport(),
        platform = platform ?? Platform.operatingSystem,
        abi = abi ?? Abi.current().toString(),
        installedVersion = installedVersion ?? getAppVersion,
        directory = directory ??
            (() async => Directory(
                '${(await getTemporaryDirectory()).path}/modu-updates'));
  static final instance = AppUpdateController();
  final UpdateTransport transport;
  final String platform, abi;
  final Future<String> Function() installedVersion;
  final Future<Directory> Function() directory;
  UpdatePhase phase = UpdatePhase.idle;
  UpdateRelease? release;
  File? downloaded;
  String currentVersion = '', error = '';
  DateTime? checkedAt;
  double progress = 0;
  CancelToken? _cancel;
  bool get busy => {
        UpdatePhase.checking,
        UpdatePhase.downloading,
        UpdatePhase.installing
      }.contains(phase);
  bool get newer =>
      release != null &&
      currentVersion.isNotEmpty &&
      isNewerRelease(release!.version, currentVersion);

  Future<void> check() async {
    if (busy) return;
    phase = UpdatePhase.checking;
    error = '';
    notifyListeners();
    try {
      currentVersion = await installedVersion();
      final latest = await transport.latest(platform, abi);
      if (release?.asset?.digest != latest.asset?.digest) downloaded = null;
      release = latest;
      checkedAt = DateTime.now();
      phase = !newer
          ? UpdatePhase.current
          : downloaded != null
              ? UpdatePhase.ready
              : UpdatePhase.available;
    } catch (e) {
      _fail(e);
    }
    notifyListeners();
  }

  Future<void> download() async {
    if (busy || !newer || release?.asset == null) return;
    phase = UpdatePhase.downloading;
    error = '';
    progress = 0;
    final cancel = _cancel = CancelToken();
    notifyListeners();
    var last = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      downloaded = await transport
          .download(release!.asset!, await directory(), cancel, (done, total) {
        progress = done / total;
        if (DateTime.now().difference(last).inMilliseconds >= 100 ||
            done == total) {
          last = DateTime.now();
          notifyListeners();
        }
      });
      _checkCancelled(cancel);
      phase = UpdatePhase.ready;
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        phase = UpdatePhase.available;
      } else {
        _fail(e);
      }
    } finally {
      _cancel = null;
    }
    notifyListeners();
  }

  void cancelDownload() => _cancel?.cancel();

  /// Recheck integrity immediately before handing executable bytes to the OS.
  Future<void> install(Future<String?> Function(File) open) async {
    if (busy || downloaded == null || release?.asset == null || !newer) return;
    phase = UpdatePhase.installing;
    error = '';
    notifyListeners();
    try {
      if (!await transport.verify(downloaded!, release!.asset!)) {
        downloaded = null;
        throw const FormatException('Installer modified or missing');
      }
      error = await open(downloaded!) ?? '';
      phase =
          UpdatePhase.ready; // Opened is not proof that installation finished.
    } catch (e) {
      _fail(e);
    }
    notifyListeners();
  }

  void _fail(Object e) {
    phase = UpdatePhase.error;
    error = e is FormatException
        ? 'integrity'
        : e is DioException &&
                (e.response?.statusCode == 403 || e.response?.statusCode == 429)
            ? 'rate_limit'
            : e is DioException && e.response?.statusCode == 404
                ? 'not_found'
                : e is FileSystemException
                    ? 'storage'
                    : e is PlatformException || e is ProcessException
                        ? 'installer'
                        : 'network';
  }
}
