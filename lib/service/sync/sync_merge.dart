class SyncRecord {
  const SyncRecord({
    required this.id,
    required this.value,
    required this.updatedAt,
    required this.deviceId,
  });

  final String id;
  final String value;
  final DateTime updatedAt;
  final String deviceId;
}

class MergeResult {
  const MergeResult({required this.winner, this.conflict});

  final SyncRecord winner;
  final SyncRecord? conflict;
}

class SyncMerger {
  MergeResult merge(SyncRecord local, SyncRecord remote) {
    final localWins = local.updatedAt.isAfter(remote.updatedAt) ||
        (local.updatedAt == remote.updatedAt &&
            local.deviceId.compareTo(remote.deviceId) >= 0);
    return MergeResult(
      winner: localWins ? local : remote,
      conflict:
          local.value == remote.value ? null : (localWins ? remote : local),
    );
  }
}
