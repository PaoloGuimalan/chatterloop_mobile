// Shared Dio wrappers - one instance per backend base URL, each carrying
// the same Origin/Device-Token/X-Nonce/x-access-token interceptor. Mirrors
// chatterloop_mobile/lib/services/api_client.dart's dual-client structure
// (ApiClient.instance / ApiClient.userService).
//
// X-Nonce is required (not optional) - confirmed by reading both
// server/reusables/hooks/jwthelper.js's jwtchecker/jwtssechecker (which
// gate most authenticated Node routes, not just the /auth/jwtchecker
// endpoint itself) and server/reusables/hooks/crypto.js's decryptNonce:
// missing/malformed nonce 403s. The exact scheme is AES-256-GCM, key =
// SHA-256(sharedSecret), encrypting "{userId}.{unixTimestamp}.{random}",
// output "{ivHex}.{cipherTextHex+tagHex}" - verified against the webapp's
// own generateXNonce in webapp/src/reusables/hooks/reusable.ts and the
// server's matching decryptNonce, byte for byte.

import 'dart:convert';
import 'dart:math';

import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/notifications/fcm_token_holder.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/utils/device_token.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiClient {
  ApiClient._(this.baseUrl);

  /// Node backend - realtime.chatterloop.app (messages, contacts,
  /// notifications, jwtchecker, media upload/post creation).
  static final ApiClient instance = ApiClient._(Endpoints().apiUrl);

  /// Django backend - user.chatterloop.app (auth, signup, profile, search).
  static final ApiClient userService = ApiClient._(Endpoints().userApiUrl);

  final String baseUrl;
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'token';

  late final Dio dio = _build();

  Dio _build() {
    final d = Dio(BaseOptions(
      baseUrl: baseUrl,
      headers: {'Content-Type': 'application/json'},
    ));
    d.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await readToken();
        options.headers['origin'] = Endpoints.origin;
        options.headers['device-token'] = await resolveDeviceToken();
        options.headers['X-Nonce'] = await _buildNonce(_userIdFromToken(token));
        if (token != null && token.isNotEmpty) {
          options.headers['x-access-token'] = token;
        }
        // FCM registration token (null until PushNotificationService fetches
        // it). The server's jwtchecker reads this header and upserts it onto
        // the current device session, so the token is registered/refreshed on
        // ordinary authenticated requests - no dedicated endpoint needed.
        final fcmToken = fcmTokenForHeader;
        if (fcmToken != null && fcmToken.isNotEmpty) {
          options.headers['fcm-token'] = fcmToken;
        }
        handler.next(options);
      },
    ));
    return d;
  }

  Future<String?> readToken() => _storage.read(key: _tokenKey);
  Future<void> writeToken(String token) =>
      _storage.write(key: _tokenKey, value: token);
  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  String _userIdFromToken(String? token) {
    if (token == null) return 'guest';
    final decoded = JwtCodec.decode(token);
    final userId = decoded?['userID'] ?? decoded?['id'] ?? decoded?['username'];
    return userId?.toString() ?? 'guest';
  }

  Future<String> _buildNonce(String userId) async {
    final secretKeyBytes = crypto.sha256.convert(utf8.encode(secretKey)).bytes;
    final secret = SecretKey(secretKeyBytes);
    final algorithm = AesGcm.with256bits();

    final nonceBytes =
        List<int>.generate(12, (_) => Random.secure().nextInt(256));
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final randomPart = Random.secure().nextInt(1 << 32).toRadixString(36);
    final plainText = utf8.encode('$userId.$timestamp.$randomPart');

    final box = await algorithm.encrypt(plainText,
        secretKey: secret, nonce: nonceBytes);

    final ivHex =
        nonceBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final cipherHex =
        box.cipherText.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final macHex =
        box.mac.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '$ivHex.$cipherHex$macHex';
  }
}
