import 'dart:convert';

import 'package:modu_reader/service/remote_library/ftp_library.dart';
import 'package:modu_reader/service/remote_library/webdav_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum RemoteLibrarySource {
  webdav('WebDAV'),
  ftp('FTP');

  const RemoteLibrarySource(this.label);
  final String label;
}

class FtpConnection {
  const FtpConnection({
    required this.address,
    this.directory = '',
    this.username = '',
    this.password = '',
  });

  final String address, directory, username, password;

  Uri get root {
    FtpLibrary.validateCredentials(username, password);
    return FtpLibrary.parseRoot(address, directory);
  }
}

class FtpConnectionStore {
  static const key = 'remoteFtpLibraryConnection';

  static Future<FtpConnection?> load() async {
    final raw = (await SharedPreferences.getInstance()).get(key);
    if (raw is! String) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final value = FtpConnection(
        address: map['address'] as String,
        directory: map['directory'] as String? ?? '',
        username: map['username'] as String? ?? '',
        password: map['password'] as String? ?? '',
      );
      value.root;
      return value;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(FtpConnection value) async {
    value.root;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      key,
      jsonEncode({
        'address': value.address.trim(),
        'directory': value.directory.trim(),
        'username': value.username,
        'password': value.password,
      }),
    )) {
      throw StateError('Cannot save FTP connection');
    }
  }

  static Future<void> clear() async {
    if (!await (await SharedPreferences.getInstance()).remove(key)) {
      throw StateError('Cannot clear FTP connection');
    }
  }
}

String ftpLibraryError(Object error, bool zh, {bool listing = false}) {
  if (error is FtpLibraryException) {
    return switch (error.failure) {
      FtpFailure.connection => zh
          ? '无法连接 FTP，请检查地址、端口和网络。'
          : 'Could not connect to FTP. Check the address, port and network.',
      FtpFailure.authentication => zh
          ? 'FTP 登录失败，请检查用户名和密码。'
          : 'FTP login failed. Check the username and password.',
      FtpFailure.notFound => zh
          ? 'FTP 目录或文件不存在，或账号无权读取。'
          : 'The FTP directory or file is unavailable or inaccessible.',
      FtpFailure.invalidResponse => zh
          ? '无法读取 FTP 响应，请检查服务器配置。'
          : 'Could not read the FTP response. Check the server configuration.',
      FtpFailure.server => zh
          ? 'FTP 服务器未完成操作，请稍后重试。'
          : 'The FTP server did not complete the request. Try again later.',
    };
  }
  if (error is LibraryListingException && error.reason == 'invalid') {
    return zh ? '无法解析 FTP 目录清单。' : 'Could not parse the FTP directory listing.';
  }
  return libraryError(error, zh, listing: listing);
}
