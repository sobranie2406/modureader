import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/service/dictionary/local_dictionary.dart';
import 'package:modu_reader/service/plugins/plugin_http_client.dart';
import 'package:modu_reader/service/plugins/plugin_network_guard.dart';

Matcher _fails(String code) =>
    throwsA(isA<DictionaryFailure>().having((e) => e.code, 'code', code));

void main() {
  late ServerSocket server;
  late PluginGuardResult target;
  final peers = <Socket>[];

  setUp(() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    // Only the connector is exercised: production callers first run the
    // public-address guard, which deliberately refuses this test loopback.
    target = PluginGuardResult(
        uri: Uri.parse('https://localhost:${server.port}/article'),
        addresses: await InternetAddress.lookup('localhost',
            type: InternetAddressType.IPv4),
        headers: const {});
  });
  tearDown(() async {
    for (final peer in peers) {
      peer.destroy();
    }
    peers.clear();
    await server.close();
  });

  Future<Socket> accept() async {
    final peer = await server.first;
    peers.add(peer);
    return peer;
  }

  test('sends TLS ClientHello with the original host, never a plaintext GET',
      () async {
    final incoming = accept();
    final task = await connectPluginTls(
        target: target,
        timeout: const Duration(seconds: 2),
        isCancelled: () => false);
    final rejected =
        expectLater(task.socket, throwsA(isA<HandshakeException>()));
    final peer = await incoming;
    final hello = await peer.first;
    expect(hello.first, 22); // TLS handshake record.
    expect(latin1.decode(hello), contains('localhost')); // SNI.
    expect(latin1.decode(hello), isNot(startsWith('GET ')));
    peer.destroy();
    await rejected;
  });

  test('cancels an unfinished TLS handshake promptly', () async {
    final incoming = accept();
    final task = await connectPluginTls(
        target: target,
        timeout: const Duration(seconds: 2),
        isCancelled: () => false);
    final cancelled = expectLater(task.socket, _fails('cancelled'));
    final peer = await incoming;
    await peer.first;
    task.cancel();
    await cancelled.timeout(const Duration(milliseconds: 200));
  });

  test('bounds a TLS peer that never completes its handshake', () async {
    final incoming = accept();
    final task = await connectPluginTls(
        target: target,
        timeout: const Duration(milliseconds: 60),
        isCancelled: () => false);
    final expired = expectLater(task.socket, _fails('timeout'));
    await incoming;
    await expired;
  });

  test('refuses a pinned address with unrelated TLS hostname metadata',
      () async {
    final mismatched = PluginGuardResult(
        uri: Uri.parse('https://different.invalid:${server.port}/'),
        addresses: target.addresses,
        headers: const {});
    await expectLater(
        connectPluginTls(
            target: mismatched,
            timeout: const Duration(seconds: 1),
            isCancelled: () => false),
        _fails('configuration'));
  });

  test('does not start a connection after cancellation', () async {
    await expectLater(
        connectPluginTls(
            target: target,
            timeout: const Duration(seconds: 1),
            isCancelled: () => true),
        _fails('cancelled'));
  });

  test('rejects an untrusted server certificate', () async {
    final context = SecurityContext()
      ..useCertificateChain('test/fixtures/plugins/tls/localhost-cert.pem')
      ..usePrivateKey('test/fixtures/plugins/tls/localhost-key.pem');
    final tlsServer =
        await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, context);
    final subscription = tlsServer.listen(peers.add, onError: (Object _) {});
    try {
      final task = await connectPluginTls(
          target: PluginGuardResult(
              uri: Uri.parse('https://localhost:${tlsServer.port}/'),
              addresses: target.addresses,
              headers: const {}),
          timeout: const Duration(seconds: 2),
          isCancelled: () => false);
      await expectLater(task.socket, throwsA(isA<HandshakeException>()));
    } finally {
      await subscription.cancel();
      await tlsServer.close();
    }
  });
}
