// Newsfeed interactions (Django user_service): reactions, comments, saves,
// post creation and sharing. Verified against webapp's requests.ts (ReactionSaveRequest,
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

  /// One page of a profile's posts - the feed under a user OR a realm.
  ///
  /// Three things about this endpoint are easy to get wrong:
  ///  - it is a **POST**, not a GET, because the body carries `viewcache`
  ///    (which posts the viewer has seen, for engagement scoring);
  ///  - `handle` resolves as an Account **username** OR a Realm **slug**, so
  ///    one call serves both profile kinds;
  ///  - page/page_size are QUERY params while `archive` is a separate one.
  ///
  /// `viewcache` is sent empty: it's fed by web's localforage view tracker,
  /// which has no mobile equivalent yet. The server treats an empty list as
  /// "nothing to record" rather than erroring.
  Future<PagedResult<PostPreview>> getProfilePostsRequest({
    required String handle,
    int page = 1,
    int pageSize = 10,
    bool archive = false,
  }) async {
    try {
      final response = await _dio.post(
        '${_endpoints.newsfeedProfile}${Uri.encodeComponent(handle)}/',
        data: {'viewcache': const []},
        queryParameters: {
          'page': page,
          'page_size': pageSize,
          'archive': archive,
        },
      );
      return PagedResult.fromDrf(response.data, PostPreview.fromJson);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return PagedResult.empty();
    }
  }

  /// Save / unsave a post. Available to ANYONE who can see it, not just the
  /// author - it's a bookmark, not an authorship action.
  Future<bool> setPostSavedRequest({
    required String postId,
    required bool saved,
  }) async {
    try {
      final response = saved
          ? await _dio.post(_endpoints.newsfeedSaves, data: {'post_id': postId})
          : await _dio.delete(_endpoints.newsfeedSaves,
              data: {'post_id': postId});
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// Archive / unarchive - AUTHOR only (the server enforces it too).
  ///
  /// Goes through the generic post update, which takes a `fields` map rather
  /// than named columns.
  Future<bool> setPostArchivedRequest({
    required String postId,
    required bool archived,
  }) async {
    try {
      final response = await _dio.put(
        _endpoints.newsfeedPost,
        data: {
          'post_id': postId,
          'fields': {'is_archived': archived},
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

  /// Delete a post - AUTHOR only.
  ///
  /// The endpoint takes `post_ids`, PLURAL, even for a single post: it's a
  /// bulk delete that the UI only ever calls with one.
  Future<bool> deletePostRequest(String postId) async {
    try {
      final response = await _dio.delete(
        _endpoints.newsfeedPost,
        data: {
          'post_ids': [postId]
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

  /// Delete a comment - its AUTHOR only. Soft-deleted server side, which also
  /// enforces ownership (assert_owns), so the client gate is only about not
  /// offering a button that would 403.
  Future<bool> deleteCommentRequest(String commentId) async {
    try {
      final response = await _dio.delete(
        _endpoints.newsfeedComments,
        data: {'comment_id': commentId},
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

  /// Create an ordinary post - caption, optional media, optional tags.
  ///
  /// Same Node endpoint and same signed envelope as [sharePostRequest]; the two
  /// differ only in what they put in `content.references` and `type`. Media has
  /// to be uploaded FIRST (ProfileApi.uploadMediaRequest) - this takes the CDN
  /// references that upload returns, exactly as web's composer does since the
  /// two-step upload flow landed.
  ///
  /// [taggedEntityIds] are ENTITY ids and may be people OR pages.
  ///
  /// The author is the ACTING entity, resolved server-side from the token - so
  /// posting while switched to a page publishes as that page. There is no
  /// "post to someone else's wall": writing on a profile you're visiting is a
  /// post of your own that TAGS them, which is why the composer pre-selects
  /// that profile instead of addressing the post anywhere.
  /// [contentType] overrides the derived kind, and is what turns a plain photo
  /// post into an account update: "profile" and "cover_photo" make Node's
  /// /createpost write user_account.profile / .coverphoto as well as filing the
  /// post - which is how a changed picture appears in the feed. Same two-step
  /// upload-then-post flow web's UploadProfileMedia uses.
  Future<bool> createPostRequest({
    required String caption,
    List<PostMediaReference> media = const [],
    List<String> taggedEntityIds = const [],
    String privacy = "public",
    String? contentType,
  }) async {
    final hasMedia = media.isNotEmpty;
    final payload = {
      'content': {
        'isShared': false,
        'references': [
          for (var i = 0; i < media.length; i++) media[i].toJson(i + 1),
        ],
        'data': caption,
      },
      'type': {
        'fileType': hasMedia ? 'media' : 'text',
        'contentType': contentType ?? (hasMedia ? 'media' : 'text'),
      },
      'tagging': {
        'isTagged': taggedEntityIds.isNotEmpty,
        'users': taggedEntityIds,
      },
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

  /// Share a post onto the viewer's own feed, with an optional caption.
  ///
  /// A share is an ordinary post whose single reference points at the original
  /// post's id with media type "shared_post" - exactly what web's composer
  /// sends when `toShare` is set. The whole payload is JWT-signed because
  /// that's what Node's /posts/createpost expects.
  /// [taggedEntityIds] are ENTITY ids and may be people OR pages - the server
  /// resolves both through the same table, which is why there's one list
  /// rather than a list per kind.
  Future<bool> sharePostRequest({
    required String postId,
    String caption = "",
    String privacy = "public",
    List<String> taggedEntityIds = const [],
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
      'tagging': {
        'isTagged': taggedEntityIds.isNotEmpty,
        'users': taggedEntityIds,
      },
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
