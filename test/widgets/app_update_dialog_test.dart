import 'dart:io';
import 'dart:async';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/main.dart' show navigatorKey;
import 'package:modu_reader/service/update/app_update.dart';
import 'package:modu_reader/utils/check_update.dart';
import 'package:modu_reader/widgets/settings/app_update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeTransport extends UpdateTransport {
  UpdateRelease value = const UpdateRelease('1.0.9', 'Changes',
      UpdateAsset('Modu-1.0.9-android-arm64.apk', '', 200, 'test'));
  bool offline = false;
  final browserRequests = <bool>[];
  final browserFallback = <bool>[];
  final checkRequests = <UpdateSource>[];
  Completer<UpdateRelease>? gate;
  @override
  Future<Uri> browserDownloadUrl(UpdateAsset asset,
      {bool mirrorOnly = false, bool allowFallback = true}) async {
    browserRequests.add(mirrorOnly);
    browserFallback.add(allowFallback);
    return Uri.parse(mirrorOnly ? asset.mirrorUrl! : asset.url);
  }

  @override
  Future<UpdateRelease> latest(String platform, String abi,
      {UpdateSource source = UpdateSource.github}) async {
    checkRequests.add(source);
    if (gate != null) return gate!.future;
    if (offline) throw const SocketException('offline');
    return UpdateRelease(value.version, value.notes, value.asset,
        fromMirror: value.fromMirror || source == UpdateSource.gitee);
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
    final picker = find.descendant(
        of: find.byKey(ValueKey(id)), matching: find.text(text));
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'one selector defaults to GitHub and controls checking and downloading',
      (tester) async {
    final t = FakeTransport();
    final c = AppUpdateController(
        transport: t,
        platform: 'android',
        installedVersion: () async => '1.0.8');
    addTearDown(c.dispose);
    await show(tester, c);
    final githubChip = tester
        .widget<ChoiceChip>(find.byKey(const ValueKey('update-source-github')));
    expect((githubChip.label as Text).data, 'GitHub');
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('update-source-github')))
            .selected,
        true);
    expect(find.byType(DropdownButton<UpdateSource>), findsNothing);
    await choose(tester, 'update-source', 'Gitee');
    await tester.ensureVisible(find.text('Check for updates'));
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(t.checkRequests, [UpdateSource.gitee]);
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('update-source-gitee')))
            .selected,
        true);
    expect(find.byType(DropdownButton<UpdateSource>), findsNothing);
    expect(find.byKey(const ValueKey('update-download-source')), findsNothing);
    expect(c.source, UpdateSource.gitee);
    t.gate = Completer<UpdateRelease>();
    final pending = c.check();
    await tester.pump();
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('update-source-gitee')))
            .onSelected,
        isNull);
    t.gate!.complete(t.value);
    await pending;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'macOS source choice sends chosen Gitee URL to browser on narrow screens',
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
    await choose(tester, 'update-source', 'Gitee');
    expect(find.text('Download in browser'), findsNothing);
    await tester.ensureVisible(find.text('Check for updates'));
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Download in browser'));
    await tester.tap(find.text('Download in browser'));
    await tester.pumpAndSettle();
    expect(t.browserRequests, [true]);
    expect(t.browserFallback, [false]);
    expect(t.checkRequests, [UpdateSource.github, UpdateSource.gitee]);
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
    expect(find.textContaining('Checking and downloading use the same source'),
        findsNothing);
    const hint = 'Download, then follow the system installation prompts.';
    expect(find.text(hint), findsNothing);
    await tester.tap(find.byIcon(Icons.help_outline).first);
    await tester.pumpAndSettle();
    expect(find.text(hint), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text(hint), findsNothing);
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
    expect(c.source, UpdateSource.gitee);
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('update-source-gitee')))
            .selected,
        true);
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
    expect(find.textContaining('No package is available for this device'),
        findsOneWidget);
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

  testWidgets('iOS offers export and on-demand signing instructions',
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
    expect(find.textContaining('iOS cannot install'), findsNothing);
    await tester.tap(find.byIcon(Icons.help_outline).first);
    await tester.pumpAndSettle();
    expect(find.text('Download the IPA, then sign and install it.'),
        findsOneWidget);
  });

  testWidgets(
      'macOS uses browser and rechecks before switching source, never cached install',
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
    expect(find.textContaining('cannot monitor its progress'), findsNothing);
    await tester.ensureVisible(find.text('Download in browser'));
    await tester.tap(find.text('Download in browser'));
    await tester.pumpAndSettle();
    expect(opened.single.toString(), t.value.asset!.url);
    expect(
        find.textContaining('Download opened in your browser'), findsOneWidget);
    expect(c.downloaded, isNull);
    expect(find.text('Download from Gitee'), findsNothing);
    await choose(tester, 'update-source', 'Gitee');
    expect(c.release, isNull);
    expect(find.text('Download in browser'), findsNothing);
    await tester.ensureVisible(find.text('Check for updates'));
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Download in browser'));
    await tester.tap(find.text('Download in browser'));
    await tester.pumpAndSettle();
    expect(opened.last.toString(), t.value.asset!.mirrorUrl);
    expect(t.browserRequests, [false, true]);
    expect(t.browserFallback, [false, false]);
    expect(t.checkRequests, [UpdateSource.github, UpdateSource.gitee]);
    expect(
        find.textContaining('Download opened in your browser'), findsOneWidget);
    expect(find.text('Install update'), findsNothing);
  });

  testWidgets('automatic checks default on and honor the saved preference',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Prefs();
    prefs.prefs = await SharedPreferences.getInstance();
    final transport = FakeTransport();
    final controller = AppUpdateController(
        transport: transport,
        platform: 'android',
        installedVersion: () async => '1.0.8');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
        MaterialApp(navigatorKey: navigatorKey, home: const Scaffold()));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(prefs.autoCheckUpdates, isTrue);
    await prefs.prefs.setBool('manualUpdateCheckOnly', true);
    expect(prefs.autoCheckUpdates, isFalse);
    await checkUpdate(false, controller: controller);
    expect(transport.checkRequests, isEmpty);
    expect(find.byType(AppUpdateDialog), findsNothing);

    final manual = checkUpdate(true, controller: controller);
    await tester.pumpAndSettle();
    expect(transport.checkRequests, hasLength(1));
    expect(find.text('Update available'), findsOneWidget);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await manual;

    prefs.autoCheckUpdates = true;
    transport.gate = Completer<UpdateRelease>();
    final startup = checkUpdate(false, controller: controller);
    await tester.pump();
    expect(transport.checkRequests, hasLength(2));
    prefs.autoCheckUpdates = false;
    transport.gate!.complete(transport.value);
    await tester.pumpAndSettle();
    expect(find.byType(AppUpdateDialog), findsNothing);
    await startup;
  });
}
