import 'dart:io';
import 'package:anx_reader/service/update/app_update.dart';
import 'package:anx_reader/widgets/settings/app_update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTransport extends UpdateTransport {
  UpdateRelease value = const UpdateRelease('1.0.9', 'Changes',
      UpdateAsset('Modu-1.0.9-android-arm64.apk', '', 200, 'test'));
  bool offline = false;
  @override
  Future<UpdateRelease> latest(String platform, String abi) async {
    if (offline) throw const SocketException('offline');
    return value;
  }
}

void main() {
  Future<void> show(WidgetTester tester, AppUpdateController c) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AppUpdateDialog(controller: c))));
    await tester.pumpAndSettle();
  }

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
        transport: t, installedVersion: () async => '1.0.8');
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
}
