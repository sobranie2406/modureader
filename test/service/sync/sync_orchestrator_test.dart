import 'package:anx_reader/service/sync/sync_orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coalesces repeated changes for the same object', () {
    final queue = SyncQueue();
    queue.enqueue(const SyncChange(id: 'note-1', payload: 'first'));
    queue.enqueue(const SyncChange(id: 'note-1', payload: 'latest'));

    expect(queue.pending, hasLength(1));
    expect(queue.pending.single.payload, 'latest');
  });

  test('acknowledges only the requested change', () {
    final queue = SyncQueue()
      ..enqueue(const SyncChange(id: 'book-1', payload: 'book'))
      ..enqueue(const SyncChange(id: 'note-1', payload: 'note'));

    queue.acknowledge('book-1');

    expect(queue.pending.map((change) => change.id), ['note-1']);
  });
}
