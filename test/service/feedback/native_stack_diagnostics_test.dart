import 'dart:io';
import 'package:anx_reader/service/feedback/native_stack_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Apple summary contains only fault metadata and bounded safe frames',
      () {
    final report = NativeStackDiagnostics.apple({
      'records': [
        {
          'periodStart': 1000,
          'periodEnd': 2000,
          'version': '0.1.0-beta.3',
          'code': 1,
          'signal': 11,
          'exceptionReason': 'SECRET_BOOK',
          'deviceId': 'SECRET_ID',
          'frames': List.generate(
              50,
              (i) => {
                    'offset': i,
                    'module':
                        i == 0 ? 'onnxruntime' : '/Users/SECRET/secret.dylib',
                    'buildId': i == 0
                        ? 'AABBCCDD-1122-3344-5566-77889900AABB'
                        : 'SECRET',
                    'symbol': 'SECRET',
                    'registers': 'SECRET',
                    'address': 123456789,
                  }),
        }
      ],
    });
    expect(report, contains('onnxruntime +0x0'));
    expect(report, contains('binaryUUID=AABBCCDD'));
    expect(report, contains('#31'));
    expect(report, isNot(contains('#32')));
    expect(report, isNot(contains('SECRET')));
    expect(report, isNot(contains('123456789')));
    expect(report, contains('reporting interval is not crash time'));
  });

  test('Apple malformed input and missing records fail closed', () {
    expect(NativeStackDiagnostics.apple({'records': 'SECRET'}),
        contains('No delivered'));
    final result = NativeStackDiagnostics.apple({
      'records': [
        {
          'periodStart': 999999999999999999,
          'version': '/SECRET/path',
          'code': 'SECRET',
          'frames': [
            null,
            'SECRET',
            {'offset': -1},
            {'offset': 'SECRET'}
          ],
        }
      ]
    });
    expect(result, isNot(contains('SECRET')));
    expect(result, contains('No usable'));
  });

  test(
      'Windows fixed record filters keys, paths, function names and invalid data',
      () {
    final report = NativeStackDiagnostics.windows({
      'active': true,
      'trace': 'modu-native-v1\ncode=c0000005\ntime=1000\nbuild=6330\n'
          'frame=onnxruntime.dll|123|aa-bb\n'
          'frame=secret.dll|456|cc-dd\n'
          'frame=/Users/SECRET|789|aa\n'
          'frame=onnxruntime.dll|SECRET|aa\n'
          'registers=SECRET\napiKey=SECRET\nsymbol=SECRET\n'
    });
    expect(report, contains('Exception: 0xc0000005'));
    expect(report, contains('Crash app build: 6330'));
    expect(report, contains('onnxruntime.dll +0x123'));
    expect(report, contains('omitted +0x456'));
    expect(report, isNot(contains('SECRET')));
    expect(report, isNot(contains('secret.dll')));
  });

  test('Windows recorder status, truncation and size limits are explicit', () {
    expect(NativeStackDiagnostics.windows({'active': false}),
        contains('inactive'));
    expect(NativeStackDiagnostics.windows({'trace': 'SECRET'}),
        contains('No retained'));
    expect(
        NativeStackDiagnostics.windows(
            {'trace': 'modu-native-v1\n${'x' * 32768}'}),
        contains('No retained'));
    expect(
        NativeStackDiagnostics.windows(
            {'trace': 'modu-native-v1\ncode=c0000005\n'}),
        contains('unwinding was unavailable'));
  });

  test('Linux query only asks for metadata of this exact executable', () {
    final arguments =
        NativeStackDiagnostics.linuxArguments('/private/book;SECRET');
    expect(arguments, contains('COREDUMP_EXE=/private/book;SECRET'));
    expect(arguments, contains('info'));
    for (final forbidden in ['dump', 'debug', '--output', 'sudo']) {
      expect(arguments, isNot(contains(forbidden)));
    }
  });

  test(
      'Linux strips command line, raw PCs, user paths, symbols and other threads',
      () {
    final output = NativeStackDiagnostics.linuxSummary('''
           UID: 1000 (SECRET_PERSON)
    Executable: /home/SECRET/modu
  Command Line: modu SECRET_BOOK sk-SECRET
        Signal: 11 (SEGV)
       Message: Process dumped core. SECRET_TEXT
                Stack trace of thread 100:
                #0 0x0000deadbeef1234 SECRET_SYMBOL (libonnxruntime.so + 0x1234)
                #1 0x0000deadbeef5678 SECRET_SYMBOL (/private/SECRET.so + 0xab)
                Stack trace of thread 101:
                #0 0x0000deadbeef9999 SECRET_SYMBOL (libc.so.6 + 0xcccc)
''');
    expect(output, contains('Signal: 11'));
    expect(output, contains('libonnxruntime.so +0x1234'));
    expect(output, contains('omitted +0xab'));
    for (final private in [
      'SECRET',
      'deadbeef',
      'cccc',
      '/home/',
      '/private/'
    ]) {
      expect(output, isNot(contains(private)));
    }
  });

  test('Linux malformed or oversized report does not echo raw contents', () {
    expect(NativeStackDiagnostics.linuxSummary('SECRET'),
        isNot(contains('SECRET')));
    expect(NativeStackDiagnostics.linuxSummary('x' * 262145),
        NativeStackDiagnostics.linuxUnavailable);
  });

  // Pipe handling tested with harmless subprocesses, no system journal access.
  test(
      'bounded subprocess drains complete stdout, discards stderr, checks exit',
      () async {
    final good = await Process.start(
        '/bin/sh', ['-c', 'printf safe; printf PRIVATE >&2']);
    expect(await NativeStackDiagnostics.boundedOutput(good), 'safe');
    final bad =
        await Process.start('/bin/sh', ['-c', 'printf PRIVATE; exit 1']);
    expect(await NativeStackDiagnostics.boundedOutput(bad), isNull);
  }, skip: Platform.isWindows);

  test('bounded subprocess kills on excess output or timeout', () async {
    final big = await Process.start('/bin/sh', ['-c', 'printf 123456789']);
    expect(await NativeStackDiagnostics.boundedOutput(big, limit: 4), isNull);
    final slow = await Process.start('/bin/sleep', ['10']);
    final watch = Stopwatch()..start();
    expect(
        await NativeStackDiagnostics.boundedOutput(slow,
            timeout: const Duration(milliseconds: 50)),
        isNull);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  }, skip: Platform.isWindows);
}
