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
import 'package:modu_reader/utils/webView/webview_environment_boot.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
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

/// The shared Windows WebView2 environment, for the many call sites that pass
/// it straight to `InAppWebView`.
///
/// The object is owned by [WebViewEnvironmentBoot], not by this page: creating
/// it in a post-frame callback meant one failure latched null for the rest of
/// the session, and every background WebView (plugins, article capture, book
/// import, AI search) failed until the app restarted. The boot module retries
/// and lets a caller ask for it again.
WebViewEnvironment? get webViewEnvironment =>
    WebViewEnvironmentBoot.instance.environment;

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
    // One call owns creation, retry and the profile folder, so a failed start is
    // not permanent and no two callers create a second environment at once.
    final environment = await WebViewEnvironmentBoot.instance.ensure();
    AnxLog.info('WebView2 environment: '
        '${environment == null ? 'unavailable' : 'ready'}');
    if (environment == null && mounted) {
      final missingRuntime =
          WebViewEnvironmentBoot.instance.lastError?.contains('not installed') ==
              true;
      SmartDialog.show(
        builder: (context) => AlertDialog(
          title: const Icon(Icons.error),
          content: Text(missingRuntime
              ? L10n.of(context).webview2NotInstalled
              : ModuStrings.text(
                  context,
                  '网页组件启动失败，导入、插件与 AI 搜索暂时不可用。可以重试，或检查 Microsoft Edge WebView2 Runtime 是否正常。',
                  'The web component failed to start, so import, plugins and AI search are unavailable. You can retry, or check that the Microsoft Edge WebView2 Runtime is installed correctly.')),
          actions: [
            TextButton(
              onPressed: () async {
                SmartDialog.dismiss();
                await _checkWindowsWebview();
              },
              child: Text(ModuStrings.text(context, '重试', 'Retry')),
            ),
            if (missingRuntime)
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
