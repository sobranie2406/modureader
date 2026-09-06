import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A second allowlist boundary before any native data reaches the preview.
/// Raw system reports, symbols, addresses and user-controlled paths stay out.
class NativeStackDiagnostics {
  static const modules = {
    'Modu',
    'Runner',
    'App',
    'Flutter',
    'FlutterMacOS',
    'onnxruntime',
    'flutter_onnxruntime',
    'libonnxruntime.dylib',
    'tokenizers_ffi',
    'libtokenizers_ffi.dylib',
    'libsystem_kernel.dylib',
    'libsystem_pthread.dylib',
    'libsystem_c.dylib',
    'libsystem_malloc.dylib',
    'libc++abi.dylib',
    'libc++.1.dylib',
    'libobjc.A.dylib',
    'libdyld.dylib',
    'dyld',
    'Foundation',
    'CoreFoundation',
    'AppKit',
    'UIKitCore',
    'modu.exe',
    'flutter_windows.dll',
    'onnxruntime.dll',
    'tokenizers_ffi.dll',
    'ntdll.dll',
    'kernel32.dll',
    'kernelbase.dll',
    'ucrtbase.dll',
    'vcruntime140.dll',
    'vcruntime140_1.dll',
    'msvcp140.dll',
    'modu',
    'libflutter_linux_gtk.so',
    'libapp.so',
    'libonnxruntime.so',
    'libtokenizers_ffi.so',
    'libc.so.6',
    'libpthread.so.0',
    'libm.so.6',
    'libstdc++.so.6',
    'libgcc_s.so.1',
    'ld-linux-x86-64.so.2',
    'ld-linux-aarch64.so.1',
  };

  static String module(Object? name) =>
      modules.contains(name) ? '$name' : 'omitted';
  static int number(Object? value) => value is int && value >= 0 ? value : -1;
  static String _time(Object? value) {
    final n = number(value);
    return n >= 0 && n < 8640000000000000
        ? DateTime.fromMillisecondsSinceEpoch(n, isUtc: true).toIso8601String()
        : 'unknown';
  }

