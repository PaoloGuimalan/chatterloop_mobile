// Notifications endpoints. Mirrors chatterloop_mobile/lib/services/notifications_api.dart's role.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/utils/content_validator.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
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
