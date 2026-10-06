import 'dart:async';
import 'dart:io';
import 'package:anx_reader/service/sync/sync_maintenance_schedule.dart';
import 'package:flutter_test/flutter_test.dart';
import 'sync_asset_listing_test.dart' show ListingClient;

void main() {
  late Directory directory;
  late DateTime now;
  late ListingClient client;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('modu-maintenance-test-');
    now = DateTime.utc(2026);
    client = ListingClient();
  });
  tearDown(() => directory.delete(recursive: true));
  SyncMaintenanceSchedule schedule() =>
      SyncMaintenanceSchedule(directory, now: () => now);

  test(
      'unchanged repeated syncs and a restarted scheduler skip GC for six hours',
      () async {
    var calls = 0;
    Future<int> cleanup() async => ++calls;
    expect(await schedule().run(client, cleanup), 1);
    for (var i = 0; i < 10; i++) {
      expect(await schedule().run(client, cleanup), isNull);
    }
    now = now.add(const Duration(hours: 6));
    expect(await schedule().run(client, cleanup), 2);
  });
  test('failed cleanup backs off for an hour without hiding its error',
      () async {
    await expectLater(
        schedule().run(client, () async => throw StateError('offline')),
        throwsStateError);
    expect(await schedule().run(client, () async => 99), isNull);
    now = now.add(const Duration(hours: 1));
    expect(await schedule().run(client, () async => 99), 99);
  });
  test('independent endpoints never share the GC schedule', () async {
    await schedule().run(client, () async => 1);
    client.endpoint = 'memory://other';
    expect(await schedule().run(client, () async => 2), 2);
    client.endpoint = 'memory://test';
    expect(await schedule().run(client, () async => 3), isNull);
  });
  test('concurrent calls do not start duplicate maintenance', () async {
    final started = Completer<void>();
    final finish = Completer<int>();
    final pending = schedule().run(client, () {
      started.complete();
      return finish.future;
    });
    await started.future;
    expect(await schedule().run(client, () async => 2), isNull);
    finish.complete(1);
    expect(await pending, 1);
  });
}
