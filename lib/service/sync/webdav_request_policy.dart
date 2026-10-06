import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';

bool isJianguoyunWebdav(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !['http', 'https'].contains(uri.scheme)) return false;
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  return host == 'jianguoyun.com' || host.endsWith('.jianguoyun.com');
}

bool isWebdavBusy(Object error) =>
    error is DioException && [429, 503].contains(error.response?.statusCode);

/// One circuit breaker per endpoint/account, shared by sync, downloads and
/// status clients in this process. No request (especially PUT) is replayed.
class WebdavRequestPolicy {
  WebdavRequestPolicy(
      {required this.jianguoyun,
      DateTime Function()? now,
      Future<File> Function()? stateFile,
      this.requestLimit = 480})
      : assert(requestLimit > 0),
        _now = now ?? DateTime.now,
        _stateFile = stateFile;

  static final _accounts = <String, WebdavRequestPolicy>{};
  static WebdavRequestPolicy forAccount(String url, String username,
      {Future<Directory> Function()? stateDirectory}) {
    final uri = Uri.tryParse(url);
    final host = isJianguoyunWebdav(url)
        ? 'jianguoyun.com'
        : uri != null &&
                ['http', 'https'].contains(uri.scheme) &&
                uri.host.isNotEmpty
            ? uri.origin
            : url;
    // Paths and app passwords must not split an account's request gate.
    final account =
        isJianguoyunWebdav(url) ? username.trim().toLowerCase() : username;
    final identity = '$host\n$account';
    final policy = _accounts.putIfAbsent(identity,
        () => WebdavRequestPolicy(jianguoyun: isJianguoyunWebdav(url)));
    if (stateDirectory != null && policy._stateFile == null) {
      policy._stateFile = () async {
        final directory = await stateDirectory();
        final key = sha256.convert(utf8.encode(identity));
        return File('${directory.path}/modu-webdav-policy/$key.json');
      };
      policy._loaded = null;
    }
    return policy;
  }

  final bool jianguoyun;
  final DateTime Function() _now;
  // Conservative device-local budget; other devices still share the server's
  // allowance. Keep headroom below the free-tier 600 requests / 30 minutes.
  final int requestLimit;
  static const requestWindow = Duration(minutes: 30);
  final List<int> _requests = [];
  Future<File> Function()? _stateFile;
  Future<void>? _loaded;
  Future<void> _serial = Future.value();
  DateTime? _lastSync;
  DateTime? _blockedUntil;
  DateTime? _lastBusy;
  int _failures = 0;
  int _status = 503;

  Future<void> prepare() => _loaded ??= _load().catchError((Object error) {
        _loaded = null;
        throw error;
      });

  Future<void> _load() async {
    final resolver = _stateFile;
    if (resolver == null) return;
    final file = await resolver();
    if (!await file.exists()) return;
    try {
      if (await file.length() > 64 * 1024) {
        throw const FormatException('policy size');
      }
      final saved = jsonDecode(await file.readAsString()) as Map;
      if (saved['version'] != 1) throw const FormatException('policy version');
      DateTime? time(String key) {
        final value = saved[key];
        if (value == null) return null;
        if (value is! int || value < 0 || value > 8640000000000000) {
          throw const FormatException('policy time');
        }
        final date = DateTime.fromMillisecondsSinceEpoch(value);
        final maximum = key == 'blockedUntil'
            ? _now().add(const Duration(days: 7))
            : _now();
        return date.isAfter(maximum) ? maximum : date;
      }

      final until = time('blockedUntil');
      if (until != null &&
          (_blockedUntil == null || until.isAfter(_blockedUntil!))) {
        _blockedUntil = until;
      }
      final sync = time('lastSync');
      if (sync != null && (_lastSync == null || sync.isAfter(_lastSync!))) {
        _lastSync = sync;
      }
      _lastBusy = time('lastBusy');
      _failures = (saved['failures'] as int).clamp(0, 6);
      _status = saved['status'] == 429 ? 429 : 503;
      if (jianguoyun) {
        final requests = (saved['requests'] as List).cast<int>();
        if (requests.length > requestLimit) {
          throw const FormatException('policy size');
        }
        if (requests.any((time) => time < 0 || time > 8640000000000000)) {
          throw const FormatException('policy time');
        }
        _requests.addAll(requests.map((time) =>
            time > _now().millisecondsSinceEpoch
                ? _now().millisecondsSinceEpoch
                : time));
        _requests.sort();
        _pruneRequests();
      }
    } on FormatException {
      _quarantineInvalidState();
      await _save();
    } on TypeError {
      _quarantineInvalidState();
      await _save();
    }
  }

