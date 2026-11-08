import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:anx_reader/service/remote_library/webdav_library.dart';

/// No Baidu app secret or refresh token is distributed with the client.
class BaiduAuth {
  BaiduAuth({Dio? client, FlutterSecureStorage? storage})
      : client = client ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 20),
                sendTimeout: const Duration(seconds: 15),
                followRedirects: false)),
        storage = storage ??
            const FlutterSecureStorage(
                aOptions: AndroidOptions(encryptedSharedPreferences: true),
                iOptions: IOSOptions(
                    accessibility: KeychainAccessibility.unlocked_this_device));
  static const origin = 'https://baidu-auth.2406.fun';
  static const sessionKey = 'modu.baidu.device-session.v1';
  final Dio client;
  final FlutterSecureStorage storage;
  String? _session, _access;
  DateTime? _expiry;
  Future<String>? _refresh;

  Future<bool> restore() async {
    final stored = await storage.read(key: sessionKey);
    if (stored != _session) {
      _access = null;
      _expiry = null;
    }
    _session = stored;
    return _session != null;
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> data, CancelToken? cancel,
      {String? session}) async {
    try {
      return await boundedJson(client, Uri.parse('$origin$path'), cancel,
          maxBytes: 65536,
          data: data,
          options: Options(method: 'POST', headers: {
            'Content-Type': 'application/json',
            if (session != null) 'Authorization': 'Bearer $session',
          }));
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      final code = error.response?.statusCode;
      throw RemoteLibraryException(
          code == 401
              ? '授权已失效，请重新连接百度网盘。'
              : code == 429 || code == 503
                  ? '授权服务繁忙，请稍后重试。'
                  : '无法连接授权服务，请检查网络后重试。',
          code == 401
              ? 'Authorization expired. Reconnect Baidu Netdisk.'
              : 'Authorization service unavailable. Please retry.');
    }
  }

  static String newProof() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  Future<({String ticket, Uri url})> start(
      String proof, CancelToken cancel) async {
    final data = await _post('/v1/start',
        {'challenge': sha256.convert(utf8.encode(proof)).toString()}, cancel);
    final ticket = data['ticket'] as String;
    final uri = Uri.parse(data['authorize_url'] as String);
    if (uri.scheme != 'https' ||
        uri.host != 'openapi.baidu.com' ||
        uri.path != '/oauth/2.0/authorize' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.queryParametersAll.values.any((values) => values.length != 1) ||
        (uri.hasPort && uri.port != 443) ||
        uri.queryParameters['redirect_uri'] != '$origin/oauth/baidu/callback' ||
        uri.queryParameters['state'] != ticket) {
      throw const FormatException('Invalid authorization URL');
    }
    return (ticket: ticket, url: uri);
  }

  Future<bool> claim(String ticket, String proof, CancelToken cancel) async {
    final data =
        await _post('/v1/claim', {'ticket': ticket, 'proof': proof}, cancel);
    if (data['pending'] == true) return false;
    final session = data['session'] as String;
    if (!RegExp(r'^[A-Za-z0-9_-]{43,128}$').hasMatch(session)) {
      throw const FormatException('Invalid device session');
    }
    final previous = _session;
    _rememberAccess(data);
    try {
      await storage.write(key: sessionKey, value: session);
    } catch (_) {
      _access = null;
      try {
        await _post('/v1/revoke', {}, null, session: session);
      } catch (_) {}
      rethrow;
    }
    _session = session;
    if (previous != null && previous != session) {
      try {
        await _post('/v1/revoke', {}, null, session: previous);
      } catch (_) {
        // A failed old-session revocation expires server-side; keep the new login.
      }
    }
    return true;
  }

  void _rememberAccess(Map<String, dynamic> data) {
    final token = data['access_token'];
    final seconds = data['expires_in'];
    if (token is! String || token.isEmpty || seconds is! int || seconds <= 0) {
      throw const FormatException('Invalid access token response');
    }
    _access = token;
    _expiry = DateTime.now().add(Duration(seconds: seconds));
  }

  Future<String> accessToken() {
    if (_access != null &&
        _expiry!.isAfter(DateTime.now().add(const Duration(minutes: 2)))) {
      return Future.value(_access);
    }
    return _refresh ??= _loadAccess().whenComplete(() => _refresh = null);
  }

  Future<String> _loadAccess() async {
    final session = _session;
    if (session == null) {
      throw const RemoteLibraryException(
          '请先连接百度网盘。', 'Connect Baidu Netdisk first.');
    }
    final data = await _post('/v1/token', {}, null, session: session);
    if (session != _session) throw StateError('Session disconnected');
    _rememberAccess(data);
    return _access!;
  }

  Future<void> disconnect() async {
    // Keep the local session if the server is unreachable, so revocation can retry.
    if (_session != null) {
      await _post('/v1/revoke', {}, null, session: _session);
    }
    await storage.delete(key: sessionKey);
    _session = _access = null;
    _expiry = null;
  }

  void close() => client.close(force: true);
}

Future<Map<String, dynamic>> boundedJson(
    Dio client, Uri uri, CancelToken? cancel,
    {Object? data, Options? options, int maxBytes = 4 * 1024 * 1024}) async {
  final response = await client.requestUri<ResponseBody>(uri,
      data: data,
      options: (options ?? Options()).copyWith(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (s) => s == 200),
      cancelToken: cancel);
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in response.data!.stream) {
    if (bytes.length + chunk.length > maxBytes) {
      throw const FormatException('Response too large');
    }
    bytes.add(chunk);
  }
  final result = jsonDecode(utf8.decode(bytes.takeBytes()));
  if (result is! Map<String, dynamic>) {
    throw const FormatException('Invalid response');
  }
  return result;
}
