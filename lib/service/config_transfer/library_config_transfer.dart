import 'package:anx_reader/service/remote_library/webdav_library.dart';

/// Separate from sync WebDAV: importing never enables sync or contacts a host.
class LibraryConfigTransfer {
  const LibraryConfigTransfer._();
  static const kind = 'remote-library-webdav';

  static Map<String, dynamic> createPayload(LibraryConnection connection,
      {bool includePassword = true}) {
    connection.root;
    return {
      'type': kind,
      'url': connection.url.trim(),
      'username': connection.username,
      'allowHttp': connection.allowHttp,
      if (includePassword) 'password': connection.password,
    };
  }

  static LibraryConnection parse(Map<String, dynamic> data) {
    if (data['type'] != kind ||
        data['url'] is! String ||
        (data.containsKey('username') && data['username'] is! String) ||
        (data.containsKey('password') && data['password'] is! String) ||
        (data.containsKey('allowHttp') && data['allowHttp'] is! bool)) {
      throw const FormatException('Invalid remote library configuration');
    }
    final connection = LibraryConnection(
      url: (data['url'] as String).trim(),
      username: (data['username'] as String? ?? '').trim(),
      password: data['password'] as String? ?? '',
      allowHttp: data['allowHttp'] as bool? ?? false,
    );
    connection.root;
    return connection;
  }
}
