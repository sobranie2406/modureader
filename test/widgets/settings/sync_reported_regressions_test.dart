import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/sync_protocol.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart' show navigatorKey;
import 'package:anx_reader/page/settings_page/sync.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/widgets/bookshelf/sync_status_bottom_sheet.dart';
import 'package:anx_reader/widgets/settings/database_backup_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
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
      builder: FlutterSmartDialog.init(),
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
      'database export uses the renamed dialog and cancellation unlocks actions',
      (tester) async {
    await open(tester);
    final export = find.byKey(const ValueKey('database-backup-export'));
    await tester.scrollUntilVisible(export, 500,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(export);
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Export database backup')),
        findsOneWidget);
    expect(
        tester
            .widget<DatabaseBackupSection>(find.byType(DatabaseBackupSection))
            .busy,
        true);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        tester
            .widget<DatabaseBackupSection>(find.byType(DatabaseBackupSection))
            .busy,
        false);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('active WebDAV cannot be accidentally switched or reconfigured',
      (tester) async {
    Prefs().saveWebdavStatus(true);
    final saved = Prefs().prefs.getString('webdavInfo');
    await open(tester);
    await tester.tap(find.text('Object storage'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsNothing);
    await tester.ensureVisible(find.text('https://old.example.test/dav'));
    await tester.tap(find.text('https://old.example.test/dav'),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsNothing);
    expect(Prefs().prefs.getString('webdavInfo'), saved);
    expect(Prefs().syncProtocol, isNull);
    expect(Prefs().webdavStatus, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'backend tabs restore independent connection settings without enabling sync',
      (tester) async {
    final dav = Prefs().prefs.getString('webdavInfo');
    Prefs().setSyncInfo(SyncProtocol.s3, {
      'endpoint': 'https://objects.example.test',
      'bucket': 'saved-bucket',
      'accessKeyId': 'example-id',
      'secretAccessKey': 'example-secret',
    });
    final s3 = Prefs().prefs.getString('s3Info');
    await open(tester);
    expect(find.text('https://old.example.test/dav'), findsOneWidget);
    await tester.tap(find.text('Object storage'));
    await tester.pumpAndSettle();
    expect(Prefs().syncProtocol, 's3');
    expect(find.text('saved-bucket'), findsOneWidget);
    expect(find.text('https://old.example.test/dav'), findsNothing);
    expect(Prefs().webdavStatus, false);
    final tabs = find.byKey(const ValueKey('sync-backend-tabs'));
    await tester.tap(find.descendant(of: tabs, matching: find.text('WebDAV')));
    await tester.pumpAndSettle();
    expect(Prefs().syncProtocol, 'webdav');
    expect(find.text('https://old.example.test/dav'), findsOneWidget);
    expect(Prefs().prefs.getString('webdavInfo'), dav);
    expect(Prefs().prefs.getString('s3Info'), s3);
    expect(Prefs().webdavStatus, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active object storage cannot switch to WebDAV', (tester) async {
    Prefs().syncProtocol = 's3';
    Prefs().saveWebdavStatus(true);
    await open(tester);
    final tabs = find.byKey(const ValueKey('sync-backend-tabs'));
    await tester.tap(find.descendant(of: tabs, matching: find.text('WebDAV')),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(Prefs().syncProtocol, 's3');
    expect(Prefs().webdavStatus, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'WebDAV password reveal never changes saved credentials on cancel',
      (tester) async {
    final saved = Prefs().prefs.getString('webdavInfo');
    await open(tester);
    await tester.tap(find.text('https://old.example.test/dav'));
    await tester.pumpAndSettle();
    final password = find.byType(TextField).last;
    expect(tester.widget<TextField>(password).obscureText, true);
    await tester.tap(find.byTooltip('Show sensitive value'));
    await tester.pump();
    expect(tester.widget<TextField>(password).obscureText, false);
    await tester.enterText(password, 'unsaved-example');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(Prefs().prefs.getString('webdavInfo'), saved);
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
