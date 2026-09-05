import 'package:anx_reader/service/security/credential_vault.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('credential envelope contains ciphertext but never plaintext', () async {
    final vault = CredentialVault(XorTestCipher());
    final envelope = await vault.seal({'glm': 'secret-key'});

    expect(envelope.ciphertext, isNot(contains('secret-key')));
    expect(await vault.open(envelope), {'glm': 'secret-key'});
  });

  test('failed opening does not replace a previously saved credential',
      () async {
    final vault = CredentialVault(XorTestCipher());
    final envelope = await vault.seal({'glm': 'secret-key'});
    final corrupted = CredentialEnvelope(
      version: envelope.version,
      algorithm: envelope.algorithm,
      salt: envelope.salt,
      nonce: envelope.nonce,
      ciphertext: 'corrupted',
      tag: envelope.tag,
    );

    expect(() => vault.open(corrupted), throwsA(isA<CredentialException>()));
  });
}