  void _quarantineInvalidState() {
    // A damaged local budget must not silently reset the server allowance.
    _requests.clear();
    _blockedUntil =
        _now().add(jianguoyun ? requestWindow : const Duration(minutes: 1));
  }

  void _pruneRequests() {
    final cutoff = _now().subtract(requestWindow).millisecondsSinceEpoch;
    _requests.removeWhere((time) => time <= cutoff);
  }

  Duration get budgetDelay {
    if (!jianguoyun) return Duration.zero;
    _pruneRequests();
    if (_requests.length < requestLimit) return Duration.zero;
    return DateTime.fromMillisecondsSinceEpoch(_requests.first)
        .add(requestWindow)
        .difference(_now());
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _serial.then((_) => action());
    _serial = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _save() async {
    final resolver = _stateFile;
    if (resolver == null) return;
    final file = await resolver();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.pending');
    await temporary.writeAsString(
        jsonEncode({
          'version': 1,
          'lastSync': _lastSync?.millisecondsSinceEpoch,
          'blockedUntil': _blockedUntil?.millisecondsSinceEpoch,
          'lastBusy': _lastBusy?.millisecondsSinceEpoch,
          'failures': _failures,
          'status': _status,
          'requests': _requests,
        }),
        flush: true);
    await temporary.rename(file.path);
  }

  Future<void> persist() => _exclusive(() async {
        await prepare();
        await _save();
      });

  /// Reserve before transport, including auth retries. Concurrent requests
  /// cannot all pass the final remaining slot. Never automatically replay PUT.
  Future<DioException?> beforeRequest(RequestOptions request) =>
      _exclusive(() async {
        await prepare();
        final rejected = rejectWhileCooling(request);
        if (rejected != null) return rejected;
        if (jianguoyun) {
          _requests.add(_now().millisecondsSinceEpoch);
          _requests.sort();
          await _save();
        }
        return null;
      });

  Duration get cooldown {
    final until = _blockedUntil;
    if (until == null || !until.isAfter(_now())) return Duration.zero;
    return until.difference(_now());
  }

  Duration get automaticDelay {
    var delay = const Duration(seconds: 2);
    if (jianguoyun && _lastSync != null) {
      final remaining =
          _lastSync!.add(const Duration(minutes: 10)).difference(_now());
      if (remaining > delay) delay = remaining;
    }
    if (cooldown > delay) delay = cooldown;
    if (budgetDelay > delay) delay = budgetDelay;
    return delay;
  }

  void syncStarted() => _lastSync = _now();

  void observe(Response<dynamic>? response) {
    if (response == null || ![429, 503].contains(response.statusCode)) return;
    final now = _now();
    if (_lastBusy == null ||
        now.difference(_lastBusy!) > const Duration(minutes: 30)) {
      _failures = 0;
    }
    // Concurrent in-flight failures belong to one failed burst.
    if (cooldown == Duration.zero) _failures++;
    _lastBusy = now;
    _status = response.statusCode!;
    final seconds =
        ((jianguoyun ? 300 : 60) * (1 << (_failures - 1).clamp(0, 5)))
            .clamp(0, 1800);
    var until = now.add(Duration(seconds: seconds));
    final value = response.headers.value('retry-after');
    if (value != null) {
      final delta = int.tryParse(value.trim());
      DateTime? serverUntil;
      if (delta != null && delta >= 0) {
        // Bound malformed giant integers before Duration/DateTime arithmetic.
        serverUntil = now.add(Duration(seconds: delta.clamp(0, 7 * 24 * 3600)));
      } else {
        try {
          serverUntil = HttpDate.parse(value);
        } catch (_) {/* Invalid hints use bounded fallback backoff. */}
      }
      if (serverUntil != null && serverUntil.isAfter(until)) {
        until = serverUntil;
      }
    }
    if (_blockedUntil == null || until.isAfter(_blockedUntil!)) {
      _blockedUntil = until;
    }
  }

  DioException? rejectWhileCooling(RequestOptions request) {
    final budget = budgetDelay;
    final budgetLimited = budget > cooldown;
    final remaining = budgetLimited ? budget : cooldown;
    if (remaining == Duration.zero) return null;
    return DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      error: budgetLimited
          ? const WebdavRequestBudgetExceeded()
          : const WebdavCoolingDown(),
      response: Response<dynamic>(
        requestOptions: request,
        statusCode: budgetLimited ? 429 : _status,
        headers: Headers.fromMap({
          'retry-after': ['${(remaining.inMilliseconds / 1000).ceil()}'],
        }),
      ),
    );
  }
}

class WebdavCoolingDown {
  const WebdavCoolingDown();
}

class WebdavRequestBudgetExceeded extends WebdavCoolingDown {
  const WebdavRequestBudgetExceeded();
}
