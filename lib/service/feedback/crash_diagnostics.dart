import 'dart:convert';
import 'dart:io';
import 'dart:ffi';
import 'package:anx_reader/service/feedback/crash_journal.dart';
import 'package:anx_reader/service/feedback/native_stack_diagnostics.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

/// Deliberately separate from general application logs, which may contain text,
/// URLs and credentials. Only the user-reviewed, allowlisted summary is shared.
class CrashDiagnostics {
  static const channel = MethodChannel('com.modu.reader/crash_diagnostics');
  static DateTime? _lastRecord;
  static int? _lastPhase;

  static Future<void> recordIndexState(int phase,
      {int done = 0, int total = 0, int model = 0}) async {
    final now = DateTime.now();
    if (phase == _lastPhase &&
        _lastRecord != null &&
        now.difference(_lastRecord!) < const Duration(seconds: 1)) {
      return;
    }
    _lastRecord = now;
    _lastPhase = phase;
    CrashJournal.indexState(phase, done, total, model);
    if (!Platform.isAndroid) return;
    try {
      await channel.invokeMethod<void>('indexState', {
        'phase': phase,
        'done': done,
        'total': total,
        'model': model
      }).timeout(const Duration(milliseconds: 500));
    } catch (_) {
      // Diagnostics must never fail a reading/indexing task.
    }
  }

  static Future<String> load() async {
    final local = CrashJournal.preview();
    if (Platform.isLinux) {
      return '$local\n${await NativeStackDiagnostics.linux()}';
    }
    try {
      final data = await channel
          .invokeMapMethod<String, dynamic>('read')
          .timeout(const Duration(seconds: 8));
      if (data == null) throw const FormatException('No diagnostic response');
      final native = Platform.isAndroid
          ? format(data)
          : Platform.isWindows
              ? NativeStackDiagnostics.windows(data)
              : (Platform.isIOS || Platform.isMacOS)
                  ? NativeStackDiagnostics.apple(data)
                  : '此平台原生堆栈接入不可用。Native diagnostics unsupported.';
      return '$local\n$native';
    } catch (_) {
      return '$local\n原生崩溃记录读取失败，仅附带本地应用记录，不代表没有发生崩溃。Native records unavailable.';
    }
  }

  static Future<String> loadEnvironment() async {
    if (!Platform.isAndroid) {
      final data = (await DeviceInfoPlugin()
              .deviceInfo
              .timeout(const Duration(seconds: 5)))
          .data;
      return 'Process ABI: ${Abi.current()}\n${formatDesktopEnvironment(Platform.operatingSystem, data)}';
    }
    final data = await channel
        .invokeMapMethod<String, dynamic>('environment')
        .timeout(const Duration(seconds: 5));
    return data == null ? '' : formatEnvironment(data);
  }

  static String formatDesktopEnvironment(String platform, Map data) {
    final keys = switch (platform) {
      'macos' => [
          'majorVersion',
          'minorVersion',
          'patchVersion',
          'model',
          'arch',
          'memorySize'
        ],
      'windows' => [
          'productName',
          'displayVersion',
          'buildNumber',
          'systemMemoryInMegabytes',
          'numberOfCores'
        ],
      'linux' => ['prettyName', 'versionId'],
      'ios' => ['systemName', 'systemVersion', 'model', 'modelName'],
      _ => <String>[],
    };
    final out = StringBuffer();
    for (final key in keys) {
      final item = data[key];
      if (item is int) out.writeln('$key: $item');
      if (item is String) out.writeln('$key: ${_display(item)}');
    }
    if (platform == 'ios' && data['utsname'] is Map) {
      out.writeln('machine: ${_display((data['utsname'] as Map)['machine'])}');
    }
    return out.toString().trim();
  }

  static String _display(Object? input) {
    if (input is! String) return 'unknown';
    final clean = input.replaceAll(RegExp(r'[^a-zA-Z0-9 ._,()+-]'), '');
    return clean.substring(0, clean.length.clamp(0, 100));
  }

  static String formatEnvironment(Map data) {
    String value(String key) {
      final input = data[key];
      if (input is! String) return 'unknown';
      // System-supplied display fields only; no identifiers, build fingerprints,
      // network interfaces, accounts or application preferences.
      return _display(input);
    }

    const allowedAbis = {'arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64'};
    final abis = data['abis'] is List
        ? (data['abis'] as List).where(allowedAbis.contains).join(', ')
        : 'unknown';
    return 'Android: ${value('android')} (API ${_number(data['sdk'])})\n'
        'Device: ${value('manufacturer')} ${value('model')}\n'
        'CPU ABI: $abis\nRAM: ${_number(data['ramMiB'])} MiB\n'
        'Installed Modu: ${value('version')}+${_number(data['build'])}';
  }

