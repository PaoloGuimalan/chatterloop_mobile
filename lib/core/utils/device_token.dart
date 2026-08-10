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

const _callClientIdKey = 'call_client_id';

/// This install's identity inside a call room - the media stack's `clientId`.
///
/// STABLE across launches, which is the whole point. The server treats a join
/// under a clientId it already has as a RECONNECT: it evicts the previous
/// session's transports and producers without broadcasting a leave/rejoin
/// flash (webRTC.js's evictClientSession). A fresh random id per join, which
/// is what this used to be, can never reach that path - it arrives as a
/// stranger, so a session orphaned by a crash or a dropped network is left
/// sitting in the room as a ghost participant beside the new one.
///
/// Webapp does the same thing by reusing its stored `device` value as the
/// clientId. A SEPARATE key here rather than resolveDeviceToken's: the clientId
/// is broadcast to every other participant in the room (it rides
/// participant-joined and new_producer), and the device token is a request
/// header that has no business being handed to peers.
///
/// One id per install is enough because one install can only be in one call at
/// a time - CallController refuses a join while a call is live.
Future<String> resolveCallClientId() async {
  final existing = await _storage.read(key: _callClientIdKey);
  if (existing != null && existing.isNotEmpty) return existing;

  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  final generated = 'mobile-${base64UrlEncode(bytes)}';
  await _storage.write(key: _callClientIdKey, value: generated);
  return generated;
}
