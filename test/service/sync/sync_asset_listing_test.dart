import 'package:anx_reader/models/remote_file.dart';
import 'package:anx_reader/service/sync/sync_asset_listing.dart';
import 'package:anx_reader/service/sync/sync_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'row_sync_test.dart' show MemorySyncClient;

class ListingClient extends MemorySyncClient {
  final calls = <String>[];
  bool fail = false;
  String endpoint = 'memory://test';
  @override
  Map<String, dynamic> get config => {'url': endpoint, 'username': 'test'};
  @override
  Future<List<RemoteFile>> safeReadDir(String path) async {
    calls.add(path);
    if (fail) throw StateError('incomplete directory');
    return readDir(path);
  }
}

void main() {
  test('three stable asset passes list books and covers once each', () async {
    final client = ListingClient();
    final listing = SyncAssetListing(client);
    for (var i = 0; i < 3; i++) {
      await listing.read(SyncPaths.books, ['file/a']);
      await listing.read(SyncPaths.covers, ['cover/a']);
    }
    expect(client.calls, [SyncPaths.books, SyncPaths.covers]);
  });
  test('new or changed merged references invalidate only affected directory',
      () async {
    final client = ListingClient();
    final listing = SyncAssetListing(client);
    await listing.read(SyncPaths.books, ['file/a']);
    await listing.read(SyncPaths.covers, ['cover/a']);
    client.files['${SyncPaths.covers}/b'] = [1];
    expect(await listing.read(SyncPaths.covers, ['cover/b']), {'cover/b'});
    await listing.read(SyncPaths.books, ['file/a']);
    expect(client.calls, [SyncPaths.books, SyncPaths.covers, SyncPaths.covers]);
  });
  test('successful uploads join this round; next round rechecks remote state',
      () async {
    final client = ListingClient();
    final listing = SyncAssetListing(client);
    await listing.read(SyncPaths.books, ['file/a']);
    listing.uploaded('file/a');
    expect(await listing.read(SyncPaths.books, ['file/a']), {'file/a'});
    expect(listing.bookNames, ['a']);
    expect(await SyncAssetListing(client).read(SyncPaths.books, ['file/a']),
        isEmpty);
    expect(client.calls, hasLength(2));
  });
  test('failed directory scans are not cached as empty', () async {
    final client = ListingClient()..fail = true;
    final listing = SyncAssetListing(client);
    await expectLater(listing.read(SyncPaths.books, []), throwsStateError);
    client.fail = false;
    await listing.read(SyncPaths.books, []);
    expect(client.calls, hasLength(2));
  });
  test('database/log directories cannot be cached; endpoint changes stop reuse',
      () async {
    final client = ListingClient();
    final listing = SyncAssetListing(client);
    await expectLater(
        listing.read(SyncPaths.recordLog, []), throwsArgumentError);
    await listing.read(SyncPaths.books, []);
    client.endpoint = 'memory://other';
    await expectLater(listing.read(SyncPaths.books, []), throwsStateError);
    expect(() => listing.uploaded('file/a'), throwsStateError);
  });
}
