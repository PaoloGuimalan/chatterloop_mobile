import 'dart:convert';
import 'package:chatterloop_app/core/encryption/passphrase_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('passphrases count Unicode points and preserve exact whitespace', () {
    expect(PassphraseCrypto.validPhrase('😀' * 15), isTrue);
    expect(PassphraseCrypto.validPhrase('😀' * 14), isFalse);
    expect(PassphraseCrypto.validPhrase('a' * 1025), isFalse);
  });
  test('field envelopes authenticate field name and matching pair binding',
      () async {
    final key = List<int>.generate(32, (i) => i);
    final crypto = PassphraseCrypto();
    final fields = await crypto.encryptDiary(key, 'entity', 'user',
        '11111111-1111-4111-8111-111111111111', 'Secret title', '<p>Body</p>');
    expect(
        await crypto.decryptDiary(key, 'entity', 'user', fields.$1, fields.$2),
        ('Secret title', '<p>Body</p>'));
    await expectLater(
        crypto.decryptDiary(key, 'entity', 'user', fields.$2, fields.$1),
        throwsA(anything));
    final altered = Map<String, dynamic>.from(jsonDecode(fields.$2) as Map)
      ..['entry_binding'] = '22222222-2222-4222-8222-222222222222';
    await expectLater(
        crypto.decryptDiary(
            key, 'entity', 'user', fields.$1, jsonEncode(altered)),
        throwsA(anything));
  });
  test('unsupported profile is rejected before deriving a key', () {
    expect(() => PassphraseCrypto.validateProfile({'format_version': 2}),
        throwsFormatException);
  });
  test('Python Argon2id and AES-GCM verification vector interoperates',
      () async {
    final c = <String, dynamic>{
      'id': '11111111-1111-4111-8111-111111111111',
      'purpose': 'diary',
      'entity_id': 'entity-vector',
      'user_id': 'user-vector',
      'format_version': 1,
      'kdf_algorithm': 'argon2id',
      'kdf_parameters': PassphraseCrypto.parameters,
      'cipher_algorithm': 'aes-256-gcm',
      'salt': 'AAECAwQFBgcICQoLDA0ODw==',
      'verification_nonce': 'EBESExQVFhcYGRob',
      'verification_ciphertext':
          'D3h/e9M1tO+oc+WaZll42I07hZ+lFGH89ZMaBIkM2TKzS1NBLer7h8wFDrxCnva1dQZ4YAHVtXGcQbESkFf6mv85dcDLkZjqPYzsbCJ73F4ebKhqk39jUIvvNU8JiZLQc05xr3CxEIJ619iamKKB0rhIgwjnwxm5+IM=',
      'verification_aad':
          '["chatterloop.encryption.verification",1,"11111111-1111-4111-8111-111111111111","entity-vector","user-vector","diary"]',
    };
    final unlocked =
        await PassphraseCrypto().unlock(c, 'violet lantern river 你好');
    expect(unlocked.key.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        '5485f9dbf50c2bfb57a2054954e4498576759e490e476f877e160b1cf818d4a2');
    expect(unlocked.proof, 'ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8=');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
