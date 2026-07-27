// Notifications endpoints. Mirrors chatterloop_mobile/lib/services/notifications_api.dart's role.
//
// v1 (/u/getNotifications, /u/readnotifications) and v2 (/u/v2/notifications/*)
// coexist deliberately, exactly as on web: v1 keeps serving the topbar badge
// and the SSE-driven redux list, while the sectioned v2 routes back the
// redesigned Notifications screen.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/utils/content_validator.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_v2_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class NotificationsApi {
  final _dio = ApiClient.instance.dio;
  final _endpoints = Endpoints();

  /// page/range are required, not optional - the server's Mongo aggregation
  /// does `$skip: (parseInt(page) - 1) * parseInt(range)` with no fallback
  /// (routes/users/index.js's GET /getNotifications). Without these headers
  /// that's NaN, the aggregation throws, and the route responds
  /// {status:false} - which silently looked like "no notifications" client
  /// side. Matches webapp's NotificationInitRequest (page: page || 1,
  /// range: range || 20).
  Future<EncodedResponse?> getNotificationsListRequest(
      {int page = 1, int range = 20}) async {
    ContentValidator()
        .printer('${_endpoints.apiUrl}${_endpoints.getNotifications}');
    try {
      final response = await _dio.get(_endpoints.getNotifications,
          options: Options(headers: {
            'page': page.toString(),
            'range': range.toString(),
          }));
      if (response.data["status"] == false) return null;
      return EncodedResponse(response.data["result"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  /// Notifications v2 init: previews + totals + unread counts for all three
  /// sections in one round-trip. `range` doubles as the per-page size for
  /// [notificationsSectionV2Request] so the Mongo $skip arithmetic stays
  /// aligned across loads (page 2 starts where the preview left off) - pass
  /// the same value to both.
  Future<NotificationsOverviewV2?> notificationsOverviewV2Request(
      {int range = 10}) async {
    try {
      final response = await _dio.get('${_endpoints.notificationsV2}overview',
          options: Options(headers: {'range': range.toString()}));
      if (response.data["status"] != true) return null;
      final decoded = JwtCodec.decode(response.data["result"]);
      if (decoded == null) return null;
      return NotificationsOverviewV2.fromJson(decoded);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  /// One page of a single section - drives the See-all infinite scroll.
  Future<NotificationSectionData?> notificationsSectionV2Request(
    NotificationSection section, {
    int page = 1,
    int range = 10,
  }) async {
    try {
      final response = await _dio.get(
          '${_endpoints.notificationsV2}${section.slug}',
          options: Options(headers: {
            'page': page.toString(),
            'range': range.toString(),
          }));
      if (response.data["status"] != true) return null;
      final decoded = JwtCodec.decode(response.data["result"]);
      if (decoded == null) return null;
      return NotificationSectionData.fromJson(decoded);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  Future<EncodedResponse?> readNotificationsRequest() async {
    ContentValidator()
        .printer('${_endpoints.apiUrl}${_endpoints.readNotifications}');
    try {
      final response = await _dio.post(_endpoints.readNotifications);
      if (response.data["status"] == false) return null;
      return EncodedResponse(response.data["message"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }
}
