// Settings-section endpoints on the Django user service (device sessions,
// blocked accounts, data export/deletion). Auth token is attached
// automatically by ApiClient's interceptor, so - unlike the webapp's manual
// x-access-token header - nothing here sets it explicitly. Each list call
// degrades to an empty list on failure so the screens show an empty state
// rather than throwing.

import 'package:dio/dio.dart';

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
  /// files a report against any entity or one piece of its content. Mirrors
  /// webapp's SubmitReportRequest.
  ///
  /// [targetId] is the ENTITY id for target_type 'user'/'realm' (a realm also
  /// accepts its own realm id), and the artefact's own id for
  /// 'post'/'comment'/'message'. The server resolves which entity is
  /// responsible either way, so this one call covers every surface.
  ///
  /// A 4xx here is a real answer ("You cannot report yourself", "Post not
  /// found"), so its message is surfaced rather than swallowed - only a
  /// transport failure falls through to the generic null.
  Future<({bool ok, String? message})> submitReport({
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
    } on DioException catch (e) {
      if (kDebugMode) print('ERROR submitReport: $e');
      return (
        ok: false,
        message: e.response?.data is Map
            ? e.response?.data['message']?.toString()
            : null,
      );
    } catch (e) {
      if (kDebugMode) print('ERROR submitReport: $e');
      return (ok: false, message: null);
    }
  }

  /// GET /api/user/me/export - returns the full data export payload (the
  /// `data` object the webapp serializes to a downloaded JSON file), or null
  /// on failure. Mirrors webapp's ExportAccountDataRequest.
  /// Settings > Data & Privacy > Private profile.
  ///
  /// Returns `ok` plus `postsRestricted`: switching ON also narrows every
  /// existing PUBLIC post to contacts-only, and the response says how many.
  /// Surface that number - a silent bulk rewrite of someone's back catalogue
  /// is exactly what a settings toggle must say out loud.
  ///
  /// Deliberately one-way server side: switching back OFF does NOT re-publish
  /// those posts, so the copy has to warn before the user flips it on.
  Future<({bool ok, int postsRestricted})> setProfilePrivacy(
      bool isPrivate) async {
    try {
      final response = await _dio
          .put(_endpoints.updateProfile, data: {'is_private': isPrivate});
      final data = response.data;
      final ok = data is Map ? data["status"] == true : false;
      final restricted =
          data is Map && data["posts_restricted"] is num
              ? (data["posts_restricted"] as num).toInt()
              : 0;
      return (ok: ok, postsRestricted: restricted);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return (ok: false, postsRestricted: 0);
    }
  }

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
