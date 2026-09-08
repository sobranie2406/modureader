import 'package:anx_reader/page/home_page/remote_library_page.dart';
import 'package:anx_reader/page/settings_page/remote_library.dart';
import 'package:anx_reader/service/remote_library/webdav_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LibraryConnectionStore.clear();
  });
  testWidgets('unconfigured remote library links to its own settings',
      (tester) async {
    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: RemoteLibraryPage())));
    await tester.pumpAndSettle();
    expect(find.text('Remote library'), findsOneWidget);
    await tester.tap(find.text('Configure library WebDAV'));
    await tester.pumpAndSettle();
    expect(find.byType(RemoteLibrarySettings), findsOneWidget);
    expect(find.text('Test connection'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('settings save does not persist passwords or enable sync',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: RemoteLibrarySettings())));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).at(0), 'https://example.com/books/');
    await tester.enterText(find.byType(TextField).at(1), 'reader');
    await tester.enterText(find.byType(TextField).at(2), 'session-secret');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {LibraryConnectionStore.key});
    expect(prefs.getString(LibraryConnectionStore.key),
        isNot(contains('session-secret')));
    expect(tester.takeException(), isNull);
  });
}
