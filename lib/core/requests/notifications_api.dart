// Notifications endpoints. Mirrors chatterloop_mobile/lib/services/notifications_api.dart's role.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/utils/content_validator.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:flutter/foundation.dart';

class NotificationsApi {
  final _dio = ApiClient.instance.dio;
  final _endpoints = Endpoints();

  Future<EncodedResponse?> getNotificationsListRequest() async {
    ContentValidator()
        .printer('${_endpoints.apiUrl}${_endpoints.getNotifications}');
    try {
      final response = await _dio.get(_endpoints.getNotifications);
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
