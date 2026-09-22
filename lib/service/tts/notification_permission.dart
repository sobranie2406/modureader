import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

const ttsNotificationAskedKey = 'ttsNotificationPermissionAsked';

/// One contextual request, shared by overlapping start commands. Denial never
/// prevents playback (media notifications have a platform exemption).
class NotificationPermissionGate {
  NotificationPermissionGate(
      {required this.status,
      required this.request,
      required this.wasAsked,
      required this.markAsked});
  final Future<PermissionStatus> Function() status;
  final Future<PermissionStatus> Function() request;
  final bool Function() wasAsked;
  final Future<void> Function() markAsked;
  Future<PermissionStatus?>? _pending;

  Future<PermissionStatus?> ensure({required bool foregroundAndroid}) {
    if (!foregroundAndroid) return Future.value(null);
    return _pending ??= _ensure().whenComplete(() => _pending = null);
  }

  Future<PermissionStatus?> _ensure() async {
    if (wasAsked()) return null;
    final current = await status();
    await markAsked();
    if (current.isGranted) return current;
    if (current.isPermanentlyDenied || current.isRestricted) return current;
    return request();
  }
}

final _notificationGate = NotificationPermissionGate(
  status: () => Permission.notification.status,
  request: () => Permission.notification.request(),
  wasAsked: () => Prefs().prefs.getBool(ttsNotificationAskedKey) ?? false,
  markAsked: () async {
    await Prefs().prefs.setBool(ttsNotificationAskedKey, true);
  },
);

Future<void> prepareTtsNotificationPermission() async {
  try {
    final result = await _notificationGate.ensure(
      foregroundAndroid: AnxPlatform.isAndroid &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    final context = navigatorKey.currentContext;
    if (result == null ||
        result.isGranted ||
        context == null ||
        !context.mounted) return;
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(chinese
          ? '通知未开启。如需通知栏朗读控制，可在系统设置中开启；仍可继续朗读。'
          : 'Notifications are disabled. Enable them in system settings for reading controls; playback can continue.'),
      action: SnackBarAction(
          label: chinese ? '设置' : 'Settings',
          onPressed: () async {
            await openAppSettings();
          }),
    ));
  } catch (error) {
    // Missing/unsupported permission APIs must never disable TTS itself.
    AnxLog.warning(
        'TTS notification permission check failed: ${error.runtimeType}');
  }
}
