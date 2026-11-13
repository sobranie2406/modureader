import 'dart:collection';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:modu_reader/service/tts/media_diagnostic_fields.dart';

/// A current-session, shareable projection of Settings > Advanced > Logs.
/// Free-form messages can include whole books, SQL arguments and credentials:
/// extract diagnostic fields instead of relying on a secret blacklist.
class DetailedRuntimeLog {
  static const maxEntries = 1000;
  static const maxCharacters = 256 * 1024;
  static final _entries = Queue<String>();
  static int _characters = 0;
  static int _discarded = 0;

  static void clear() {
    _entries.clear();
    _characters = 0;
    _discarded = 0;
  }

  static void record(LogRecord record) {
    final entry = format(record);
    _entries.addLast(entry);
    _characters += entry.length;
    while (_entries.length > maxEntries || _characters > maxCharacters) {
      _characters -= _entries.removeFirst().length;
      _discarded++;
    }
  }

  static String preview() => '\nDetailed application log / 详细运行日志（脱敏）\n'
      'Source: Settings > Advanced > Logs; current session only.\n'
      'Only recognized diagnostic fields and code locations are included; '
      'raw messages, SQL, book content, credentials and local/network addresses are omitted.\n'
      '仅保留可识别的诊断字段及代码位置；原始消息和私人内容省略。\n'
      '${_discarded == 0 ? '' : 'Earlier entries omitted / 已省略较早记录: $_discarded\n'}'
      '${_entries.isEmpty ? 'No application log entries captured / 暂无运行日志。' : _entries.join('\n')}';

  static String format(LogRecord record) {
    // Bound work even when an existing caller logs an entire response/document.
    String bounded(String text) =>
        text.length > 16384 ? text.substring(0, 16384) : text;
    final message = bounded(record.message);
    final error = record.error;
    final source =
        '$message\n${error == null || error is StackTrace ? '' : bounded(error.toString())}';
    final details = <String, Object>{
      'time': record.time.toUtc().toIso8601String(),
      'level': record.level.value >= Level.SEVERE.value
          ? 'SEVERE'
          : record.level.value >= Level.WARNING.value
              ? 'WARNING'
              : 'INFO',
    };
    const mediaPrefix = 'TTS media diagnostic: ';
    if (message.startsWith(mediaPrefix)) {
      try {
        details['mediaDiagnostic'] = safeMediaDiagnosticFields(
            jsonDecode(message.substring(mediaPrefix.length)));
      } on FormatException {
        // Malformed diagnostics never fall back to sharing the raw message.
      }
    }
    const operations = {
      'Sync incomplete:': 'sync_failed',
      'Sync metadata:': 'sync_metadata',
      'Sync journal': 'sync_journal',
      'Sync progress': 'sync_progress',
      'WebDAV': 'webdav',
      'S3': 's3',
      'importData:': 'import_data',
      'exportData:': 'export_data',
      'Failed to upload book': 'book_upload_failed',
      'Failed to download book': 'book_download_failed',
      'Failed to restore': 'restore_failed',
      'Database': 'database',
      'OCR': 'ocr',
      'TTS': 'tts',
      'Edge TTS': 'edge_tts',
      'Reader': 'reader',
    };
    for (final operation in operations.entries) {
      if (message.startsWith(operation.key)) {
        details['operation'] = operation.value;
        break;
      }
    }
    const types = [
      'DatabaseException',
      'SqfliteDatabaseException',
      'DioException',
      'FileSystemException',
      'SocketException',
      'HandshakeException',
      'TimeoutException',
      'PlatformException',
      'MissingPluginException',
      'FormatException',
      'StateError',
      'LateInitializationError',
      'RangeError',
      'ArgumentError',
      'UnsupportedError',
      'SyncFeedbackFailure',
      'SyncNetworkUnavailable',
      'AiSyncDecryptionException',
      'AiSyncPasswordMissingException',
    ];
    final foundTypes =
        types.where((type) => RegExp('\\b$type\\b').hasMatch(source)).toList();
    if (foundTypes.isNotEmpty) details['errors'] = foundTypes;
    const reasons = {
      'reason=ocr_model_unavailable': 'ocr_model_unavailable',
      'reason=ocr_invalid_page': 'ocr_invalid_page',
      'reason=ocr_invalid_bounds': 'ocr_invalid_bounds',
      'reason=ocr_invalid_image': 'ocr_invalid_image',
      'reason=ocr_no_text': 'ocr_no_text',
      'reason=ocr_preview_failed': 'ocr_preview_failed',
      'open_failed': 'open_failed',
      'open_failed_error': 'open_failed',
      'missing_table': 'missing_table',
      'no such table': 'missing_table',
      'read_only': 'read_only',
      'readonly database': 'read_only',
      'database is locked': 'locked',
      'database_closed': 'closed',
      'database_closed_error': 'closed',
      'database is closed': 'closed',
      'reason=closed': 'closed',
      'reason=syntax': 'syntax',
      'reason=constraint': 'constraint',
      'reason=unknown': 'unknown',
      'UNIQUE constraint failed': 'constraint',
      'NOT NULL constraint failed': 'constraint',
      'Permission denied': 'permission_denied',
      'No space left on device': 'no_space',
      'Connection refused': 'connection_refused',
      'Connection timed out': 'timeout',
      'channel-error': 'channel_error',
      '备份缺少书籍文件': 'backup_missing_books',
      '同步数据库校验失败': 'database_integrity_failed',
    };
    final foundReasons = reasons.entries
        .where((entry) => source.contains(entry.key))
        .map((entry) => entry.value)
        .toSet()
        .toList();
    if (foundReasons.isNotEmpty) details['reasons'] = foundReasons;
    final http = RegExp(r'\bHTTP(?: status)?[ :=]+([1-5][0-9]{2})\b',
            caseSensitive: false)
        .firstMatch(source);
    if (http != null) details['httpStatus'] = int.parse(http.group(1)!);
    final code =
        RegExp(r'\b(?:code|errno)[ :=]+(-?[0-9]{1,10})\b').firstMatch(source);
    if (code != null) details['errorCode'] = int.parse(code.group(1)!);
    final sqlOperation = RegExp(
            r'\boperation=(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|PRAGMA|BEGIN|COMMIT|ROLLBACK|VACUUM|unknown)\b')
        .firstMatch(source);
    if (sqlOperation != null) {
      details['databaseOperation'] = sqlOperation.group(1)!;
    }
    final stack = record.stackTrace ?? (error is StackTrace ? error : null);
    final frames = RegExp(
            r'(?:^|[\s(])((?:package:(?:modu_reader|anx_reader|flutter|sqflite|sqflite_common|sqflite_common_ffi|dio)/[a-zA-Z0-9_/]+\.dart|dart:[a-zA-Z_][a-zA-Z0-9_/]*)(?::\d+){1,2})(?=[\s)]|$)')
        .allMatches(bounded(stack?.toString() ?? ''))
        .where((match) => match.group(1)!.length <= 200)
        .take(16)
        .map((match) => match.group(1)!)
        .toList();
    if (frames.isNotEmpty) details['frames'] = frames;
    if (details.length == 2) {
      details['message'] = '[private/unrecognized message omitted]';
    }
    return jsonEncode(details);
  }
}
