import 'package:flutter/widgets.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/service/update/app_update.dart';
import 'package:anx_reader/widgets/settings/app_update_dialog.dart';

bool _startupChecked = false;
bool _dialogOpen = false;

Future<void> checkUpdate(bool manualCheck,
    {AppUpdateController? controller}) async {
  if (!manualCheck && (_startupChecked || !Prefs().autoCheckUpdates)) {
    return;
  }
  final updater = controller ?? AppUpdateController.instance;
  if (!manualCheck) {
    _startupChecked = true;
    await updater.check();
    // Startup network failures must not interrupt reading or masquerade as
    // "up to date". The About page keeps the status and offers a manual retry.
    if (!Prefs().autoCheckUpdates ||
        !updater.newer ||
        updater.phase == UpdatePhase.error ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
  }
  final context = navigatorKey.currentContext;
  if (context == null || !context.mounted || _dialogOpen) return;
  _dialogOpen = true;
  try {
    final dialog = showAppUpdateDialog(context, controller: updater);
    if (manualCheck) await updater.check();
    await dialog;
  } finally {
    _dialogOpen = false;
  }
}
