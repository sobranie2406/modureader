import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';

/// Device-local, endpoint-specific scheduling; not part of the sync archive.
/// Delaying recoverable GC is safe; it never delays publication of user data.
class SyncMaintenanceSchedule {
  SyncMaintenanceSchedule(this.directory, {DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final Directory directory;
  final DateTime Function() _now;
  static final _running = <String>{};

  Future<int?> run(
      SyncClientBase client, Future<int> Function() cleanup) async {
    final identity = jsonEncode(client.syncIdentity);
    final digest = sha256.convert(utf8.encode(identity));
    final file = File('${directory.path}/replaced-cleanup-$digest.json');
    if (!_running.add(file.path)) return null;
    try {
      if (await file.exists()) {
        try {
          final saved = jsonDecode(await file.readAsString());
          final next =
              saved is Map<String, dynamic> ? saved['nextAttempt'] : null;
          // Ignore corrupt/far-future state rather than disabling GC forever.
          final remaining =
              next is int ? next - _now().millisecondsSinceEpoch : 0;
          if (remaining > 0 &&
              remaining <= const Duration(hours: 6).inMilliseconds) {
            return null;
          }
        } on FormatException {
          /* Rebuild damaged local schedule. */
        } on TypeError {/* Rebuild obsolete local schedule. */}
      }
      Future<void> postpone(Duration delay) => file.writeAsString(
          jsonEncode({'nextAttempt': _now().add(delay).millisecondsSinceEpoch}),
          flush: true);
      // Persist before starting so a failed/restarted session cannot hammer
      // the server on every sync. Only maintenance is deferred, never records.
      await postpone(const Duration(hours: 1));
      final result = await cleanup();
      await postpone(const Duration(hours: 6));
      return result;
    } finally {
      _running.remove(file.path);
    }
  }
}
