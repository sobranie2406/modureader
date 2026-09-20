import 'dart:async';
import 'dart:io';

import 'package:anx_reader/service/sync/ai_settings_sync.dart';
import 'package:anx_reader/service/sync/sync_feedback.dart';
import 'package:anx_reader/service/sync/sync_preflight.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const secret = 'private-book-and-api-key';
  DioException httpError(int status) {
    final request = RequestOptions(
      path: 'https://private.example/$secret',
      headers: {'Authorization': secret},
    );
    return DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      message: secret,
      response:
          Response(requestOptions: request, statusCode: status, data: secret),
    );
  }

  test('success is a terminal, concise localized message', () {
    expect(syncSuccessMessage(chinese: true), '同步成功');
    expect(syncSuccessMessage(chinese: false), 'Sync successful');
  });

  for (final entry in {
    401: '账号',
    403: '权限',
    404: '路径',
    408: '超时',
    409: '并发',
    412: '并发',
    423: '锁定',
    429: '频率',
    500: '暂时不可用',
    507: '空间',
    400: '配置',
  }.entries) {
    test('HTTP ${entry.key} has an actionable reason without private data', () {
      final error = httpError(entry.key);
      final message = syncFailureMessage(error, chinese: true);
      expect(message, startsWith('同步失败：'));
      expect(message, contains(entry.value));
      expect(message, contains('HTTP ${entry.key}'));
      for (final chinese in [true, false]) {
        final localized = syncFailureMessage(error, chinese: chinese);
        expect(localized, isNot(contains(secret)));
        expect(localized, isNot(contains('private.example')));
      }
    });
  }

  for (final entry in <Object, String>{
    const SocketException(secret): '网络',
    TimeoutException(secret): '超时',
    const HandshakeException(secret): '证书',
    SyncNetworkUnavailable(): '网络',
    const FileSystemException(secret, secret): '本地文件',
    const FormatException('阅读位置无效', secret): '阅读位置',
    const FormatException('向量索引超过安全同步大小限制', secret): '128 MiB',
    const FormatException('向量索引传输完整性校验失败', secret): '向量索引',
    const FormatException('目录分页异常', secret): '目录列表',
    const FormatException('超过安全限制', secret): '安全限制',
    const FormatException('不支持的数据版本', secret): '不兼容',
    const FormatException(secret, secret): '完整性',
    UnsupportedError(secret): '不支持',
    StateError(secret): '处理同步数据',
    const AiSyncPasswordMissingException(): '加密密码',
    const AiSyncDecryptionException(): '无法解密',
  }.entries) {
    test('${entry.key.runtimeType} maps to ${entry.value} safely', () {
      expect(
          syncFailureMessage(entry.key, chinese: true), contains(entry.value));
      for (final chinese in [true, false]) {
        final message = syncFailureMessage(entry.key, chinese: chinese);
        expect(message, isNot(contains(secret)));
        expect(message, startsWith(chinese ? '同步失败：' : 'Sync failed: '));
      }
    });
  }

  for (final code in SyncFailureCode.values) {
    test('configuration failure $code has a localized reason', () {
      final error = SyncFeedbackFailure(code);
      expect(syncFailureMessage(error, chinese: true), startsWith('同步失败：'));
      expect(syncFailureMessage(error, chinese: false),
          startsWith('Sync failed: '));
    });
  }

  test('automatic probe retries emit only one final failure', () async {
    var attempts = 0;
    final messages = <String>[];
    try {
      await SyncPreflight(delay: (_) async {}).run(
        automatic: true,
        enabled: () => true,
        networkReady: () async => true,
        probe: () async {
          attempts++;
          throw const SocketException(secret);
        },
      );
    } catch (error) {
      messages.add(syncFailureMessage(error, chinese: true));
    }
    expect(attempts, 3);
    expect(messages, hasLength(1));
    expect(messages.single, startsWith('同步失败：'));
  });

  test('a cancelled probe does not become a failure notification', () async {
    var enabled = true;
    final completed = await SyncPreflight(delay: (_) async {
      enabled = false;
    }).run(
      automatic: true,
      enabled: () => enabled,
      networkReady: () async => false,
      probe: () async => fail('must not access network'),
    );
    expect(completed, false);
  });

  test('sync entry points do not display intermediate toast messages', () {
    final provider = File('lib/providers/sync.dart').readAsStringSync();
    final sheet = File('lib/widgets/bookshelf/sync_status_bottom_sheet.dart')
        .readAsStringSync();
    expect(provider, isNot(contains('.webdavSyncing')));
    expect(sheet, isNot(contains('AnxToast.show(l10n.webdavSyncing)')));
    expect(provider, contains('AnxToast.show(syncSuccessMessage('));
    expect(provider, contains('AnxToast.show(syncFailureMessage('));
  });
}
