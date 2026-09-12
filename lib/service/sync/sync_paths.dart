/// Remote paths relative to the configured WebDAV endpoint.
/// Keep separate from the user-selected WebDAV book-library directory.
abstract final class SyncPaths {
  static const root = 'modu';
  static const books = '$root/data/file';
  static const covers = '$root/data/cover';
  static const connectionTest = '$root/.test';
  static const recordLog = '$root/record-log-v1';

  static String database(String fileName) => '$root/$fileName';
  static String data(String relativePath) {
    final parts = relativePath.split('/');
    if (parts.length < 2 ||
        !const ['file', 'cover'].contains(parts.first) ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..') ||
        relativePath.contains('\\')) {
      throw ArgumentError('WebDAV 仅同步书籍和封面文件，不同步字体等本机资源。');
    }
    return '$root/data/$relativePath';
  }
}
