// Persisted per-install device identifier, sent as the Device-Token header
// on every authenticated request and embedded in the SSE subscribe payload.
// Mirrors webapp/src/reusables/hooks/requests.ts's device-token pattern.

import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _deviceTokenKey = 'device_token';
final _storage = FlutterSecureStorage();

Future<String> resolveDeviceToken() async {
  final existing = await _storage.read(key: _deviceTokenKey);
  if (existing != null && existing.isNotEmpty) return existing;

  final random = Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  final generated = base64UrlEncode(bytes);
  await _storage.write(key: _deviceTokenKey, value: generated);
  return generated;
}
