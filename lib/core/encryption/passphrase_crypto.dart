import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'package:crypto/crypto.dart' as digest;
import 'package:cryptography/cryptography.dart';

class PassphraseCrypto {
  static const parameters = {
    'version': 19,
    'memory_kib': 65536,
    'iterations': 3,
    'parallelism': 1,
    'output_length': 32
  };
  static const profile = {
    'format_version': 1,
    'kdf_algorithm': 'argon2id',
    'kdf_parameters': parameters,
    'cipher_algorithm': 'aes-256-gcm',
    'salt_bytes': 16,
    'nonce_bytes': 12,
    'tag_bytes': 16,
    'verification_token_bytes': 32,
    'verification_marker': 'chatterloop.encryption.verification.v1'
  };
  static final _uuid =
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
  static bool validPhrase(String value) =>
      value.runes.length >= 15 && utf8.encode(value).length <= 1024;
  static List<int> randomBytes(int length) =>
      List.generate(length, (_) => Random.secure().nextInt(256));
  static String uuid() {
    final b = randomBytes(16);
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static List<int> binary(dynamic value, int min, int max) {
    if (value is! String || value.length > ((max + 2) ~/ 3) * 4) {
      throw const FormatException('Invalid encrypted data');
    }
    final bytes = base64Decode(value);
    if (base64Encode(bytes) != value ||
        bytes.length < min ||
        bytes.length > max) {
      throw const FormatException('Invalid encrypted data');
    }
    return bytes;
  }

  static void validateProfile(Map<String, dynamic> value) {
    for (final e in profile.entries) {
      if (e.key == 'kdf_parameters') {
        if (value[e.key] is! Map ||
            parameters.entries.any((p) => value[e.key][p.key] != p.value) ||
            (value[e.key] as Map).length != parameters.length) {
          throw const FormatException('Unsupported encryption profile');
        }
      } else if (value[e.key] != e.value) {
        throw const FormatException('Unsupported encryption profile');
      }
    }
  }

  static void validateConfiguration(Map<String, dynamic> c) {
    validateProfile({...profile, ...c});
    if (!_uuid.hasMatch(c['id'] as String? ?? '') || c['purpose'] != 'diary') {
      throw const FormatException('Unsupported encryption configuration');
    }
    for (final field in ['entity_id', 'user_id']) {
      if (c[field] is! String ||
          (c[field] as String).isEmpty ||
          (c[field] as String).length > 40) {
        throw const FormatException('Invalid encryption owner');
      }
    }
    if (c['verification_aad'] != verificationAad(c)) {
      throw const FormatException('Invalid verification binding');
    }
    binary(c['salt'], 16, 16);
    binary(c['verification_nonce'], 12, 12);
    binary(c['verification_ciphertext'], 17, 1024);
  }

  static String verificationAad(Map<String, dynamic> c) => jsonEncode([
        'chatterloop.encryption.verification',
        1,
        c['id'],
        c['entity_id'],
        c['user_id'],
        'diary'
      ]);
  Future<List<int>> derive(String phrase, List<int> salt) =>
      Isolate.run(() async {
        final key = await Argon2id(
                parallelism: 1, memory: 65536, iterations: 3, hashLength: 32)
            .deriveKey(secretKey: SecretKey(utf8.encode(phrase)), nonce: salt);
        return key.extractBytes();
      });
  Future<({List<int> key, String proof})> unlock(
      Map<String, dynamic> c, String phrase) async {
    validateConfiguration(c);
    final key = await derive(phrase, binary(c['salt'], 16, 16));
    try {
      final plain = await _decrypt(key, binary(c['verification_nonce'], 12, 12),
          binary(c['verification_ciphertext'], 17, 1024), verificationAad(c));
      final payload = jsonDecode(plain);
      if (payload is! Map ||
          payload.length != 2 ||
          payload['marker'] != profile['verification_marker']) {
        throw const FormatException('Incorrect passphrase');
      }
      final token = binary(payload['token'], 32, 32);
      return (key: key, proof: base64Encode(token));
    } catch (_) {
      key.fillRange(0, key.length, 0);
      throw const FormatException('Could not unlock. Check your passphrase.');
    }
  }

  Future<Map<String, dynamic>> setup(String name, String phrase, String entity,
      String user, String version) async {
    if (!validPhrase(phrase) ||
        name.trim().isEmpty ||
        name.trim().runes.length > 80) {
      throw const FormatException('Check the name and passphrase');
    }
    final id = uuid(),
        salt = randomBytes(16),
        token = randomBytes(32),
        nonce = randomBytes(12);
    final key = await derive(phrase, salt);
    try {
      final aad = jsonEncode([
        'chatterloop.encryption.verification',
        1,
        id,
        entity,
        user,
        'diary'
      ]);
      final cipher = await _encrypt(
          key,
          nonce,
          jsonEncode({
            'marker': profile['verification_marker'],
            'token': base64Encode(token)
          }),
          aad);
      final verified = await _decrypt(key, nonce, cipher, aad);
      if (verified !=
          jsonEncode({
            'marker': profile['verification_marker'],
            'token': base64Encode(token)
          })) {
        throw const FormatException('Could not verify encryption');
      }
      return {
        'id': id,
        'purpose': 'diary',
        'name': name.trim(),
        'expected_scope_version': version,
        'format_version': 1,
        'kdf_algorithm': 'argon2id',
        'kdf_parameters': parameters,
        'cipher_algorithm': 'aes-256-gcm',
        'salt': base64Encode(salt),
        'verification_nonce': base64Encode(nonce),
        'verification_ciphertext': base64Encode(cipher),
        'verification_digest': digest.sha256.convert(token).toString()
      };
    } finally {
      key.fillRange(0, key.length, 0);
      token.fillRange(0, token.length, 0);
    }
  }

  Future<List<int>> _encrypt(
      List<int> key, List<int> nonce, String plain, String aad) async {
    final box = await AesGcm.with256bits().encrypt(utf8.encode(plain),
        secretKey: SecretKey(key), nonce: nonce, aad: utf8.encode(aad));
    return [...box.cipherText, ...box.mac.bytes];
  }

  Future<String> _decrypt(
          List<int> key, List<int> nonce, List<int> cipher, String aad) async =>
      utf8.decode(await AesGcm.with256bits().decrypt(
          SecretBox(cipher.sublist(0, cipher.length - 16),
              nonce: nonce, mac: Mac(cipher.sublist(cipher.length - 16))),
          secretKey: SecretKey(key),
          aad: utf8.encode(aad)));
  static Map<String, dynamic> envelope(String raw) {
    if (raw.length > 4 * 1024 * 1024 + 512) {
      throw const FormatException('Encrypted entry too large');
    }
    final e = jsonDecode(raw);
    if (e is! Map ||
        e.length != 5 ||
        e['v'] != 1 ||
        !_uuid.hasMatch(e['configuration_id'] as String? ?? '') ||
        !_uuid.hasMatch(e['entry_binding'] as String? ?? '')) {
      throw const FormatException('Invalid diary encryption');
    }
    binary(e['nonce'], 12, 12);
    binary(e['ciphertext'], 16, 2 * 1024 * 1024);
    return Map<String, dynamic>.from(e);
  }

  Future<(String, String)> encryptDiary(List<int> key, String entity,
      String user, String config, String title, String content) async {
    if (utf8.encode(title).length + 16 > 16 * 1024 ||
        utf8.encode(content).length + 16 > 2 * 1024 * 1024) {
      throw const FormatException('This entry is too large to encrypt');
    }
    final binding = uuid();
    Future<String> field(String name, String text) async {
      final nonce = randomBytes(12);
      final cipher = await _encrypt(
          key,
          nonce,
          text,
          jsonEncode([
            'chatterloop.diary.field',
            1,
            entity,
            user,
            config,
            binding,
            name
          ]));
      return jsonEncode({
        'v': 1,
        'configuration_id': config,
        'entry_binding': binding,
        'nonce': base64Encode(nonce),
        'ciphertext': base64Encode(cipher)
      });
    }

    return (await field('title', title), await field('content', content));
  }

  Future<(String, String)> decryptDiary(List<int> key, String entity,
      String user, String title, String content) async {
    final t = envelope(title), c = envelope(content);
    if (t['configuration_id'] != c['configuration_id'] ||
        t['entry_binding'] != c['entry_binding'] ||
        t['nonce'] == c['nonce']) {
      throw const FormatException('Diary binding mismatch');
    }
    Future<String> field(Map<String, dynamic> e, String name) => _decrypt(
        key,
        binary(e['nonce'], 12, 12),
        binary(
            e['ciphertext'], 16, name == 'title' ? 16 * 1024 : 2 * 1024 * 1024),
        jsonEncode([
          'chatterloop.diary.field',
          1,
          entity,
          user,
          e['configuration_id'],
          e['entry_binding'],
          name
        ]));
    return (await field(t, 'title'), await field(c, 'content'));
  }
}
