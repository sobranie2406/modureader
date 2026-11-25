import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/page/settings_page/remote_library.dart';
import 'package:modu_reader/service/local_data/backup_safety.dart';
import 'package:modu_reader/service/remote_library/ftp_connection.dart';
import 'package:modu_reader/service/remote_library/webdav_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const webdav = LibraryConnection(
    url: 'https://webdav.example.test/books/',
    username: 'webdav-reader',
    password: 'webdav-secret',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await LibraryConnectionStore.save(webdav);
  });

  testWidgets('FTP settings save, reopen and clear independently of WebDAV',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> open(RemoteLibrarySource source) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: RemoteLibrarySettings(initialSource: source)),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> tap(String label) async {
      final button = find.text(label);
      await tester.scrollUntilVisible(button, 160,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    TextField field(int index) =>
        tester.widget<TextField>(find.byType(TextField).at(index));

    await open(RemoteLibrarySource.webdav);
    expect(field(1).controller!.text, webdav.username);
    await tester.tap(find.text('FTP'));
    await tester.pumpAndSettle();
    expect(field(0).controller!.text, isEmpty);
    expect(field(3).obscureText, true);
    await tester.enterText(
        find.byType(TextField).at(0), 'nas.example.test:2121');
    await tester.enterText(find.byType(TextField).at(1), '/图书/小说');
    await tester.enterText(find.byType(TextField).at(2), 'ftp-reader');
    await tester.enterText(find.byType(TextField).at(3), 'ftp-secret');
    await tap('Save');

    final ftp = (await FtpConnectionStore.load())!;
    expect(ftp.root.port, 2121);
    expect(ftp.root.pathSegments, ['图书', '小说', '']);
    expect(ftp.username, 'ftp-reader');
    expect(ftp.password, 'ftp-secret');
    expect((await LibraryConnectionStore.load())!.password, webdav.password);

    await open(RemoteLibrarySource.ftp);
    expect(field(1).controller!.text, '/图书/小说');
    expect(field(3).controller!.text, 'ftp-secret');
    expect(field(3).obscureText, true);
    await tap('Clear connection');
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(await FtpConnectionStore.load(), isNull);
    expect((await LibraryConnectionStore.load())!.url, webdav.url);
    expect(tester.takeException(), isNull);
  });

  test('local FTP credentials stay out of whole-library backups', () async {
    await FtpConnectionStore.save(const FtpConnection(
      address: '192.168.1.1',
      username: 'ftp-reader',
      password: 'local-ftp-secret',
    ));
    final backup = await Prefs().buildPrefsBackupMap();
    expect(backup, isNot(contains(FtpConnectionStore.key)));
    expect(backup, contains(LibraryConnectionStore.key));
    expect(
        withoutBackupCredentials({FtpConnectionStore.key: 'ftp-credentials'}),
        isEmpty);

    await Prefs().applyPrefsBackupMap({
      FtpConnectionStore.key: {
        'type': 'string',
        'value': jsonEncode({'address': 'other.example.test'}),
      },
    });
    expect((await FtpConnectionStore.load())!.password, 'local-ftp-secret');
  });
}
