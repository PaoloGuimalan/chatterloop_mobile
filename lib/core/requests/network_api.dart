// Network endpoints - the redesigned Contacts screen's data. Verified against
// webapp's NetworkOverviewRequest / NetworkSectionRequest /
// GroupShortcutsRequest and user_service's entity/network_views.py.
//
// TWO services feed this screen, and they are loaded independently so a slow
// query on one never holds up the other:
//   - the three graph sections (connections/followers/following) come from
//     Django, ranked by interaction score;
//   - group chats come from Node/Mongo - shortcuts into conversations the
//     entity is actually in, ordered by most recent activity.
//
// Follow back / Unfollow are NOT here: they reuse the existing entity-generic
// ProfileApi.setEntityFollowRequest (POST/DELETE /api/realm/follow).

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/http_models/paged_result.dart';
import 'package:chatterloop_app/models/user_models/network_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// The three graph sections served by /api/entity/network/*. Group chats are
/// deliberately not one of these - see the file comment.
enum NetworkSection { connections, followers, following }

extension NetworkSectionSlug on NetworkSection {
  /// The path segment AND the overview response key.
  String get slug => switch (this) {
        NetworkSection.connections => "connections",
        NetworkSection.followers => "followers",
        NetworkSection.following => "following",
      };

  String get title => switch (this) {
        NetworkSection.connections => "Connections",
        NetworkSection.followers => "Followers",
        NetworkSection.following => "Following",
      };

  static NetworkSection? fromSlug(String slug) {
    for (final section in NetworkSection.values) {
      if (section.slug == slug) return section;
    }
    return null;
  }
}

class NetworkApi {
  final _userDio = ApiClient.userService.dio;
  final _nodeDio = ApiClient.instance.dio;
  final _endpoints = Endpoints();

  /// Contacts screen init: previews + totals for all three graph sections in
  /// one call. Plain JSON body (no {status, result} envelope). Returns null on
  /// failure so the screen can distinguish it from a genuinely empty network.
  Future<NetworkOverview?> networkOverviewRequest() async {
    try {
      final response = await _userDio.get(_endpoints.networkOverview);
      if (response.data is! Map) return null;
      return NetworkOverview.fromJson(
          Map<String, dynamic>.from(response.data as Map));
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  /// One page of a graph section - DRF-paginated, ranked the same way as the
  /// overview preview so the "See all" list simply continues it.
  Future<PagedResult<NetworkEntityResult>> networkSectionRequest(
    NetworkSection section, {
    int page = 1,
    int pageSize = 12,
  }) async {
    try {
      final response = await _userDio.get(
        '${_endpoints.network}${section.slug}',
        queryParameters: {"page": page, "page_size": pageSize},
      );
      return PagedResult.fromDrf(response.data, NetworkEntityResult.fromJson);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return PagedResult.empty();
    }
  }

  /// Group chat shortcuts (Node). page/range go as HEADERS, not query params -
  /// that's this route's own convention, same as /u/getNotifications - and the
  /// result is jwt-signed like the rest of the Node routes.
  Future<GroupShortcutsPage> groupShortcutsRequest({
    int page = 1,
    int range = 20,
  }) async {
    try {
      final response = await _nodeDio.get(
        _endpoints.groupShortcuts,
        options: Options(headers: {
          'page': page.toString(),
          'range': range.toString(),
        }),
      );
      if (response.data["status"] != true) return GroupShortcutsPage.empty;
      return GroupShortcutsPage.fromJson(
          JwtCodec.decode(response.data["result"]));
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return GroupShortcutsPage.empty;
    }
  }
}
