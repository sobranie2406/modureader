abstract interface class CredentialCipher {
  String get algorithm;
  Future<CredentialEnvelope> encrypt(Map<String, String> credentials);
  Future<Map<String, String>> decrypt(CredentialEnvelope envelope);
}

class CredentialEnvelope {
  const CredentialEnvelope({
    required this.version,
    required this.algorithm,
    required this.salt,
    required this.nonce,
    required this.ciphertext,
    required this.tag,
  });

  final int version;
  final String algorithm;
  final String salt;
  final String nonce;
  final String ciphertext;
  final String tag;
}

class CredentialException implements Exception {
  const CredentialException(this.message);
  final String message;

  @override
  String toString() => 'CredentialException: $message';
}

class CredentialVault {
  CredentialVault(this._cipher);

  final CredentialCipher _cipher;

  Future<CredentialEnvelope> seal(Map<String, String> credentials) {
    return _cipher.encrypt(Map.unmodifiable(credentials));
  }

  Future<Map<String, String>> open(CredentialEnvelope envelope) async {
    if (envelope.algorithm != _cipher.algorithm) {
      throw const CredentialException('Unsupported credential algorithm');
    }
    try {
      return Map.unmodifiable(await _cipher.decrypt(envelope));
    } catch (_) {
      throw const CredentialException('Credential authentication failed');
    }
  }
}

/// Test-only deterministic cipher; production injects a platform crypto adapter.
class XorTestCipher implements CredentialCipher {
  @override
  String get algorithm => 'test-only';

  @override
  Future<CredentialEnvelope> encrypt(Map<String, String> credentials) async {
    final plaintext = credentials.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('&');
    final ciphertext = plaintext.codeUnits
        .map((value) => (value ^ 0x5a).toRadixString(16))
        .join('.');
    return CredentialEnvelope(
      version: 1,
      algorithm: algorithm,
      salt: 'test-salt',
      nonce: 'test-nonce',
      ciphertext: ciphertext,
      tag: 'test-tag',
    );
  }

  @override
  Future<Map<String, String>> decrypt(CredentialEnvelope envelope) async {
    final plaintext = envelope.ciphertext.split('.').map((value) {
      final code = int.tryParse(value, radix: 16);
      if (code == null) throw const FormatException();
      return String.fromCharCode(code ^ 0x5a);
    }).join();
    final result = <String, String>{};
    for (final pair in plaintext.split('&')) {
      final separator = pair.indexOf('=');
      if (separator <= 0) throw const FormatException();
      result[pair.substring(0, separator)] = pair.substring(separator + 1);
    }
    return result;
  }
}
