/// Remote paths relative to the configured WebDAV endpoint.
/// Keep separate from the user-selected WebDAV book-library directory.
abstract final class SyncPaths {
  static const root = 'modu';
  static const books = '$root/data/file';
  static const covers = '$root/data/cover';
  static const connectionTest = '$root/.test';

  static String database(String fileName) => '$root/$fileName';
  static String data(String relativePath) => '$root/data/$relativePath';
}
