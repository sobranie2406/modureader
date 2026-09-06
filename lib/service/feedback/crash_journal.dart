import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Small, local-only, allowlisted journal shared by every native platform.
/// Never pass exception messages, user input, paths, URLs or preferences here.
class CrashJournal {
  static File? _file;
  static final List<Map<String, dynamic>> _events = [];
  static bool _closed = false;
  static String _version = 'unknown';

  static Future<void> initialize(
      {Directory? directory, String version = 'unknown'}) async {
    if (_file != null) return;
    _version = RegExp(r'^[a-zA-Z0-9.+-]{1,60}$').hasMatch(version)
        ? version
        : 'unknown';
    try {
      final root = directory ??
          Directory(
              '${(await getApplicationSupportDirectory()).path}/modu_crash_diagnostics');
      await root.create(recursive: true);
      _file = File('${root.path}/session.json');
      if (_file!.existsSync() && _file!.lengthSync() <= 32768) {
        final previous = jsonDecode(_file!.readAsStringSync());
        if (previous is Map && previous['events'] is List) {
          _events.addAll((previous['events'] as List)
              .whereType<Map>()
              .take(16)
              .map((e) => Map<String, dynamic>.from(e)));
          if (previous['closed'] != true) {
            _add('previous_session_unconfirmed');
          }
        }
      }
      _closed = false;
      _add('session_start');
    } catch (_) {
      // Recording must not prevent startup, including malformed old files.
      _events.clear();
      _add('session_start');
    }
  }

  static void recordError(Object error, StackTrace? stack,
      {bool framework = false}) {
    final type = error.runtimeType.toString();
    final locations = RegExp(
            r'(?:package:(?:anx_reader|flutter)/[a-zA-Z0-9_/]+\.dart|dart:[a-zA-Z0-9_/]+)(?::\d+){1,2}')
        .allMatches(stack?.toString() ?? '')
        .where((m) => m.group(0)!.length <= 200)
        .take(12)
        .map((m) => m.group(0)!)
        .toList();
    _add(framework ? 'flutter_error' : 'unhandled_error', {
      'type': RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,60}$').hasMatch(type)
          ? type
          : 'Error',
      'frames': locations,
    });
  }

  static void indexState(int phase, int done, int total, int model) => _add(
      'index_checkpoint',
      {'phase': phase, 'done': done, 'total': total, 'model': model});

  static void closeSession() {
    _closed = true;
    _add('session_closed');
  }

  static void _add(String event, [Map<String, dynamic> fields = const {}]) {
    if (_file == null) return;
    _events.add({
      'event': event,
      'time': DateTime.now().toUtc().toIso8601String(),
      'version': _version,
      ...fields
    });
    while (_events.length > 16) {
      _events.removeAt(0);
    }
    try {
      final temporary = File('${_file!.path}.tmp');
      var payload = jsonEncode({'closed': _closed, 'events': _events});
      while (utf8.encode(payload).length > 30000 && _events.length > 1) {
        _events.removeAt(0);
        payload = jsonEncode({'closed': _closed, 'events': _events});
      }
      temporary.writeAsStringSync(payload, flush: true);
      temporary.renameSync(_file!.path);
    } catch (_) {}
  }

  static String preview() {
    final out = StringBuffer('Local app diagnostics (all platforms)\n');
    out.writeln(
        'An unconfirmed prior session may mean a crash, force-stop or normal OS reclaim; it is not proof of a crash.');
    if (_events.isEmpty) out.writeln('No retained local diagnostic events.');
    const allowed = {
      'session_start',
      'session_closed',
      'previous_session_unconfirmed',
      'index_checkpoint',
      'flutter_error',
      'unhandled_error'
    };
    for (final event in _events) {
      if (!allowed.contains(event['event'])) continue;
      final time = event['time'];
      if (time is! String || !RegExp(r'^[0-9TZ:.+-]{1,35}$').hasMatch(time)) {
        continue;
      }
      out.writeln('$time ${event['event']}');
      final version = event['version'];
      if (version is String &&
          RegExp(r'^[a-zA-Z0-9.+-]{1,60}$').hasMatch(version)) {
        out.writeln('Modu=$version');
      }
      final type = event['type'];
      if (type is String &&
          RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,60}$').hasMatch(type)) {
        out.writeln('type=$type');
      }
      for (final key in ['phase', 'done', 'total', 'model']) {
        if (event[key] is int) out.write('$key=${event[key]} ');
      }
      out.writeln();
      if (event['frames'] is List) {
        for (final frame in (event['frames'] as List).take(12)) {
          if (frame is String &&
              RegExp(r'^(?:package:(?:anx_reader|flutter)/[a-zA-Z0-9_/]+\.dart|dart:[a-zA-Z0-9_/]+)(?::\d+){1,2}$')
                  .hasMatch(frame)) {
            out.writeln(frame);
          }
        }
      }
    }
    return out.toString();
  }

  /// Test-only process restart boundary: intentionally does not mark a clean exit.
  static void resetForTesting() {
    _file = null;
    _events.clear();
    _closed = false;
  }
}
