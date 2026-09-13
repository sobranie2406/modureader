import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Production Sync is a singleton attached to the application's one container.
  late ProviderContainer container;
  setUpAll(() => container = ProviderContainer());
  tearDownAll(() => container.dispose());
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'webdavStatus': true, 'autoSync': true});
    await Prefs().initPrefs();
  });
  test('closed reader request is rejected before client initialization',
      () async {
    final sync = container.read(syncProvider.notifier);
    final clientBefore = SyncClientFactory.currentClient;
    await sync.syncData(SyncDirection.both, null, shouldStart: () => false);
    expect(container.read(syncProvider).isSyncing, false);
    expect(SyncClientFactory.currentClient, same(clientBefore));
  });
  test('leaving the reader during auto-start delay cannot reach the network',
      () {
    final sync = container.read(syncProvider.notifier);
    final clientBefore = SyncClientFactory.currentClient;
    fakeAsync((clock) {
      var allowed = true, completed = false;
      sync
          .syncData(SyncDirection.both, null, shouldStart: () => allowed)
          .then((_) => completed = true);
      clock.elapse(const Duration(seconds: 1));
      allowed = false;
      clock.elapse(const Duration(seconds: 2));
      expect(completed, true);
      expect(SyncClientFactory.currentClient, same(clientBefore));
      expect(container.read(syncProvider).isSyncing, false);
    });
  });
}
