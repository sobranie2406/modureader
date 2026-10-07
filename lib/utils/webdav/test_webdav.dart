import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/enums/sync_trigger.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/enums/sync_protocol.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/service/sync/sync_connection_tester.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<bool> testEnableWebdav() async {
  final protocol = SyncClientFactory.getCurrentSyncProtocol();
  final info = Prefs().getSyncInfo(protocol);
  if (info.isNotEmpty) {
    final result = await SyncConnectionTester.testConnection(
      protocol: protocol,
      config: info,
    );
    if (result.isSuccess) {
      return true;
    } else {
      AnxToast.show(protocol == SyncProtocol.webdav
          ? L10n.of(navigatorKey.currentContext!).webdavConnectionFailed
          : result.message);
    }
  } else {
    AnxToast.show(protocol == SyncProtocol.webdav
        ? L10n.of(navigatorKey.currentContext!).webdavSetInfoFirst
        : ModuStrings.text(navigatorKey.currentContext!, '请先配置对象存储同步。',
            'Configure object storage sync first.'));
  }
  return false;
}

void chooseDirection(WidgetRef ref) {
  // Keep the existing settings entry point, but never offer destructive
  // whole-library upload/download choices for record-based synchronization.
  Sync().syncData(SyncDirection.both, ref, trigger: SyncTrigger.manual);
}
