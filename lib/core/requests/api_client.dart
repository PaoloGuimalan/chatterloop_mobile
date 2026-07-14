// Shared Dio wrappers - one instance per backend base URL, each carrying
// the same Origin/Device-Token/x-access-token interceptor. Mirrors
// chatterloop_mobile/lib/services/api_client.dart's dual-client structure
// (ApiClient.instance / ApiClient.userService), adapted to this app's
// actual working auth pattern (secure-storage token, no client-side nonce).

import 'package:chatterloop_app/core/utils/device_token.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
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
        options.headers['origin'] = Endpoints.origin;
        options.headers['device-token'] = await resolveDeviceToken();
        final token = await readToken();
        if (token != null && token.isNotEmpty) {
          options.headers['x-access-token'] = token;
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
}
