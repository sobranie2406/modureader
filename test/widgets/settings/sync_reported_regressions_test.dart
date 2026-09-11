import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/sync_protocol.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart' show navigatorKey;
import 'package:anx_reader/page/settings_page/sync.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/widgets/bookshelf/sync_status_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    Prefs().setSyncInfo(SyncProtocol.webdav, {
      'url': 'https://old.example.test/dav',
      'username': '',
      'password': ''
    });
  });

  test(
      'UTC server timestamps and local file timestamps show the same local clock',
      () {
    final local = DateTime(2026, 9, 12, 18, 23, 45);
    final remote = DateTime.parse(local.toUtc().toIso8601String());
    expect(formatSyncTimestamp(remote), '2026-09-12 18:23:45');
    expect(formatSyncTimestamp(local), formatSyncTimestamp(remote));
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      navigatorKey: navigatorKey,
      locale: const Locale('en'),
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      home: const Scaffold(body: SyncSetting()),
    )));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'saving WebDAV immediately refreshes URL without leaving settings',
      (tester) async {
    await open(tester);
    await tester.ensureVisible(find.text('https://old.example.test/dav'));
    await tester.tap(find.text('https://old.example.test/dav'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).first, 'https://new.example.test/dav');
    await tester
        .tap(find.text(L10n.of(navigatorKey.currentContext!).commonSave));
    await tester.pumpAndSettle();
    expect(Prefs().getSyncInfo(SyncProtocol.webdav)['url'],
        'https://new.example.test/dav');
    expect(find.text('https://new.example.test/dav'), findsOneWidget);
    expect(find.text('https://old.example.test/dav'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'backup management Cancel dismisses only its dialog and keeps settings',
      (tester) async {
    await open(tester);
    // Missing path-provider host is safely treated as no backups by production.
    late Future<void> pending;
    await tester.runAsync(() async {
      pending = Sync().showBackupManagementDialog();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    final l10n = L10n.of(navigatorKey.currentContext!);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text(l10n.commonCancel)));
    await tester.pumpAndSettle();
    await tester.runAsync(() => pending);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SyncSetting), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
