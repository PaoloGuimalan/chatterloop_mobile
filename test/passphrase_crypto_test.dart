import 'dart:convert';
import 'package:chatterloop_app/core/encryption/passphrase_crypto.dart';
import 'package:chatterloop_app/core/encryption/diary_session.dart';
import 'package:chatterloop_app/core/requests/diary_api.dart';
import 'package:dio/dio.dart';
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
    final cachedKey = List<int>.from(unlocked.key);
    final session = DiarySession();
    session.install({
      'consumer_capabilities': {
        'diary': {'format_version': 1}
      },
      'purposes': [
        {
          'purpose': 'diary',
          'active_configuration_id': c['id'],
          'configurations': [
            {...c, 'is_active': true}
          ],
        }
      ],
    }, 'vector-owner');
    session.addKey(c['id'] as String, cachedKey);
    final fields = await session.encryptNew(
        'Saved title', '<p>Saved writing</p>',
        confirmedKey: unlocked.key);
    // This is the real dialog-confirmation buffer, not a writable fixture key.
    unlocked.key.fillRange(0, unlocked.key.length, 0);
    expect(unlocked.key, everyElement(0));
    final dio = Dio(BaseOptions(baseUrl: 'https://local.test'));
    Map<String, dynamic>? submitted;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      submitted = Map<String, dynamic>.from(options.data as Map);
      handler.resolve(Response(
          requestOptions: options,
          data: {'id': 'saved-encrypted-entry', ...submitted!}));
    }));
    final saved = await DiaryApi(dio: dio).createEntry(
        title: fields.$1,
        content: fields.$2,
        entryDate: '2026-10-20',
        isPrivate: true,
        isEncrypted: true);
    dio.close();
    expect(saved?.isEncrypted, isTrue);
    expect(submitted?['is_encrypted'], isTrue);
    expect(submitted?['title'], fields.$1);
    expect(submitted?['content'], fields.$2);
    expect(
        await PassphraseCrypto().decryptDiary(
            cachedKey, 'entity-vector', 'user-vector', fields.$1, fields.$2),
        ('Saved title', '<p>Saved writing</p>'));
    session.clear();
    expect(session.ready, isFalse);
    expect(cachedKey, everyElement(0));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
