import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Only a signature made by the project can extend the reviewed catalog.
class PluginCatalogSignature {
  PluginCatalogSignature({Map<String, List<int>>? publicKeys})
      : _publicKeys = Map.unmodifiable({
          for (final entry
              in (publicKeys ?? {keyId: base64Decode(publicKeyBase64)}).entries)
            entry.key: List<int>.unmodifiable(entry.value),
        });

  static const keyId = 'modu-plugins-2026-01';
  static const publicKeyBase64 = 't8p8Y8jV/yr7BDJCUeqpSdrRmRDec/spYO8V8FktTWM=';
  static const maxEnvelopeBytes = 256 * 1024;
  static const maxPayloadBytes = 192 * 1024;
  static const _invalid = FormatException('Invalid plugin catalog signature');
  final Map<String, List<int>> _publicKeys;

  Future<Map<String, dynamic>> decode(String envelope) async {
    try {
      if (envelope.length > maxEnvelopeBytes ||
          utf8.encode(envelope).length > maxEnvelopeBytes) {
        throw _invalid;
      }
      final value = jsonDecode(envelope);
      if (value is! Map<String, dynamic> ||
          value.length != 5 ||
          value['schemaVersion'] is! int ||
          value['schemaVersion'] != 1 ||
          value['algorithm'] != 'Ed25519' ||
          value['keyId'] is! String ||
          !RegExp(r'^[a-z][a-z0-9-]{0,63}$').hasMatch(value['keyId'])) {
        throw _invalid;
      }
      final key = _publicKeys[value['keyId']];
      if (key == null || key.length != 32) throw _invalid;
      final payload = _bytes(value['payload'], maxPayloadBytes);
      final signature = _bytes(value['signature'], 64);
      if (signature.length != 64 ||
          !await Ed25519().verify(
            payload,
            signature: Signature(signature,
                publicKey: SimplePublicKey(key, type: KeyPairType.ed25519)),
          )) {
        throw _invalid;
      }
      // Decode catalog data only after authenticating its exact UTF-8 bytes.
      final catalog = jsonDecode(utf8.decode(payload, allowMalformed: false));
      if (catalog is! Map<String, dynamic> ||
          catalog['schemaVersion'] is! int ||
          catalog['schemaVersion'] != 1 ||
          catalog['plugins'] is! List) {
        throw _invalid;
      }
      return catalog;
    } catch (_) {
      throw _invalid;
    }
  }

  static List<int> _bytes(Object? value, int maxBytes) {
    if (value is! String ||
        value.isEmpty ||
        value.length > ((maxBytes + 2) ~/ 3) * 4) {
      throw _invalid;
    }
    final bytes = base64Decode(value);
    if (bytes.isEmpty ||
        bytes.length > maxBytes ||
        base64Encode(bytes) != value) {
      throw _invalid;
    }
    return bytes;
  }
}
