// Settings-section endpoints on the Django user service (device sessions,
// blocked accounts, data export/deletion). Auth token is attached
// automatically by ApiClient's interceptor, so - unlike the webapp's manual
// x-access-token header - nothing here sets it explicitly. Each list call
// degrades to an empty list on failure so the screens show an empty state
// rather than throwing.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/user_models/blocked_account_model.dart';
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

  /// GET /api/user/blocks - mirrors webapp's ListBlockedUsersRequest.
  Future<List<BlockedAccount>> listBlockedAccounts() async {
    try {
      final response = await _dio.get(_endpoints.blocks);
      if (response.data?['status'] != true) return const [];
      final data = response.data?['data'];
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((e) => BlockedAccount.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      if (kDebugMode) print('ERROR listBlockedAccounts: $e');
      return const [];
    }
  }

  /// DELETE /api/user/blocks {entityID} - unblocks one account. Mirrors
  /// webapp's UnblockUserRequest.
  Future<bool> unblockAccount(String entityID) async {
    try {
      final response =
          await _dio.delete(_endpoints.blocks, data: {'entityID': entityID});
      return response.data?['status'] == true;
    } catch (e) {
      if (kDebugMode) print('ERROR unblockAccount: $e');
      return false;
    }
  }

  /// POST /api/user/blocks {entityID} - blocks an account (from their
  /// profile). Mirrors webapp's BlockUserRequest. Returns the server's
  /// status + message so the caller can surface it, same as the webapp alert.
  Future<({bool ok, String? message})> blockAccount(String entityID) async {
    try {
      final response =
          await _dio.post(_endpoints.blocks, data: {'entityID': entityID});
      return (
        ok: response.data?['status'] == true,
        message: response.data?['message']?.toString(),
      );
    } catch (e) {
      if (kDebugMode) print('ERROR blockAccount: $e');
      return (ok: false, message: null);
    }
  }

  /// POST /api/user/reports {target_type, target_id, reason, description} -
  /// submits a moderation report. Mirrors webapp's ReportUserRequest.
  Future<({bool ok, String? message})> reportUser({
    required String targetId,
    required String reason,
    String description = '',
    String targetType = 'user',
  }) async {
    try {
      final response = await _dio.post(_endpoints.reports, data: {
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason,
        'description': description,
      });
      return (
        ok: response.data?['status'] == true,
        message: response.data?['message']?.toString(),
      );
    } catch (e) {
      if (kDebugMode) print('ERROR reportUser: $e');
      return (ok: false, message: null);
    }
  }

  /// GET /api/user/me/export - returns the full data export payload (the
  /// `data` object the webapp serializes to a downloaded JSON file), or null
  /// on failure. Mirrors webapp's ExportAccountDataRequest.
  Future<dynamic> exportAccountData() async {
    try {
      final response = await _dio.get(_endpoints.dataExport);
      if (response.data?['status'] != true) return null;
      return response.data?['data'];
    } catch (e) {
      if (kDebugMode) print('ERROR exportAccountData: $e');
      return null;
    }
  }

  /// DELETE /api/user/me - permanently deactivates the account. Mirrors
  /// webapp's DeleteAccountRequest (which then logs the user out).
  Future<bool> deleteAccount() async {
    try {
      final response = await _dio.delete(_endpoints.updateProfile);
      return response.data?['status'] == true;
    } catch (e) {
      if (kDebugMode) print('ERROR deleteAccount: $e');
      return false;
    }
  }
}
