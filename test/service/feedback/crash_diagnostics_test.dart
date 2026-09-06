import 'dart:convert';
import 'dart:typed_data';
import 'package:anx_reader/service/feedback/crash_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> vint(int value) {
  final out = <int>[];
  while (value >= 128) {
    out.add((value & 127) | 128);
    value >>= 7;
  }
  return [...out, value];
}

List<int> number(int field, int value) => [...vint(field << 3), ...vint(value)];
List<int> blob(int field, List<int> bytes) =>
    [...vint((field << 3) | 2), ...vint(bytes.length), ...bytes];
List<int> text(int field, String value) => blob(field, utf8.encode(value));

void main() {
  test('native trace retains only relative PC, library basename and build id',
      () {
    final frame = [
      ...number(1, 1234),
      ...text(4, 'private function /book/api_key'),
      ...text(6, '/data/user/0/private/libonnxruntime.so'),
      ...text(8, 'abcdef0123456789')
    ];
    final thread = [
      ...number(1, 42),
      ...text(2, 'private title'),
      ...blob(4, frame),
      ...text(5, 'sk-secret memory')
    ];
    final trace = Uint8List.fromList([
      ...number(6, 42),
      ...text(14, 'secret abort message'),
      ...blob(16, [...number(1, 42), ...blob(2, thread)]),
      ...text(18, 'private logcat')
    ]);
    final output = CrashDiagnostics.nativeFrames(trace);
    expect(output, contains('pc 4d2 libonnxruntime.so build=abcdef0123456789'));
    for (final secret in [
      'private',
      'secret',
      'abort',
      'logcat',
      '/data/',
      'function'
    ]) {
      expect(output, isNot(contains(secret)));
    }
  });
  test('malformed and oversized native traces fail closed', () {
    for (final bytes in [
      Uint8List.fromList([128]),
      Uint8List.fromList([130, 1, 127]),
      Uint8List(1048577)
    ]) {
      expect(CrashDiagnostics.nativeFrames(bytes), contains('omitted'));
    }
  });
  test('Android diagnostics omit untrusted fields and summaries', () {
    final result = CrashDiagnostics.format({
      'supported': true,
      'sdk': 36,
      'serial': 'SECRET_SERIAL',
      'records': [
        {
          'time': 1000,
          'reason': 3,
          'status': 0,
          'rss': 100,
          'pss': 50,
          'description': 'SECRET_KEY',
          'state': Uint8List.fromList(utf8.encode('SECRET_BOOK'))
        }
      ]
    });
    expect(result, contains('LOW_MEMORY'));
    expect(result, isNot(contains('SECRET')));
  });
  test('known index checkpoint survives process exit without book identifiers',
      () {
    final result = CrashDiagnostics.format({
      'supported': true,
      'sdk': 36,
      'records': [
        {
          'time': 1000,
          'reason': 5,
          'state':
              Uint8List.fromList(ascii.encode('modu-index-v1|6331|3|16|200|3'))
        }
      ]
    });
    expect(result, contains('6331|3|16|200|3'));
  });
  test(
      'all-platform environment export allowlists fields and excludes identifiers',
      () {
    final windows = CrashDiagnostics.formatDesktopEnvironment('windows', {
      'productName': 'Windows 11',
      'buildNumber': 26100,
      'deviceId': 'SECRET',
      'computerName': 'SECRET',
      'registeredOwner': 'SECRET',
      'productId': 'SECRET'
    });
    final mac = CrashDiagnostics.formatDesktopEnvironment('macos', {
      'model': 'Mac16,1',
      'arch': 'arm64',
      'memorySize': 17179869184,
      'hostName': 'SECRET',
      'systemGUID': 'SECRET'
    });
    final ios = CrashDiagnostics.formatDesktopEnvironment('ios', {
      'systemVersion': '18.5',
      'name': 'SECRET',
      'identifierForVendor': 'SECRET',
      'utsname': {'machine': 'iPhone16,1', 'nodename': 'SECRET'}
    });
    final android = CrashDiagnostics.formatEnvironment({
      'android': '16',
      'sdk': 36,
      'manufacturer': 'vivo',
      'model': 'V2301A',
      'abis': ['arm64-v8a', 'SECRET'],
      'ramMiB': 12000,
      'version': '0.1.0-beta.3',
      'build': 6331,
      'serial': 'SECRET'
    });
    expect('$windows$mac$ios$android', isNot(contains('SECRET')));
    expect(windows, contains('Windows 11'));
    expect(mac, contains('Mac16,1'));
    expect(ios, contains('iPhone16,1'));
    expect(android, contains('Android: 16 (API 36)'));
  });
}
