import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/enums/sync_trigger.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/models/current_reading_state.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/service/sync/pending_auto_sync.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late HttpServer server;
  late Directory directory;
  late PathProviderPlatform oldPaths;
  HttpOverrides? oldHttp;
  late Sync sync;
  var requests = 0;
  var responseStatus = 503;
  var disconnectOnRequest = false;
  var network = ['wifi'];
  final responseGates = <int, Completer<void>>{};
  var activeRequests = 0, maximumActiveRequests = 0;
  const connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');

  setUpAll(() => container = ProviderContainer());
  tearDownAll(() => container.dispose());
  setUp(() async {
    oldHttp = HttpOverrides.current;
    HttpOverrides.global = null;
    requests = 0;
    responseStatus = 503;
    disconnectOnRequest = false;
    responseGates.clear();
    activeRequests = maximumActiveRequests = 0;
    container.read(currentReadingProvider.notifier).finish();
    network = ['wifi'];
    directory = await Directory.systemTemp.createTemp('modu-auto-sync-');
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      activeRequests++;
      if (activeRequests > maximumActiveRequests) {
        maximumActiveRequests = activeRequests;
      }
      await responseGates[requests]?.future;
      // Exercise the real provider and transport without creating a cloud library.
      request.response.statusCode = responseStatus;
      if (disconnectOnRequest) network = ['none'];
      await request.response.close();
      activeRequests--;
    });
    SharedPreferences.setMockInitialValues({
      'webdavStatus': true,
      'autoSync': true,
      'webdavInfo': jsonEncode({
        'url': 'http://127.0.0.1:${server.port}/dav',
        'username': 'fixture',
        'password': 'fixture',
      }),
    });
    await Prefs().initPrefs();
    SyncClientFactory.resetCurrentClient();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        connectivity, (call) async => call.method == 'check' ? network : null);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    sync = container.read(syncProvider.notifier);
  });
  tearDown(() async {
    sync.pauseAutomaticSync();
    HttpOverrides.global = oldHttp;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(connectivity, null);
    PathProviderPlatform.instance = oldPaths;
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('PDF reader retries a real server failure exactly three times',
      () async {
    responseStatus = 405;
    container.read(currentReadingProvider.notifier).start(CurrentReadingState(
        book: Book.mock().copyWith(filePath: 'file/test.pdf')));
    await sync.syncData(SyncDirection.both, null, immediate: true);
    expect(requests, 4);
    expect(container.read(syncProvider).isSyncing, false);
    expect(PendingAutoSync(() => Prefs().prefs).pending, true);
  });

  test('reader losing its network after the first failure stops silently',
      () async {
    responseStatus = 405;
    disconnectOnRequest = true;
    container.read(currentReadingProvider.notifier).start(CurrentReadingState(
        book: Book.mock().copyWith(filePath: 'file/test.epub')));
    await sync.syncData(SyncDirection.both, null, immediate: true);
    expect(requests, 1);
    expect(PendingAutoSync(() => Prefs().prefs).pending, true);
  });

  test('manual reader synchronization without a connection makes no requests',
      () async {
    network = ['none'];
    container.read(currentReadingProvider.notifier).start(CurrentReadingState(
        book: Book.mock().copyWith(filePath: 'file/test.epub')));
    await sync.syncData(SyncDirection.both, null, trigger: SyncTrigger.manual);
    expect(requests, 0);
    expect(container.read(syncProvider).isSyncing, false);
  });

  test('exit waits for saved progress, then probes without two-second debounce',
      () async {
    final saved = Completer<void>();
    final result = sync.syncData(SyncDirection.both, null,
        immediate: true, savedReading: saved.future);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(requests, 0);
    saved.complete();
    await result.timeout(const Duration(seconds: 1));
    expect(requests, 1);
    expect(PendingAutoSync(() => Prefs().prefs).pending, true);
    expect(container.read(syncProvider).isSyncing, false);
  });

  test(
      'locked exit stays pending, resume probes immediately and preserves failed work',
      () async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await sync.syncData(SyncDirection.both, null, immediate: true);
    expect(requests, 0);
    expect(PendingAutoSync(() => Prefs().prefs).pending, true);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await sync
        .syncData(SyncDirection.both, null, immediate: true)
        .timeout(const Duration(seconds: 1));
    expect(requests, 1);
    expect(PendingAutoSync(() => Prefs().prefs).pending, true);
  });

  test('immediate exit never bypasses disabled automatic sync', () async {
    Prefs().autoSync = false;
    await sync.syncData(SyncDirection.both, null, immediate: true);
    expect(requests, 0);
    expect(PendingAutoSync(() => Prefs().prefs).pending, true);
  });

  test('Wi-Fi-only exit on mobile stays pending and background cancels probing',
      () async {
    Prefs().onlySyncWhenWifi = true;
    network = ['mobile'];
    final result = sync.syncData(SyncDirection.both, null, immediate: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(requests, 0);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    sync.pauseAutomaticSync();
    await result;
    expect(requests, 0);
    expect(PendingAutoSync(() => Prefs().prefs).pending, true);
  });

  test('background lifecycle waits for saved progress and probes while paused',
      () async {
    responseStatus = 405;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final saved = Completer<void>();
    final result =
        sync.syncForLifecycle(background: true, savedReading: saved.future);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(requests, 0);
    saved.complete();
    await result.timeout(const Duration(seconds: 1));
    expect(requests, 1);
    expect(container.read(syncProvider).isSyncing, false);
    expect(PendingAutoSync(() => Prefs().prefs).pending, true);
  });

  for (final background in [false, true]) {
    for (final disabled in ['webdavStatus', 'autoSync', 'preview']) {
      test('lifecycle background=$background obeys $disabled', () async {
        binding.handleAppLifecycleStateChanged(
            background ? AppLifecycleState.paused : AppLifecycleState.resumed);
        if (disabled == 'webdavStatus') {
          await Prefs().prefs.setBool('webdavStatus', false);
        }
        if (disabled == 'autoSync') Prefs().autoSync = false;
        if (disabled == 'preview') Prefs().syncPreviewBeforeSync = true;
        final saved = Completer<void>();
        var finished = false;
        final result = sync
            .syncForLifecycle(
                background: background, savedReading: saved.future)
            .then((_) => finished = true);
        await Future<void>.delayed(Duration.zero);
        expect(finished, false);
        saved.complete();
        await result;
        expect(requests, 0);
      });
    }
    for (final connection in ['none', 'mobile']) {
      test('lifecycle background=$background silently defers $connection',
          () async {
        binding.handleAppLifecycleStateChanged(
            background ? AppLifecycleState.paused : AppLifecycleState.resumed);
        Prefs().onlySyncWhenWifi = true;
        network = [connection];
        await sync.syncForLifecycle(background: background);
        expect(requests, 0);
        expect(PendingAutoSync(() => Prefs().prefs).pending, true);
      });
    }
  }

  test('disabled lifecycle still waits for failed reading writes safely',
      () async {
    Prefs().autoSync = false;
    final saved = Completer<void>();
    var finished = false;
    final result = sync
        .syncForLifecycle(background: true, savedReading: saved.future)
        .then((_) => finished = true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(finished, false);
    saved.completeError(StateError('fixture write failure'));
    await result;
    expect(finished, true);
    expect(requests, 0);
  });

  test('lifecycle requests wait for active sync and their own queued execution',
      () async {
    responseStatus = 405;
    for (var i = 1; i <= 3; i++) {
      responseGates[i] = Completer<void>();
    }
    Future<void> waitForRequest(int count) async {
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (requests < count && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(requests, count);
    }

    final existing = sync.syncData(SyncDirection.both, null, immediate: true);
    await waitForRequest(1);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    sync.pauseAutomaticSync();
    var backgroundFinished = false, foregroundFinished = false;
    final background = sync
        .syncForLifecycle(background: true)
        .then((_) => backgroundFinished = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(requests, 1);
    expect(backgroundFinished, false);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final foreground = sync
        .syncForLifecycle(background: false)
        .then((_) => foregroundFinished = true);
    responseGates[1]!.complete();
    await existing;
    await waitForRequest(2);
    expect(backgroundFinished, false);
    expect(foregroundFinished, false);
    responseGates[2]!.complete();
    await background;
    await waitForRequest(3);
    expect(backgroundFinished, true);
    expect(foregroundFinished, false);
    responseGates[3]!.complete();
    await foreground;
    expect(foregroundFinished, true);
    expect(maximumActiveRequests, 1);
  });
}