  static String apple(Map data) {
    final out =
        StringBuffer('Apple MetricKit native crash diagnostics (sanitized)\n');
    out.writeln(
        '系统报告可能延迟送达；报告区间不是精确崩溃时间。System delivery may be delayed; reporting interval is not crash time.');
    final records =
        data['records'] is List ? data['records'] as List : const [];
    if (records.isEmpty) {
      out.writeln('尚无系统送达的原生崩溃报告，不代表没有崩溃。No delivered native crash reports.');
    }
    for (final record in records.take(3).whereType<Map>()) {
      out.writeln(
          'Period: ${_time(record['periodStart'])} — ${_time(record['periodEnd'])}');
      final version = record['version'];
      if (version is String &&
          RegExp(r'^[0-9A-Za-z.+-]{1,60}$').hasMatch(version)) {
        out.writeln('Crash app version: $version');
      }
      out.writeln(
          'Exception type: ${number(record['code'])}; signal: ${number(record['signal'])}');
      final frames =
          record['frames'] is List ? record['frames'] as List : const [];
      var index = 0;
      for (final frame in frames.take(32).whereType<Map>()) {
        final offset = number(frame['offset']);
        if (offset < 0) continue;
        final build = frame['buildId'];
        final safeBuild = build is String &&
                RegExp(r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$')
                    .hasMatch(build)
            ? build
            : 'unknown';
        out.writeln(
            '#${index++} ${module(frame['module'])} +0x${offset.toRadixString(16)} binaryUUID=$safeBuild');
      }
      if (index == 0) {
        out.writeln('No usable faulting-thread frames delivered.');
      }
    }
    return out.toString();
  }

  static String windows(Map data) {
    final out =
        StringBuffer('Windows native exception diagnostics (sanitized)\n');
    if (data['active'] != true) {
      out.writeln('当前进程原生记录器不可用。Native recorder inactive in this process.');
    }
    final trace = data['trace'];
    if (trace is! String ||
        trace.length > 32768 ||
        !trace.startsWith('modu-native-v1\n')) {
      out.writeln('无可用的上次原生异常记录，不代表没有崩溃。No retained native exception.');
      return out.toString();
    }
    var index = 0;
    for (final line in const LineSplitter().convert(trace).take(100)) {
      final code = RegExp(r'^code=([a-fA-F0-9]{1,8})$').firstMatch(line);
      final time = RegExp(r'^time=([0-9]{1,16})$').firstMatch(line);
      final build = RegExp(r'^build=([0-9]{1,12})$').firstMatch(line);
      if (code != null) out.writeln('Exception: 0x${code[1]}');
      if (time != null) {
        out.writeln('Crash time: ${_time(int.tryParse(time[1]!))}');
      }
      if (build != null) out.writeln('Crash app build: ${build[1]}');
      final frame = RegExp(
              r'^frame=([a-z0-9_.]{1,60})\|([a-fA-F0-9]{1,16})\|([a-fA-F0-9-]{1,40})$')
          .firstMatch(line);
      if (frame != null && index < 32) {
        out.writeln(
            '#${index++} ${module(frame[1])} +0x${frame[2]} image-signature=${frame[3]}');
      }
    }
    if (index == 0) {
      out.writeln('Exception recorded but stack unwinding was unavailable.');
    }
    out.writeln(
        'Best effort: OS force-kill, fail-fast and damaged stacks may bypass this handler. No minidump included.');
    return out.toString();
  }

  static List<String> linuxArguments(String executable) => [
        '--no-pager',
        '-1',
        '--since=7 days ago',
        'info',
        'COREDUMP_EXE=$executable',
      ];

  static Future<String> linux() async {
    try {
      final executable = ['/usr/bin/coredumpctl', '/bin/coredumpctl']
          .where((path) => File(path).existsSync())
          .firstOrNull;
      if (executable == null) return linuxUnavailable;
      final process = await Process.start(
          executable, linuxArguments(Platform.resolvedExecutable),
          // No shell, pager, debugger, elevation, dump extraction or network lookup.
          includeParentEnvironment: false,
          environment: {
            'LC_ALL': 'C',
            'SYSTEMD_COLORS': '0',
            'SYSTEMD_PAGER': '',
            'DEBUGINFOD_URLS': ''
          });
      final output = await boundedOutput(process);
      return output == null ? linuxUnavailable : linuxSummary(output);
    } catch (_) {
      return linuxUnavailable;
    }
  }

  static const linuxUnavailable =
      'Linux 原生堆栈不可用：需要 systemd-coredump 保留本应用记录及当前用户的读取权限；也可能尚无记录。不会启用系统 core dump 或申请管理员权限。No accessible systemd native crash record.';

  /// Bounds both pipes (including discarded stderr), time, and retained bytes.
  /// Never return partial output after a failure, or echo stderr with user paths.
  static Future<String?> boundedOutput(
    Process process, {
    int limit = 262144,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final bytes = BytesBuilder(copy: false);
    var size = 0;
    var failed = false;
    final finished = Completer<void>();
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    void stop() {
      failed = true;
      process.kill(ProcessSignal.sigkill);
      if (!finished.isCompleted) finished.complete();
    }

    final stdout = process.stdout.listen((chunk) {
      size += chunk.length;
      if (size > limit) {
        stop();
        return;
      }
      bytes.add(chunk);
    }, onError: (_) => stop(), onDone: stdoutDone.complete);
    final stderr = process.stderr.listen((chunk) {
      size += chunk.length;
      if (size > limit) stop();
    }, onError: (_) => stop(), onDone: stderrDone.complete);
    final timer = Timer(timeout, stop);
    final exit = process.exitCode.then((code) async {
      if (code != 0) failed = true;
      // exitCode may precede delivery of the last pipe bytes.
      await Future.wait([stdoutDone.future, stderrDone.future]);
      if (!finished.isCompleted) finished.complete();
    }).catchError((_) => stop());
    await finished.future;
    timer.cancel();
    await stdout.cancel();
    await stderr.cancel();
    if (!stdoutDone.isCompleted) stdoutDone.complete();
    if (!stderrDone.isCompleted) stderrDone.complete();
    // The exit future owns its error handler even after a timeout.
    unawaited(exit);
    return failed ? null : utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  static String linuxSummary(String input) {
    if (input.length > 262144) return linuxUnavailable;
    final out = StringBuffer(
        'Linux systemd native crash stack (sanitized; latest matching executable within 7 days)\n');
    var index = 0;
    for (final line in const LineSplitter().convert(input)) {
      final signal =
          RegExp(r'^\s*Signal:\s*(\d{1,3})(?:\s|$)').firstMatch(line);
      if (signal != null) out.writeln('Signal: ${signal[1]}');
      // Do not export absolute PCs or arbitrary symbols before the module offset.
      final frame = RegExp(
              r'^\s*#\d+\s+0x[a-fA-F0-9]+\s+.*\(([^() ]+)\s+\+\s+0x([a-fA-F0-9]{1,16})\)\s*$')
          .firstMatch(line);
      if (frame != null && index < 32) {
        out.writeln('#${index++} ${module(frame[1])} +0x${frame[2]}');
      }
      // Keep just the first stack provided by systemd; thread IDs are omitted.
      if (index > 0 && line.contains('Stack trace of thread')) break;
    }
    if (index == 0) {
      out.writeln(
          'System record has no usable stack frames; raw report omitted.');
    }
    out.writeln(
        'System-supplied first thread stack; faulting-thread attribution may be unavailable. No core memory or raw report included.');
    return out.toString();
  }
}
