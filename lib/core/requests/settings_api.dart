// Settings-section endpoints on the Django user service (device sessions,
// blocked accounts, data export/deletion). Auth token is attached
// automatically by ApiClient's interceptor, so - unlike the webapp's manual
// x-access-token header - nothing here sets it explicitly. Each list call
// degrades to an empty list on failure so the screens show an empty state
// rather than throwing.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/user_models/device_session_model.dart';
import 'package:flutter/foundation.dart';

class SettingsApi {
  final _dio = ApiClient.userService.dio;
  final _endpoints = Endpoints();

  /// GET /api/user/devices - mirrors webapp's ListDeviceSessionsRequest.
  Future<List<DeviceSession>> listDeviceSessions() async {
    try {
      final response = await _dio.get(_endpoints.devices);
      if (response.data?['status'] != true) return const [];
      final data = response.data?['data'];
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((e) => DeviceSession.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      if (kDebugMode) print('ERROR listDeviceSessions: $e');
      return const [];
    }
  }

  /// DELETE /api/user/devices {sessionID} - signs one session out. Mirrors
  /// webapp's RevokeDeviceSessionRequest.
  Future<bool> revokeDeviceSession(String sessionID) async {
    try {
      final response =
          await _dio.delete(_endpoints.devices, data: {'sessionID': sessionID});
      return response.data?['status'] == true;
    } catch (e) {
      if (kDebugMode) print('ERROR revokeDeviceSession: $e');
      return false;
    }
  }
}
