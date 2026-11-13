import 'dart:convert';

import 'package:modu_reader/service/feedback/detailed_runtime_log.dart';
import 'package:modu_reader/service/feedback/runtime_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  setUp(DetailedRuntimeLog.clear);

  test('keeps database diagnosis and code frames without SQL or private data',
      () {
    final entry = DetailedRuntimeLog.format(LogRecord(
        Level.WARNING,
        'Sync incomplete: DatabaseException, reason=missing_table, code=1, '
            'operation=SELECT, automatic=true; '
            'SELECT * FROM privateBook WHERE title="私密书名"; '
            'args=[PRIVATE_BODY] password=SECRET https://user:pass@private.host/book',
        'Modu',
        null,
        StackTrace.fromString(
            '#0 RowSyncArchive.read (package:modu_reader/service/sync/row_sync_engine.dart:90:10)\n'
            '#1 native (file:///Users/private/book.dart:1:2)')));
    final data = jsonDecode(entry) as Map;
    expect(data['reasons'], ['missing_table']);
    expect(data['errorCode'], 1);
    expect(data['databaseOperation'], 'SELECT');
    expect(data['frames'],
        ['package:modu_reader/service/sync/row_sync_engine.dart:90:10']);
    for (final value in ['私密', 'PRIVATE', 'SECRET', 'private', 'user:pass']) {
      expect(entry, isNot(contains(value)));
    }
  });

  test('keeps HTTP status and exceptions, including stack passed as error', () {
    final data = jsonDecode(DetailedRuntimeLog.format(LogRecord(
        Level.SEVERE,
        'Sync incomplete: DioException, HTTP 403',
        'Modu',
        StackTrace.fromString(
            '#0 request (package:dio/src/dio_mixin.dart:10:2)')))) as Map;
    expect(data['httpStatus'], 403);
    expect(data['errors'], ['DioException']);
    expect(data['frames'], ['package:dio/src/dio_mixin.dart:10:2']);
  });

  test('never shares arbitrary payloads or purported diagnostic field names',
      () {
    for (final text in [
      'Pop successfully ReadingPage: 我的私人书名',
      'username: alice password: abc API Key: sk-secret',
      'message=private novel body\n```\n@everyone',
      r'C:\Users\alice\private.pdf /Users/alice/book.pdf',
      'https://example.test?token=xyz content://private/file',
      'operation=PRIVATE_OPERATION reason=PRIVATE_REASON code=PRIVATE_CODE',
    ]) {
      final data = jsonDecode(DetailedRuntimeLog.format(
          LogRecord(Level.INFO, text, 'Private logger name'))) as Map;
      expect(data.keys, unorderedEquals(['time', 'level', 'message']));
      expect(data['message'], '[private/unrecognized message omitted]');
    }
  });

  test('import failures retain known cause without echoing book names', () {
    final entry = DetailedRuntimeLog.format(LogRecord(Level.INFO,
        'importData: error: FormatException: 备份缺少书籍文件 我的书', 'Modu'));
    expect(entry, contains('import_data'));
    expect(entry, contains('backup_missing_books'));
    expect(entry, isNot(contains('我的书')));
  });

  test('bounded session buffer declares omissions and resets on app start', () {
    for (var i = 0; i < DetailedRuntimeLog.maxEntries + 5; i++) {
      DetailedRuntimeLog.record(LogRecord(
          Level.WARNING, 'Sync incomplete: DioException, HTTP 429', 'Modu'));
    }
    expect('"level"'.allMatches(DetailedRuntimeLog.preview()).length, 1000);
    expect(DetailedRuntimeLog.preview(), contains('已省略较早记录: 5'));
    expect(RuntimeDiagnostics.preview(), contains('httpStatus'));
    RuntimeDiagnostics.start('1.2.11');
    expect(RuntimeDiagnostics.preview(), isNot(contains('httpStatus')));
    expect(RuntimeDiagnostics.preview(), contains('暂无运行日志'));
  });

  test('large stacks stay within aggregate budget and clear works', () {
    final frames = List.generate(16,
            (i) => '#$i action (package:modu_reader/${'a' * 150}.dart:123:456)')
        .join('\n');
    for (var i = 0; i < 300; i++) {
      DetailedRuntimeLog.record(LogRecord(Level.SEVERE, 'FormatException',
          'Modu', null, StackTrace.fromString(frames)));
    }
    expect(DetailedRuntimeLog.preview().length,
        lessThan(DetailedRuntimeLog.maxCharacters + 2000));
    expect(DetailedRuntimeLog.preview(), contains('已省略较早记录'));
    DetailedRuntimeLog.clear();
    expect(DetailedRuntimeLog.preview(), isNot(contains('FormatException')));
  });
}
