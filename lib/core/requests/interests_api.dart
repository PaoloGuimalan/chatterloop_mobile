// Interest endpoints (Django user_service, interests/urls.py).
//
// Verified against interests/views.py PopularTopicsView and the webapp's
// GetPopularTopicsRequest, so both clients read the same shape.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/http_models/paged_result.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/models/user_models/moderation_detail_model.dart';
import 'package:chatterloop_app/models/user_models/popular_topic_model.dart';
import 'package:flutter/foundation.dart';

class InterestsApi {
  final _dio = ApiClient.userService.dio;
  final _endpoints = Endpoints();

  /// The platform's currently popular topics, ranked by decayed trending
  /// score. Returns an empty list on any failure: this feeds a discovery
  /// section, and a section that cannot load should simply not render rather
  /// than turn Explore into an error screen.
  Future<List<PopularTopic>> popularTopics({int limit = 8}) async {
    try {
      final response = await _dio.get(
        _endpoints.popularTopics,
        queryParameters: {'limit': limit},
      );

      final body = response.data;
      if (body is! Map || body['status'] != true) return const [];

      final data = body['data'];
      if (data is! List) return const [];

      return data
          .whereType<Map>()
          .map((item) => PopularTopic.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('popularTopics failed: $e');
      }
      return const [];
    }
  }

  /// One page of the topic directory: matches for [query], or the trending
  /// list when it is empty.
  ///
  /// Both cases are the SAME request - the server switches its ordering on the
  /// presence of a query and nothing else - so Explore's "See all" and its Tags
  /// results page the identical endpoint rather than one screen having to know
  /// which of two it is looking at.
  Future<PagedResult<PopularTopic>> searchTopics({
    String query = '',
    int page = 1,
    int pageSize = 12,
  }) async {
    try {
      final response = await _dio.get(
        _endpoints.topicList,
        queryParameters: {
          if (query.trim().isNotEmpty) 'q': query.trim(),
          'page': page,
          'page_size': pageSize,
        },
      );
      return PagedResult.fromDrf(response.data, PopularTopic.fromJson);
    } catch (e) {
      if (kDebugMode) {
        print('searchTopics failed: $e');
      }
      return PagedResult.empty<PopularTopic>();
    }
  }

  /// One page of the posts filed under [slug], plus the topic itself.
  ///
  /// The topic travels with every page so a drill-down header can name what it
  /// is showing without a second request. Visibility is applied server-side -
  /// the posts in a topic are not a subset of whatever feed the client happens
  /// to be holding, and only the server knows which the viewer may read.
  Future<(PagedResult<PostPreview>, PopularTopic?)> topicPosts({
    required String slug,
    int page = 1,
    int pageSize = 10,
  }) async {
    try {
      final response = await _dio.get(
        '${_endpoints.topicPosts}${Uri.encodeComponent(slug)}/posts/',
        queryParameters: {'page': page, 'page_size': pageSize},
      );

      final body = response.data;
      final topic = body is Map && body['topic'] is Map
          ? PopularTopic.fromJson(Map<String, dynamic>.from(body['topic']))
          : null;

      return (PagedResult.fromDrf(body, PostPreview.fromJson), topic);
    } catch (e) {
      if (kDebugMode) {
        print('topicPosts failed: $e');
      }
      return (PagedResult.empty<PostPreview>(), null);
    }
  }

  /// Why a post or comment was removed.
  ///
  /// Returns null on ANY failure, including 404 - and 404 means either "no such
  /// record" or "not yours to see", which the server deliberately does not
  /// distinguish. The screen must not distinguish either.
  Future<ModerationDetail?> moderationDetail(String moderationId) async {
    try {
      final response = await _dio.get(
        '${_endpoints.moderationDetail}${Uri.encodeComponent(moderationId)}/',
      );

      final body = response.data;
      if (body is! Map || body['status'] != true || body['data'] is! Map) {
        return null;
      }
      return ModerationDetail.fromJson(Map<String, dynamic>.from(body['data']));
    } catch (e) {
      if (kDebugMode) {
        print('moderationDetail failed: $e');
      }
      return null;
    }
  }
}
