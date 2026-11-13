import 'package:modu_reader/service/receive_file/external_book_inbox.dart';
import 'dart:async';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/dao/database.dart';
import 'package:modu_reader/enums/sync_direction.dart';
import 'package:modu_reader/enums/sync_trigger.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/page/home_page/bookshelf_page.dart';
import 'package:modu_reader/page/home_page/notes_page.dart';
import 'package:modu_reader/page/home_page/remote_library_page.dart';
import 'package:modu_reader/page/home_page/settings_page.dart';
import 'package:modu_reader/page/home_page/statistics_page.dart';
import 'package:modu_reader/providers/sync.dart';
import 'package:modu_reader/service/initialization_check.dart';
import 'package:modu_reader/service/notes/open_reading_link.dart';
import 'package:modu_reader/service/notes/reading_link.dart';
import 'package:modu_reader/service/receive_file/receive_share.dart';
import 'package:modu_reader/utils/check_update.dart';
import 'package:modu_reader/utils/get_path/get_temp_dir.dart';
import 'package:modu_reader/utils/load_default_font.dart';
import 'package:modu_reader/utils/log/common.dart';
import 'package:modu_reader/utils/platform_utils.dart';
import 'package:modu_reader/utils/toast/common.dart';
import 'package:modu_reader/widgets/ai/ai_chat_stream.dart';
import 'package:modu_reader/widgets/home_navigation_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

WebViewEnvironment? webViewEnvironment;

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => initAnx());
  }

  Future<void> _checkWindowsWebview() async {
    final availableVersion = await WebViewEnvironment.getAvailableVersion();
    AnxLog.info('WebView2 version: $availableVersion');

    if (availableVersion == null) {
      SmartDialog.show(
        builder: (context) => AlertDialog(
          title: const Icon(Icons.error),
          content: Text(L10n.of(context).webview2NotInstalled),
          actions: [
            TextButton(
              onPressed: () => {
                launchUrl(
                    Uri.parse(
                        'https://developer.microsoft.com/en-us/microsoft-edge/webview2'),
                    mode: LaunchMode.externalApplication)
              },
              child: Text(L10n.of(context).webview2Install),
            ),
          ],
        ),
      );
    } else {
      webViewEnvironment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
            userDataFolder: (await getAnxTempDir()).path),
      );
    }
  }

  void _showDbUpdatedDialog() {
    SmartDialog.show(
      clickMaskDismiss: false,
      builder: (context) => AlertDialog(
        title: Text(L10n.of(context).commonAttention),
        content: Text(L10n.of(context).dbUpdatedTip),
        actions: [
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
            },
            child: Text(L10n.of(context).commonOk),
          ),
        ],
      ),
    );
  }

  Future<void> initAnx() async {
    AnxToast.init(context);
    if (AnxPlatform.isWindows) {
      await _checkWindowsWebview();
    }
    if (!mounted) return;
    // Local note links must not wait for optional remote synchronization.
    readingLinkInbox.attach((raw) => openReadingLink(raw, context, ref));
    checkUpdate(false);
    InitializationCheck.check();
    if (Prefs().webdavStatus) {
      await Sync().init();
      unawaited(Sync().syncData(SyncDirection.both, null,
          trigger: SyncTrigger.auto, immediate: true));
    }
    loadDefaultFont();

    if (!mounted) return;

    receiveExternalBooks(ref);

    if (DBHelper.updatedDB) {
      _showDbUpdatedDialog();
    }
  }

  @override
  void dispose() {
    readingLinkInbox.detach();
    externalBookInbox.detach();
    super.dispose();
  }

  Widget _buildPage(String identifier, ScrollController? controller) {
    return switch (identifier) {
      HomeNavigationDestination.remoteLibrary => const RemoteLibraryPage(),
      HomeNavigationDestination.statistics =>
        StatisticPage(controller: controller),
      HomeNavigationDestination.ai => AiChatStream(),
      HomeNavigationDestination.notes => NotesPage(controller: controller),
      HomeNavigationDestination.settings =>
        SettingsPage(controller: controller),
      _ => BookshelfPage(controller: controller),
    };
  }

  @override
  Widget build(BuildContext context) {
    return HomeNavigationShell(pageBuilder: _buildPage);
  }
}
