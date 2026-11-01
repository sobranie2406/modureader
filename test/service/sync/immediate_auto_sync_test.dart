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
  const connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');

  setUpAll(() => container = ProviderContainer());
  tearDownAll(() => container.dispose());
  setUp(() async {
    oldHttp = HttpOverrides.current;
    HttpOverrides.global = null;
    requests = 0;
    responseStatus = 503;
    disconnectOnRequest = false;
    container.read(currentReadingProvider.notifier).finish();
    network = ['wifi'];
    directory = await Directory.systemTemp.createTemp('modu-auto-sync-');
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      // Exercise the real provider and transport without creating a cloud library.
      request.response.statusCode = responseStatus;
      if (disconnectOnRequest) network = ['none'];
      await request.response.close();
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
}
