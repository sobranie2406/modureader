import 'dart:async';
import 'package:modu_reader/service/sync/pending_auto_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late PendingAutoSync queue;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    queue = PendingAutoSync(() => prefs);
  });

  test('persist intent immediately, but wait for reading and narration writes',
      () async {
    final writing = Completer<void>();
    var ready = false;
    final requested = queue.request(savedReading: writing.future)
      ..then((_) => ready = true);
    expect(queue.pending, true);
    await Future<void>.delayed(Duration.zero);
    expect(ready, false);
    writing.complete();
    await requested;
    expect(ready, true);
  });

  test(
      'offline, cancelled and restarted tasks remain pending until acknowledged',
      () async {
    await queue.request();
    final restarted = PendingAutoSync(() => prefs);
    expect(restarted.pending, true);
    await restarted.acknowledge(restarted.revision);
    expect(PendingAutoSync(() => prefs).pending, false);
  });

  test('completion of an older upload does not lose a new exit request',
      () async {
    await queue.request();
    final uploading = queue.revision;
    await queue.request();
    await queue.acknowledge(uploading);
    expect(queue.pending, true);
    await queue.acknowledge(queue.revision);
    await queue.acknowledge(uploading);
    expect(queue.pending, false);
    await queue.request();
    expect(queue.pending, true);
  });

  test(
      'closing another book waits for both books without overwriting positions',
      () async {
    final first = Completer<void>();
    final second = Completer<void>();
    final a = queue.request(savedReading: first.future);
    final b = queue.request(savedReading: second.future);
    var ready = false;
    queue.ready.then((_) => ready = true);
    second.complete();
    await Future<void>.delayed(Duration.zero);
    expect(ready, false);
    first.complete();
    await Future.wait([a, b]);
    expect(ready, true);
    expect(queue.revision, 2);
  });
}
