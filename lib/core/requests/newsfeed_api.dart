// Newsfeed interactions (Django user_service): reactions, comments, saves and
// sharing. Verified against webapp's requests.ts (ReactionSaveRequest,
// CommentReactionSaveRequest, GetReactionTotalRequest, GetCommentsRequest,
// SaveCommentRequest, CreatePostRequest) and user_service/newsfeed/views.py.
//
// Separate from FeedApi, which talks to the NODE feed (/posts/feed) and
// speaks a different payload shape entirely. The one exception is [sharePost],
// which posts to Node's /posts/createpost because that is where post creation
// lives - it's here rather than in ProfileApi because sharing is a newsfeed
// action, and the newsfeed ship will want it next to the rest of these.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/http_models/paged_result.dart';
import 'package:chatterloop_app/models/post_models/newsfeed_models.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Which HTTP verb a reaction tap becomes. The three endpoints below share one
/// URL and differ only by method, exactly as on web:
///
///   none -> tapping any emoji        POST   (first reaction)
///   some -> tapping a DIFFERENT one  PUT    (swap)
///   some -> tapping the SAME one     DELETE (take it back)
enum ReactionMethod { add, swap, remove }

/// Resolves the verb from what the viewer has already reacted with. Kept here
/// rather than in the widgets so the post row, the comment row and the future
/// newsfeed can't each get it subtly wrong.
ReactionMethod reactionMethodFor({
  required String? currentEmojiId,
  required String tappedEmojiId,
}) {
  if (currentEmojiId == null || currentEmojiId.isEmpty) {
    return ReactionMethod.add;
  }
  return currentEmojiId == tappedEmojiId
      ? ReactionMethod.remove
      : ReactionMethod.swap;
}

class NewsfeedApi {
  final _dio = ApiClient.userService.dio;
  final _nodeDio = ApiClient.instance.dio;
  final _endpoints = Endpoints();

  String _verb(ReactionMethod method) => switch (method) {
        ReactionMethod.add => 'POST',
        ReactionMethod.swap => 'PUT',
        ReactionMethod.remove => 'DELETE',
      };

  /// The reaction palette. Server-ordered by `priority`, but sorted here too
  /// since nothing guarantees the serializer preserves it.
  Future<List<Emoji>> getEmojisRequest() async {
    try {
      final response = await _dio.get(_endpoints.newsfeedEmojis);
      final data = response.data;
      if (data is! List) return const [];
      final emojis = data
          .whereType<Map>()
          .map((item) => Emoji.fromJson(Map<String, dynamic>.from(item)))
          .toList()
        ..sort((a, b) => a.priority.compareTo(b.priority));
      return emojis;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return const [];
    }
  }

  /// Add / swap / remove the viewer's reaction on a POST.
  ///
  /// `emoji_id` is sent even for a DELETE: the endpoint reads the body the
  /// same way for all three verbs, and web sends it unconditionally too.
  Future<bool> setPostReactionRequest({
    required String postId,
    required String emojiId,
    required ReactionMethod method,
  }) async {
    try {
      final response = await _dio.request(
        _endpoints.newsfeedReaction,
        data: {'post_id': postId, 'emoji_id': emojiId},
        options: Options(method: _verb(method)),
      );
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// Same three verbs, one level down - a reaction on a COMMENT.
  Future<bool> setCommentReactionRequest({
    required String commentId,
    required String emojiId,
    required ReactionMethod method,
  }) async {
    try {
      final response = await _dio.request(
        _endpoints.newsfeedCommentReaction,
        data: {'comment_id': commentId, 'emoji_id': emojiId},
        options: Options(method: _verb(method)),
      );
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// Authoritative reaction tallies for a post. The post payload already
  /// carries `preview`, so this is for refreshing after a reaction lands
  /// rather than for the first render.
  Future<List<PostReactionCount>> getPostReactionTotalsRequest(
      String postId) async {
    try {
      final response =
          await _dio.get('${_endpoints.newsfeedTotalReactions}$postId/');
      final data = response.data;
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((item) =>
              PostReactionCount.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return const [];
    }
  }

  /// One page of comments. [parentId] null fetches TOP-LEVEL comments; passing
  /// a comment id fetches that comment's replies (the thread is two levels
  /// deep, never more).
  Future<PagedResult<PostComment>> getCommentsRequest({
    required String postId,
    String? parentId,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get(
        _endpoints.newsfeedComments,
        queryParameters: {
          'post_id': postId,
          if (parentId != null) 'parent_id': parentId,
          'page': page,
          'page_size': pageSize,
        },
      );
      return PagedResult.fromDrf(response.data, PostComment.fromJson);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return PagedResult.empty();
    }
  }

  /// Post a comment, or a reply when [parentId] is set.
  ///
  /// Returns only success: the endpoint answers "OK", not the created row, so
  /// the caller refetches rather than trying to synthesise one locally (it
  /// wouldn't have the server's id, timestamp or resolved author).
  Future<bool> addCommentRequest({
    required String postId,
    String? parentId,
    required String text,
    String? attachment,
  }) async {
    try {
      final response = await _dio.post(
        _endpoints.newsfeedComments,
        data: {
          'post_id': postId,
          // Nulls are omitted rather than sent - mirrors web's
          // removeNullsFromObject on this exact payload.
          if (parentId != null) 'parent_id': parentId,
          'new_comment': text,
          if (attachment != null) 'new_attachment': attachment,
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// Share a post onto the viewer's own feed, with an optional caption.
  ///
  /// A share is an ordinary post whose single reference points at the original
  /// post's id with media type "shared_post" - exactly what web's composer
  /// sends when `toShare` is set. The whole payload is JWT-signed because
  /// that's what Node's /posts/createpost expects.
  Future<bool> sharePostRequest({
    required String postId,
    String caption = "",
    String privacy = "public",
  }) async {
    final payload = {
      'content': {
        'isShared': true,
        'references': [
          {
            'id': 1,
            'name': null,
            'reference': postId,
            'caption': '',
            'referenceMediaType': 'shared_post',
          }
        ],
        'data': caption,
      },
      'type': {
        'fileType': 'shared_post',
        'contentType': 'shared_post',
      },
      'tagging': {'isTagged': false, 'users': []},
      'privacy': {'status': privacy, 'users': []},
      'onfeed': 'feed',
    };

    try {
      final response = await _nodeDio.post(
        _endpoints.createPost,
        data: {'token': JwtCodec.sign(payload)},
      );
      return response.data["status"] != false;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }
}
