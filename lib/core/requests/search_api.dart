// User search endpoint (Django). Mirrors chatterloop_mobile/lib/services/search_api.dart's role.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/user_models/search_result_model.dart';
import 'package:flutter/foundation.dart';

class SearchApi {
  final _dio = ApiClient.userService.dio;
  final _endpoints = Endpoints();

  /// Not wrapped in the usual {status, result} envelope - plain DRF
  /// paginated response {count, next, previous, results}.
  ///
  /// v1: people only. Kept for any caller that specifically wants to exclude
  /// pages; the search screen uses searchEntitiesRequest below.
  Future<List<SearchResultUser>> searchUsersRequest(String query) async {
    if (query.trim().isEmpty) return const [];

    try {
      final response = await _dio
          .get('${_endpoints.search}${Uri.encodeComponent(query.trim())}/');

      final results = response.data["results"];
      if (results is! List) return const [];
      return results
          .whereType<Map>()
          .map((item) =>
              SearchResultUser.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return const [];
    }
  }

  /// Search v2 - people AND pages in one normalized shape, with connection
  /// state on the people. `realmTypes` defaults to "page" so only
  /// profile-like pages surface; widen it to include groups/servers.
  Future<List<SearchResultUser>> searchEntitiesRequest(
    String query, {
    String types = "user,realm",
    String realmTypes = "page",
  }) async {
    if (query.trim().isEmpty) return const [];

    try {
      final response = await _dio.get(
        '${_endpoints.entitySearch}${Uri.encodeComponent(query.trim())}/',
        queryParameters: {
          "page": 1,
          "page_size": 15,
          "types": types,
          "realm_types": realmTypes,
        },
      );

      final results = response.data["results"];
      if (results is! List) return const [];
      return results
          .whereType<Map>()
          .map((item) =>
              SearchResultUser.fromEntityJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return const [];
    }
  }
}
