import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/service/plugins/plugin_catalog_signature.dart';

void main() {
  final algorithm = Ed25519();
  late SimpleKeyPair key;
  late List<int> publicKey;
  late PluginCatalogSignature verifier;
  const source = '{"schemaVersion":1,"plugins":[],"note":"审阅原文"}\n';

  setUpAll(() async {
    // This deterministic key belongs only to these isolated fixtures.
    key = await algorithm.newKeyPairFromSeed(List.generate(32, (i) => i));
    publicKey = (await key.extractPublicKey()).bytes;
    verifier = PluginCatalogSignature(
        publicKeys: {PluginCatalogSignature.keyId: publicKey});
  });

  Future<Map<String, dynamic>> signedBytes(List<int> payload) async {
    final signature = await algorithm.sign(payload, keyPair: key);
    return {
      'schemaVersion': 1,
      'algorithm': 'Ed25519',
      'keyId': PluginCatalogSignature.keyId,
      'payload': base64Encode(payload),
      'signature': base64Encode(signature.bytes),
    };
  }

  Future<Map<String, dynamic>> signed([String payload = source]) =>
      signedBytes(utf8.encode(payload));

  final invalid = throwsA(isA<FormatException>()
      .having(
          (e) => e.message, 'fixed message', 'Invalid plugin catalog signature')
      .having((e) => e.source, 'no content in diagnostics', isNull));

  test('verifies the exact UTF-8 payload bytes before returning catalog data',
      () async {
    expect(
        await verifier.decode(jsonEncode(await signed())), jsonDecode(source));
    final reformatted = await signed();
    reformatted['payload'] = base64Encode(utf8.encode(source.trim()));
    await expectLater(verifier.decode(jsonEncode(reformatted)), invalid);
  });

  test('default public key verifies the OpenSSL-signed project catalog fixture',
      () async {
    final raw =
        await File('test/fixtures/plugins/catalog.signed.json').readAsString();
    final result = await PluginCatalogSignature().decode(raw);
    expect(result['schemaVersion'], 1);
    expect(result['repository'], 'https://github.com/sobranie2406/modu-plugin');
    expect((result['plugins'] as List).map((item) => item['id']).toSet(), {
      'com.modu.private-books',
      'com.modu.text-tools',
      'com.example.prompt-pack'
    });
  });

  test('modified payload and modified signature are rejected', () async {
    final payload = await signed();
    payload['payload'] =
        base64Encode(utf8.encode(source.replaceFirst('审阅', '更改')));
    await expectLater(verifier.decode(jsonEncode(payload)), invalid);
    final signature = await signed();
    final bytes = base64Decode(signature['signature'] as String);
    bytes[0] ^= 1;
    signature['signature'] = base64Encode(bytes);
    await expectLater(verifier.decode(jsonEncode(signature)), invalid);
  });

  test('a valid signature from another key is rejected', () async {
    final otherKey = await algorithm.newKeyPairFromSeed(List.filled(32, 9));
    final wrongVerifier = PluginCatalogSignature(publicKeys: {
      PluginCatalogSignature.keyId: (await otherKey.extractPublicKey()).bytes,
    });
    await expectLater(
        wrongVerifier.decode(jsonEncode(await signed())), invalid);
  });

  for (final entry in <String, Object?>{
    'schemaVersion': 1.0,
    'algorithm': 'ed25519',
    'keyId': 'unknown-key',
    'payload': 7,
    'signature': base64Encode(List.filled(63, 0)),
    'extra': 'unrecognized',
  }.entries) {
    test('rejects unsupported envelope ${entry.key}', () async {
      final envelope = await signed();
      envelope[entry.key] = entry.value;
      await expectLater(verifier.decode(jsonEncode(envelope)), invalid);
    });
  }

  test('rejects key IDs with control or path characters', () async {
    for (final id in ['../modu', 'modu\nplugins', 'x' * 65, 'MODU']) {
      final envelope = await signed();
      envelope['keyId'] = id;
      await expectLater(verifier.decode(jsonEncode(envelope)), invalid);
    }
  });

  test('rejects noncanonical base64 rather than normalizing signed metadata',
      () async {
    for (final field in ['payload', 'signature']) {
      final envelope = await signed();
      envelope[field] = (envelope[field] as String).replaceAll('=', '');
      await expectLater(verifier.decode(jsonEncode(envelope)), invalid);
    }
  });

  test('rejects unsigned plain catalogs and malformed envelopes', () async {
    for (final envelope in [source, '[]', 'null', '{', '{}']) {
      await expectLater(verifier.decode(envelope), invalid);
    }
  });

  test('authenticated payload still must be valid UTF-8 and a schema-1 catalog',
      () async {
    await expectLater(
        verifier.decode(jsonEncode(await signedBytes([0xff]))), invalid);
    for (final payload in [
      '{',
      '[]',
      'null',
      '{"schemaVersion":2,"plugins":[]}',
      '{"schemaVersion":1.0,"plugins":[]}',
      '{"schemaVersion":1,"plugins":{}}'
    ]) {
      await expectLater(
          verifier.decode(jsonEncode(await signed(payload))), invalid);
    }
  });

  test('enforces envelope and decoded-payload byte limits', () async {
    final envelope = jsonEncode(await signed());
    await expectLater(
        verifier
            .decode(' ' * PluginCatalogSignature.maxEnvelopeBytes + envelope),
        invalid);
    final payload = jsonEncode({
      'schemaVersion': 1,
      'plugins': [],
      'note': '界' * (PluginCatalogSignature.maxPayloadBytes ~/ 3 + 1),
    });
    await expectLater(
        verifier.decode(jsonEncode(await signed(payload))), invalid);
    final allowed = jsonEncode({
      'schemaVersion': 1,
      'plugins': [],
      'note': 'x' * (PluginCatalogSignature.maxPayloadBytes - 512),
    });
    expect((await verifier.decode(jsonEncode(await signed(allowed))))['note'],
        jsonDecode(allowed)['note']);
  });

  test(
      'copies supplied public keys so later caller mutations cannot change trust',
      () async {
    final bytes = publicKey.toList();
    final keys = {PluginCatalogSignature.keyId: bytes};
    final copied = PluginCatalogSignature(publicKeys: keys);
    bytes.fillRange(0, bytes.length, 0);
    keys.clear();
    expect(await copied.decode(jsonEncode(await signed())), jsonDecode(source));
  });
}
