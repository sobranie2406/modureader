import 'package:anx_reader/page/settings_page/remote_library.dart';
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
    expect(find.text('Remote library settings'), findsOneWidget);
    expect(find.text('Library WebDAV'), findsNothing);
  }

  testWidgets(
      'library transfer and password export controls moved to global page',
      (tester) async {
    await open(tester);
    expect(find.byType(ConfigTransferTile), findsNothing);
    expect(find.text('Include password in export'), findsNothing);
    expect((await LibraryConnectionStore.load())!.url, original.url);
    expect(tester.takeException(), isNull);
  });
}
