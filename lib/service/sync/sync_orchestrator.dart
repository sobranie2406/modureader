import 'sync_merge.dart';

class SyncChange {
  const SyncChange({
    required this.id,
    required this.payload,
    this.attempts = 0,
  });

  final String id;
  final String payload;
  final int attempts;

  SyncChange incrementAttempt() =>
      SyncChange(id: id, payload: payload, attempts: attempts + 1);
}

class SyncQueue {
  final Map<String, SyncChange> _changes = {};

  List<SyncChange> get pending => List.unmodifiable(_changes.values);

  void enqueue(SyncChange change) {
    _changes[change.id] = change;
  }

  void acknowledge(String id) {
    _changes.remove(id);
  }

  SyncChange? retry(String id, {int maxAttempts = 5}) {
    final change = _changes[id];
    if (change == null || change.attempts >= maxAttempts) return null;
    final next = change.incrementAttempt();
    _changes[id] = next;
    return next;
  }
}

/// Application-level boundary for startup and lifecycle-triggered sync.
class SyncOrchestrator {
  SyncOrchestrator(this.queue, this.merger);

  final SyncQueue queue;
  final SyncMerger merger;

  void recordLocalChange(SyncChange change) => queue.enqueue(change);
}
