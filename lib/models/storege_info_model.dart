import 'dart:math';

class StorageInfoModel {
  late int databaseSize;
  late int booksSize;
  late int fontSize;
  late int cacheSize;
  late int logSize;
  late int coverSize;
  final int modelSize;
  final int indexSize;
  final int aiHistorySize;
  final int backgroundSize;

  StorageInfoModel({
    required this.databaseSize,
    required this.booksSize,
    required this.fontSize,
    required this.cacheSize,
    required this.logSize,
    required this.coverSize,
    this.modelSize = 0,
    this.indexSize = 0,
    this.aiHistorySize = 0,
    this.backgroundSize = 0,
  });

  String get databaseSizeStr => formatSize(databaseSize);
  String get booksSizeStr => formatSize(booksSize);
  String get fontSizeStr => formatSize(fontSize);
  String get cacheSizeStr => formatSize(cacheSize);
  String get logSizeStr => formatSize(logSize);
  String get coverSizeStr => formatSize(coverSize);

  String get totalSizeStr => formatSize(databaseSize +
      booksSize +
      fontSize +
      cacheSize +
      logSize +
      coverSize +
      modelSize +
      indexSize +
      aiHistorySize +
      backgroundSize);
  String get dataFilesSizeStr => formatSize(booksSize + fontSize + coverSize);

  String formatSize(int bytes) {
    if (bytes <= 0) return '0 B';

    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }
}
