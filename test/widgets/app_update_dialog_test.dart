import 'dart:io';
import 'dart:async';
import 'package:anx_reader/service/update/app_update.dart';
import 'package:anx_reader/widgets/settings/app_update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTransport extends UpdateTransport {
  UpdateRelease value = const UpdateRelease('1.0.9', 'Changes',
      UpdateAsset('Modu-1.0.9-android-arm64.apk', '', 200, 'test'));
  bool offline = false;
  final browserRequests = <bool>[];
  final checkRequests = <UpdateSource>[];
  Completer<UpdateRelease>? gate;
  @override
  Future<Uri> browserDownloadUrl(UpdateAsset asset,
      {bool mirrorOnly = false}) async {
    browserRequests.add(mirrorOnly);
    return Uri.parse(mirrorOnly ? asset.mirrorUrl! : asset.url);
  }

  @override
  Future<UpdateRelease> latest(String platform, String abi,
      {UpdateSource source = UpdateSource.github}) async {
    checkRequests.add(source);
    if (gate != null) return gate!.future;
    if (offline) throw const SocketException('offline');
    return value;
  }
}

void main() {
  Future<void> show(WidgetTester tester, AppUpdateController c,
      {Future<bool> Function(Uri)? openBrowser,
      Size size = const Size(600, 1000)}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AppUpdateDialog(controller: c, openBrowser: openBrowser))));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String id, String text) async {
    final picker = find.byKey(ValueKey(id));
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'source selectors default to GitHub, explicit Gitee check is dispatched',
      (tester) async {
    final t = FakeTransport();
    final c = AppUpdateController(
        transport: t,
        platform: 'android',
        installedVersion: () async => '1.0.8');
    addTearDown(c.dispose);
    await show(tester, c);
    expect(
        tester
            .widget<DropdownButton<UpdateSource>>(
                find.byKey(const ValueKey('update-check-source')))
            .value,
        UpdateSource.github);
    await choose(tester, 'update-check-source', 'Gitee');
    await tester.ensureVisible(find.text('Check for updates'));
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(t.checkRequests, [UpdateSource.gitee]);
    expect(
        tester
            .widget<DropdownButton<UpdateSource>>(
                find.byKey(const ValueKey('update-download-source')))
            .value,
        UpdateSource.github);
    await choose(tester, 'update-download-source', 'Gitee');
    expect(c.downloadSource, UpdateSource.gitee);
    t.gate = Completer<UpdateRelease>();
    final pending = c.check();
    await tester.pump();
    for (final id in ['update-check-source', 'update-download-source']) {
      expect(
          tester
              .widget<DropdownButton<UpdateSource>>(find.byKey(ValueKey(id)))
              .onChanged,
          isNull);
    }
    t.gate!.complete(t.value);
    await pending;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'macOS dropdown sends chosen Gitee URL to browser on narrow screens',
      (tester) async {
    final t = FakeTransport()
      ..value = const UpdateRelease(
          '1.1.3',
          '',
          UpdateAsset(
              'Modu-1.1.3-macos-arm64.dmg',
              '$moduReleasePage/download/v1.1.3/Modu-1.1.3-macos-arm64.dmg',
              200,
              'test',
              mirrorUrl:
                  '$moduMirrorReleasePage/download/v1.1.3/Modu-1.1.3-macos-arm64.dmg'));
    final c = AppUpdateController(
        transport: t, platform: 'macos', installedVersion: () async => '1.1.2');
    addTearDown(c.dispose);
    await c.check();
    final opened = <Uri>[];
    await show(tester, c, size: const Size(320, 800), openBrowser: (uri) async {
      opened.add(uri);
      return true;
    });
    await choose(tester, 'update-download-source', 'Gitee');
    await tester.ensureVisible(find.text('Download in browser'));
    await tester.tap(find.text('Download in browser'));
    await tester.pumpAndSettle();
    expect(t.browserRequests, [true]);
    expect(opened.single.toString(), t.value.asset!.mirrorUrl);
    expect(find.text('Install update'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'manual check exposes installed/latest versions and download action',
      (tester) async {
    final c = AppUpdateController(
        transport: FakeTransport(),
        platform: 'android',
        installedVersion: () async => '1.0.8+10026');
    await show(tester, c);
    expect(find.text('Download update'), findsNothing);
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.text('Installed: 1.0.8+10026'), findsOneWidget);
    expect(find.text('Latest stable: 1.0.9'), findsOneWidget);
    expect(find.text('Download update'), findsOneWidget);
    expect(find.text('Install update'), findsNothing);
    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Release information source: GitHub'), findsOneWidget);
    expect(find.textContaining('Checks GitHub first'), findsOneWidget);
    expect(find.textContaining('downloads from GitHub first'), findsOneWidget);
  });

  testWidgets('displays mirror metadata source without claiming installation',
      (tester) async {
    final t = FakeTransport();
    t.value = UpdateRelease(t.value.version, t.value.notes, t.value.asset,
        fromMirror: true);
    final c = AppUpdateController(
        transport: t,
        platform: 'android',
        installedVersion: () async => '1.0.8');
    await c.check();
    await show(tester, c);
    expect(find.text('Release information source: Gitee'), findsOneWidget);
    expect(find.text('Download update'), findsOneWidget);
    expect(find.text('Install update'), findsNothing);
  });

  testWidgets('unsupported package offers release page but no unsafe download',
      (tester) async {
    final t = FakeTransport()..value = const UpdateRelease('1.0.9', '', null);
    final c = AppUpdateController(
        transport: t, installedVersion: () async => '1.0.8');
    await c.check();
    await show(tester, c);
    expect(find.text('Release page'), findsOneWidget);
    expect(find.text('Download update'), findsNothing);
    expect(find.textContaining('No matching package'), findsOneWidget);
  });

  testWidgets('check failure is visible and retryable, not up to date',
      (tester) async {
    final t = FakeTransport()..offline = true;
    final c = AppUpdateController(
        transport: t, installedVersion: () async => '1.0.8');
    await c.check();
    await show(tester, c);
    expect(find.text('Update could not complete'), findsOneWidget);
    expect(find.textContaining('Check your connection'), findsOneWidget);
    t.offline = false;
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);
  });

  testWidgets(
      'installation requires confirmation and cancelling does not open a platform installer',
      (tester) async {
    final c = AppUpdateController(
        transport: FakeTransport(),
        platform: 'android',
        installedVersion: () async => '1.0.8');
    await c.check();
    c.downloaded = File('/synthetic/never-execute.apk');
    c.phase = UpdatePhase.ready;
    await show(tester, c);
    await tester.tap(find.text('Install update'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm update'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.phase, UpdatePhase.ready);
    expect(c.error, isEmpty);
  });

  testWidgets(
      'iOS exposes export and signing limitation, not direct installation',
      (tester) async {
    final c = AppUpdateController(
        transport: FakeTransport(),
        platform: 'ios',
        installedVersion: () async => '1.0.8');
    await c.check();
    c.downloaded = File('/synthetic/never-execute.ipa');
    c.phase = UpdatePhase.ready;
    await show(tester, c);
    expect(find.text('Export IPA'), findsOneWidget);
    expect(find.text('Install update'), findsNothing);
    expect(find.textContaining('iOS cannot install'), findsOneWidget);
  });

  testWidgets(
      'macOS uses browser and offers manual mirror, never cached install',
      (tester) async {
    final t = FakeTransport()
      ..value = const UpdateRelease(
          '1.1.3',
          '',
          UpdateAsset(
              'Modu-1.1.3-macos-arm64.dmg',
              '$moduReleasePage/download/v1.1.3/Modu-1.1.3-macos-arm64.dmg',
              200,
              'test',
              mirrorUrl:
                  '$moduMirrorReleasePage/download/v1.1.3/Modu-1.1.3-macos-arm64.dmg'));
    final c = AppUpdateController(
        transport: t, platform: 'macos', installedVersion: () async => '1.1.2');
    addTearDown(c.dispose);
    await c.check();
    c.downloaded = File('/synthetic/quarantined.dmg');
    c.phase = UpdatePhase.ready;
    final opened = <Uri>[];
    await show(tester, c, openBrowser: (uri) async {
      opened.add(uri);
      return true;
    });
    expect(find.text('Download update'), findsNothing);
    expect(find.text('Install update'), findsNothing);
    expect(find.text('/synthetic/quarantined.dmg'), findsNothing);
    expect(find.text('Downloaded; SHA-256 verified'), findsNothing);
    expect(find.textContaining('cannot monitor its progress'), findsOneWidget);
    await tester.ensureVisible(find.text('Download in browser'));
    await tester.tap(find.text('Download in browser'));
    await tester.pumpAndSettle();
    expect(opened.single.toString(), t.value.asset!.url);
    expect(find.textContaining('GitHub download opened'), findsOneWidget);
    expect(c.downloaded, isNull);
    await tester.ensureVisible(find.text('Download from Gitee'));
    await tester.tap(find.text('Download from Gitee'));
    await tester.pumpAndSettle();
    expect(opened.last.toString(), t.value.asset!.mirrorUrl);
    expect(t.browserRequests, [false, true]);
    expect(find.textContaining('Gitee download opened'), findsOneWidget);
    expect(find.text('Install update'), findsNothing);
  });
}
