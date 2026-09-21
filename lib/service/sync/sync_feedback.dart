import 'dart:io';
import 'package:dio/dio.dart';
import 'package:anx_reader/service/sync/ai_settings_sync.dart';
import 'package:anx_reader/service/sync/sync_preflight.dart';

enum SyncFailureCode {
  disabled,
  notConfigured,
  wifiRequired,
  encryptionFailed,
  newerDatabase
}

class SyncFeedbackFailure implements Exception {
  const SyncFeedbackFailure(this.code);
  final SyncFailureCode code;
}

String syncSuccessMessage({required bool chinese}) =>
    chinese ? '同步成功' : 'Sync successful';

/// Never put raw exceptions, URLs, filenames or server response bodies in a toast.
String syncFailureMessage(Object error, {required bool chinese}) {
  String text(String zh, String en) => chinese ? zh : en;
  String reason;
  if (error is SyncFeedbackFailure) {
    reason = switch (error.code) {
      SyncFailureCode.disabled =>
        text('WebDAV 同步未开启。', 'WebDAV sync is turned off.'),
      SyncFailureCode.notConfigured => text('尚未配置同步服务，请检查 WebDAV 设置。',
          'No sync service configured. Check WebDAV settings.'),
      SyncFailureCode.wifiRequired => text('已设置仅 Wi-Fi 同步，请连接 Wi-Fi 后重试。',
          'Wi-Fi-only sync is enabled. Connect to Wi-Fi and retry.'),
      SyncFailureCode.encryptionFailed => text('服务配置加密失败，请检查加密设置。',
          'Could not encrypt service settings. Check encryption settings.'),
      SyncFailureCode.newerDatabase => text('云端数据库版本较新，请升级本设备的默读。',
          'The remote database is newer. Update Modu on this device.'),
    };
  } else if (error is AiSyncPasswordMissingException) {
    reason = text('未设置同步加密密码，请在同步设置中补充。',
        'The sync encryption password is missing. Set it in sync settings.');
  } else if (error is AiSyncDecryptionException) {
    reason = text('加密数据无法解密，请确认各设备使用相同同步密码。',
        'Could not decrypt settings. Use the same sync password on all devices.');
  } else if (error is HandshakeException ||
      error is DioException && error.type == DioExceptionType.badCertificate) {
    reason = text('服务器安全证书或加密连接校验失败，请检查服务地址及证书。',
        'Server certificate or TLS validation failed. Check the address and certificate.');
  } else if (error is SyncNetworkUnavailable) {
    reason = text('当前网络不可用或不满足仅 Wi-Fi 条件，请检查网络后重试。',
        'Network unavailable or Wi-Fi-only requirements unmet. Check your connection.');
  } else if (error is DioException && error.response?.statusCode != null) {
    final status = error.response!.statusCode!;
    reason = switch (status) {
      401 || 403 => text('账号或目录访问被拒绝，请检查账号、密码和权限。',
          'Account or directory access denied. Check credentials and permissions.'),
      404 => text('远程目录或文件不存在，请检查同步路径。',
          'Remote directory or file not found. Check the sync path.'),
      408 => text('服务器请求超时，请检查网络后重试。',
          'The server request timed out. Check your connection and retry.'),
      409 || 412 => text('云端数据发生并发变化，请稍后重新同步。',
          'Remote data changed concurrently. Retry sync shortly.'),
      423 =>
        text('远程文件被锁定，请稍后重试。', 'The remote file is locked. Retry shortly.'),
      429 => text('服务器请求频率受限，请稍后重试或延长同步间隔。',
          'Server rate limit reached. Retry later or increase the sync interval.'),
      507 => text('服务器存储空间不足，请释放云端空间。',
          'The server has insufficient storage. Free remote space.'),
      >= 500 => text('服务器暂时不可用，请稍后重试。',
          'The server is temporarily unavailable. Retry later.'),
      _ => text('服务器请求未成功，请检查 WebDAV 服务配置。',
          'The server request failed. Check WebDAV configuration.'),
    };
    reason = '$reason (HTTP $status)';
  } else if (isTemporarySyncError(error)) {
    reason = text('网络连接失败或超时，请检查网络后重试；本机改动已保留。',
        'Connection failed or timed out. Check your network and retry; local changes are retained.');
  } else if (error is FileSystemException) {
    reason = text('本地文件读写失败，请检查存储空间和文件权限。',
        'Local file access failed. Check free space and file permissions.');
  } else if (error is FormatException) {
    final message = error.message;
    if (message.contains('阅读位置')) {
      reason = text('阅读位置数据无效，请更新所有设备后重试。',
          'Invalid reading-position data. Update all devices and retry.');
    } else if (message.contains('分页') || message.contains('截断')) {
      reason = text('服务器目录列表不完整或分页异常，已停止以避免遗漏数据。',
          'The server directory listing is incomplete or pagination is invalid. Sync stopped to avoid missing data.');
    } else if (message.contains('安全限制') || message.contains('过大')) {
      reason = text('同步数据超过安全限制，请检查同步历史和数据大小。',
          'Sync data exceeds safety limits. Check sync history and data size.');
    } else if (message.contains('版本') || message.contains('不支持')) {
      reason = text('同步数据版本或格式不兼容，请更新所有设备。',
          'Incompatible sync version or format. Update all devices.');
    } else {
      reason = text('同步数据格式或完整性校验失败，请稍后重试；不要删除云端数据。',
          'Sync data format or integrity validation failed. Retry later; do not delete remote data.');
    }
  } else if (error is UnsupportedError) {
    reason = text('服务器不支持所需同步操作，请检查 WebDAV 兼容性。',
        'The server does not support a required sync operation. Check WebDAV compatibility.');
  } else {
    reason = text('处理同步数据时发生错误，请重试或提交脱敏诊断日志。',
        'An error occurred while processing sync data. Retry or submit sanitized diagnostics.');
  }
  return chinese ? '同步失败：$reason' : 'Sync failed: $reason';
}