  static String format(Map data) {
    if (data['supported'] != true) {
      return '需要 Android 11 或更新版本。Requires Android 11+.';
    }
    final out = StringBuffer('Android system exit diagnostics (sanitized)\n');
    out.writeln('Android API: ${_number(data['sdk'])}');
    out.writeln('RSS/PSS are last samples in KiB, not exact crash-time peaks.');
    out.writeln(
        'No ordinary logs, book text, keys, memory dumps or full paths included.');
    final records =
        data['records'] is List ? data['records'] as List : const [];
    if (records.isEmpty) {
      out.writeln('没有可用的异常退出记录；不代表未发生崩溃。No retained abnormal exit records.');
    }
    const reasons = {
      2: 'SIGNALED',
      3: 'LOW_MEMORY',
      4: 'JAVA_CRASH',
      5: 'NATIVE_CRASH',
      6: 'ANR',
      7: 'INITIALIZATION_FAILURE',
      9: 'EXCESSIVE_RESOURCE_USAGE'
    };
    for (final entry in records.take(3).whereType<Map>()) {
      final time = _number(entry['time']);
      out.writeln(
          '\nExit: ${time >= 0 && time < 8640000000000000 ? DateTime.fromMillisecondsSinceEpoch(time, isUtc: true).toIso8601String() : "unknown"}');
      out.writeln(
          'Reason: ${reasons[entry['reason']] ?? 'UNKNOWN'}; status/signal: ${_number(entry['status'])}');
      out.writeln(
          'PSS: ${_number(entry['pss'])}; RSS: ${_number(entry['rss'])}');
      final state = entry['state'];
      if (state is Uint8List && state.length <= 128) {
        final value = ascii.decode(state, allowInvalid: true);
        if (RegExp(r'^modu-index-v1\|\d{1,12}\|[0-7]\|\d{1,9}\|\d{1,9}\|[0-4]$')
            .hasMatch(value)) {
          out.writeln(
              'Index checkpoint (build|phase|done|total|model): ${value.substring(14)}');
          out.writeln(
              'phase: 1=extract 2=prepare 3=embed 4=save 5=complete 6=failed 7=cancel; model: 1=MiniLM 2=BGE-en 3=BGE-zh 4=E5 0=other');
        }
      }
      final trace = entry['trace'];
      if (entry['reason'] == 5 &&
          trace is Uint8List &&
          trace.length <= 1048576) {
        out.writeln(nativeFrames(trace));
      } else {
        out.writeln(
            'Native stack unavailable (not retained, unreadable, over size limit or unsupported).');
      }
    }
    return out.toString();
  }

  static int _number(Object? value) => value is int ? value : -1;

  /// Android debuggerd tombstone.proto: only crashed-thread relative PCs,
  /// public library basenames and ELF build IDs. All other fields are skipped.
  static String nativeFrames(Uint8List bytes) {
    try {
      if (bytes.length > 1048576) throw const FormatException('Too large');
      final root = _Proto(bytes);
      final tid = root.integer(6);
      final out = <String>[];
      for (final threadEntry in root.messages(16)) {
        if (threadEntry.integer(1) != tid) continue;
        for (final thread in threadEntry.messages(2)) {
          for (final frame in thread.messages(4).take(32)) {
            final path = frame.string(6);
            final name = path.split('/').last;
            const publicLibraries = {
              'libonnxruntime.so',
              'libonnxruntime4j_jni.so',
              'libtokenizers_ffi.so',
              'libflutter.so',
              'libapp.so',
              'libc.so',
              'libm.so',
              'libdl.so',
              'libart.so',
              'libandroid_runtime.so',
              'libc++_shared.so',
              'libutils.so',
              'libbinder.so',
              'libEGL.so',
              'libGLESv2.so'
            };
            final library =
                publicLibraries.contains(name) ? name : '[library omitted]';
            final build = frame.string(8);
            final buildId = RegExp(r'^[a-fA-F0-9]{8,128}$').hasMatch(build)
                ? build
                : 'unknown';
            out.add(
                '#${out.length} pc ${frame.integer(1).toRadixString(16)} $library build=$buildId');
            if (out.length == 32) return out.join('\n');
          }
        }
      }
      return out.isEmpty
          ? 'Native stack unavailable in retained trace.'
          : out.join('\n');
    } catch (_) {
      return 'Native stack could not be decoded safely; raw trace omitted.';
    }
  }
}

/// Bounded protobuf wire reader, not a general decoder. No recursion, no field
/// contents in errors, and no UTF-8 decoding of unknown/private fields.
class _Proto {
  _Proto(this.bytes);
  final Uint8List bytes;
  Iterable<(int, Object)> fields() sync* {
    var position = 0;
    int varint() {
      var value = 0;
      for (var shift = 0; shift < 70; shift += 7) {
        if (position >= bytes.length) throw const FormatException('Truncated');
        final b = bytes[position++];
        value |= (b & 127) << shift;
        if (b < 128) return value;
      }
      throw const FormatException('Invalid varint');
    }

    while (position < bytes.length) {
      final tag = varint();
      if (tag <= 0) throw const FormatException('Invalid tag');
      final wire = tag & 7;
      if (wire == 0) {
        yield (tag >> 3, varint());
      } else if (wire == 2) {
        final length = varint();
        if (length < 0 || length > bytes.length - position) {
          throw const FormatException('Invalid length');
        }
        final slice = Uint8List.sublistView(bytes, position, position + length);
        position += length;
        yield (tag >> 3, slice);
      } else if (wire == 1 || wire == 5) {
        position += wire == 1 ? 8 : 4;
        if (position > bytes.length) throw const FormatException('Truncated');
      } else {
        throw const FormatException('Unsupported wire');
      }
    }
  }

  int integer(int number) {
    for (final field in fields()) {
      if (field.$1 == number && field.$2 is int) return field.$2 as int;
    }
    return 0;
  }

  Iterable<_Proto> messages(int number) sync* {
    for (final field in fields()) {
      if (field.$1 == number && field.$2 is Uint8List) {
        yield _Proto(field.$2 as Uint8List);
      }
    }
  }

  String string(int number) {
    for (final field in fields()) {
      if (field.$1 == number && field.$2 is Uint8List) {
        final value = field.$2 as Uint8List;
        if (value.length > 512) return '';
        return utf8.decode(value, allowMalformed: true);
      }
    }
    return '';
  }
}
