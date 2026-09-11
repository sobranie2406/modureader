import 'package:anx_reader/page/settings_page/remote_library.dart';
import 'package:anx_reader/service/config_transfer/config_transfer_codec.dart';
import 'package:anx_reader/service/config_transfer/library_config_transfer.dart';
import 'package:anx_reader/service/remote_library/webdav_library.dart';
import 'package:anx_reader/widgets/settings/config_transfer_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const original = LibraryConnection(
      url: 'https://old.example.com/', username: 'old', password: 'old-secret');
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'sync-config-sentinel': 'unchanged'});
    await LibraryConnectionStore.clear();
    await LibraryConnectionStore.save(original);
  });
  tearDown(LibraryConnectionStore.clear);

  Future<void> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: RemoteLibrarySettings())));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(ConfigTransferTile), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'import fills form only; saving without password clears the old saved password',
      (tester) async {
    await open(tester);
    await tester
        .ensureVisible(find.text('Import Library WebDAV configuration'));
    await tester.tap(find.text('Import Library WebDAV configuration'));
    await tester.pumpAndSettle();
    expect(find.text('Read from QR image'), findsOneWidget);
    expect(find.textContaining('does not save or connect'), findsOneWidget);
    final token = ConfigTransferCodec.encode(
        kind: LibraryConfigTransfer.kind,
        data: LibraryConfigTransfer.createPayload(const LibraryConnection(
            url: 'https://new.example.com/书库/', username: 'new')));
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        token);
    await tester.tap(find.text('Import configuration'));
    await tester.pumpAndSettle();
    expect((await LibraryConnectionStore.load())!.url, original.url);
    await tester.scrollUntilVisible(find.text('Save'), -200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final stored = (await LibraryConnectionStore.load())!;
    expect(stored.url, 'https://new.example.com/书库/');
    expect(stored.password, '');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sync-config-sentinel'), 'unchanged');
    expect(
        prefs.getKeys(), {'sync-config-sentinel', LibraryConnectionStore.key});
    expect(
        prefs.getString(LibraryConnectionStore.key), contains('"password":""'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('export includes password by default and allows opting out',
      (tester) async {
    await open(tester);
    final tile =
        tester.widget<ConfigTransferTile>(find.byType(ConfigTransferTile));
    expect(tile.getData()['password'], original.password);
    await tester.ensureVisible(find.text('Include password in export'));
    await tester.tap(find.text('Include password in export'));
    await tester.pumpAndSettle();
    final enabled =
        tester.widget<ConfigTransferTile>(find.byType(ConfigTransferTile));
    expect(enabled.getData().containsKey('password'), false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sync WebDAV token rejected without changing library',
      (tester) async {
    await open(tester);
    await tester
        .ensureVisible(find.text('Import Library WebDAV configuration'));
    await tester.tap(find.text('Import Library WebDAV configuration'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        ConfigTransferCodec.encode(
            kind: 'webdav', data: {'url': 'https://other.example.com/'}));
    await tester.tap(find.text('Import configuration'));
    await tester.pumpAndSettle();
    expect(find.text('This code is not Library WebDAV configuration'),
        findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect((await LibraryConnectionStore.load())!.url, original.url);
    expect(tester.takeException(), isNull);
  });
}
