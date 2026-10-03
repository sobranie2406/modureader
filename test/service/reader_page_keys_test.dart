import 'package:anx_reader/service/reader_page_keys.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(ReaderPageKeys.channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(
      () => messenger.setMockMethodCallHandler(ReaderPageKeys.channel, null));

  Future<void> send(Object? direction, [String method = 'turnPage']) async {
    await messenger.handlePlatformMessage(
        ReaderPageKeys.channel.name,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall(method, direction)),
        (_) {});
  }

  test('direct remote paging works with volume mapping disabled', () async {
    final turns = <int>[];
    final bridge = ReaderPageKeys(android: true, onDirection: turns.add);
    await send(1);
    expect(turns, isEmpty);
    bridge.update(active: true, volume: false);
    await send(-1);
    await send(1);
    await send(0);
    await send('1');
    await send(1, 'other');
    expect(turns, [-1, 1]);
    expect(calls.single.arguments, {'active': true, 'volume': false});
    bridge.dispose();
  });

  test('panels/background block callbacks; resume and disposal release keys',
      () async {
    final turns = <int>[];
    final bridge = ReaderPageKeys(android: true, onDirection: turns.add);
    bridge.update(active: true, volume: true);
    bridge.update(active: true, volume: true);
    expect(calls, hasLength(1));
    bridge.update(active: false, volume: true);
    await send(1);
    expect(turns, isEmpty);
    bridge.update(active: true, volume: true);
    await send(1);
    expect(turns, [1]);
    bridge.dispose();
    await send(-1);
    expect(turns, [1]);
    expect(calls.last.arguments, {'active': false, 'volume': false});
  });

  test('non-Android hosts never activate Android interception', () {
    final bridge = ReaderPageKeys(android: false, onDirection: (_) {});
    bridge.update(active: true, volume: true);
    bridge.dispose();
    expect(calls, isEmpty);
  });

  test(
      'native host refresh resends unchanged policy, including blocked readers',
      () async {
    var allowed = true;
    var refreshes = 0;
    final turns = <int>[];
    late ReaderPageKeys bridge;
    bridge = ReaderPageKeys(
        android: true,
        onDirection: turns.add,
        onHostStateChanged: () {
          refreshes++;
          bridge.update(active: allowed, volume: false, force: true);
        });
    bridge.update(active: true, volume: false);
    for (var i = 0; i < 3; i++) {
      await send(null, 'hostStateChanged');
    }
    expect(refreshes, 3);
    expect(calls, hasLength(4));
    expect(calls.last.arguments, {'active': true, 'volume': false});
    allowed = false;
    await send(null, 'hostStateChanged');
    await send(1);
    expect(turns, isEmpty);
    await send(null, 'hostStateChanged');
    expect(refreshes, 5);
    expect(calls.last.arguments, {'active': false, 'volume': false});
    bridge.dispose();
    await send(null, 'hostStateChanged');
    expect(refreshes, 5);
  });
}
