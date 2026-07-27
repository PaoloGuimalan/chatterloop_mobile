// Search endpoints. v1/v2 entity search (Django) plus the v2 SECTION
// endpoints that back the redesigned Explore screen - verified against
// webapp/src/reusables/hooks/requests.ts (SearchOverviewRequest /
// SearchPeopleRequest / SearchRealmsRequest / SearchPostsRequest /
// JoinRealmGroupRequest) and user_service's entity/search_views.py +
// newsfeed/services/post_search.py.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/http_models/paged_result.dart';
import 'package:chatterloop_app/models/user_models/search_result_model.dart';
import 'package:chatterloop_app/models/user_models/search_v2_models.dart';
import 'package:flutter/foundation.dart';

class SearchApi {
  final _dio = ApiClient.userService.dio;
  final _endpoints = Endpoints();

  /// Not wrapped in the usual {status, result} envelope - plain DRF
  /// paginated response {count, next, previous, results}.
  ///
  /// v1: people only. Kept for any caller that specifically wants to exclude
  /// pages; the search screen uses the v2 section endpoints below.
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
  ///
  /// This is the flat, single-list search (used by pickers and anything that
  /// wants one homogeneous result list). The Explore screen uses the
  /// sectioned endpoints below instead.
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

  /// One round-trip that settles all three Explore section previews for a
  /// query. Wrapped in {status, result} unlike the paginated section
  /// endpoints below. Returns null on failure so the caller can tell "no
  /// results" apart from "the call failed".
  Future<SearchOverview?> searchOverviewV2Request(String query) async {
    if (query.trim().isEmpty) return null;

    try {
      final response = await _dio.get(
          '${_endpoints.searchOverviewV2}${Uri.encodeComponent(query.trim())}/');
      if (response.data["status"] != true) return null;
      final result = response.data["result"];
      if (result is! Map) return null;
      return SearchOverview.fromJson(Map<String, dynamic>.from(result));
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  /// People "See all" - ranked prefix match first, then mutual count.
  Future<PagedResult<SearchPersonResult>> searchPeopleV2Request(
    String query, {
    int page = 1,
    int pageSize = 12,
  }) async {
    if (query.trim().isEmpty) return PagedResult.empty();

    try {
      final response = await _dio.get(
        '${_endpoints.searchPeopleV2}${Uri.encodeComponent(query.trim())}/',
        queryParameters: {"page": page, "page_size": pageSize},
      );
      return PagedResult.fromDrf(response.data, SearchPersonResult.fromJson);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return PagedResult.empty();
    }
  }

  /// Realms "See all". realm_types is left at "all", which the server
  /// resolves to page/server/group only - channel/conference/voice realms can
  /// never surface in search regardless of what's asked for.
  Future<PagedResult<SearchRealmResult>> searchRealmsV2Request(
    String query, {
    int page = 1,
    int pageSize = 12,
    String realmTypes = "all",
  }) async {
    if (query.trim().isEmpty) return PagedResult.empty();

    try {
      final response = await _dio.get(
        '${_endpoints.searchRealmsV2}${Uri.encodeComponent(query.trim())}/',
        queryParameters: {
          "page": page,
          "page_size": pageSize,
          "realm_types": realmTypes,
        },
      );
      return PagedResult.fromDrf(response.data, SearchRealmResult.fromJson);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return PagedResult.empty();
    }
  }

  /// Content "See all" - ranked by PostScore.ranking_score.
  Future<PagedResult<SearchPostResult>> searchPostsV2Request(
    String query, {
    int page = 1,
    int pageSize = 10,
  }) async {
    if (query.trim().isEmpty) return PagedResult.empty();

    try {
      final response = await _dio.get(
        '${_endpoints.searchPostsV2}${Uri.encodeComponent(query.trim())}/',
        queryParameters: {"page": page, "page_size": pageSize},
      );
      return PagedResult.fromDrf(response.data, SearchPostResult.fromJson);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return PagedResult.empty();
    }
  }

  /// One-click join for a PUBLIC group realm. The server enforces
  /// public + active + type=group, so a private group can't be joined this
  /// way even if a card somehow offered it. Returns the conversation id to
  /// open (a group's conversationID IS its realm_id), or null on failure.
  Future<String?> joinGroupRealmRequest(String realmId) async {
    try {
      final response =
          await _dio.post(_endpoints.realmJoinV2, data: {"realm_id": realmId});
      if (response.data["status"] != true) return null;
      final result = response.data["result"];
      if (result is! Map) return null;
      return (result["conversation_id"] ?? result["realm_id"])?.toString();
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }
}
