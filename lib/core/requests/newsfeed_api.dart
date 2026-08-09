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

import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/core/utils/view_cache.dart';
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

/// Whether a profile handle is the signed-in ACCOUNT's own username - the
/// client half of the profile feed's `user.username != username` check.
///
/// Deliberately the account username and not the acting entity: the server
/// compares `request.user.username`, which doesn't follow an entity switch.
/// Acting as a page and opening that page's profile is therefore NOT "your
/// own profile" by this rule, and the server does process the viewcache
/// there - self-views among those posts are still dropped one layer down,
/// where it compares the post's owner to the acting entity.
bool isOwnProfileHandle(String handle) {
  final username = appStore.state.userAuth.user.username;
  return username.isNotEmpty && username == handle;
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
  /// `viewcache` carries the view durations [PostViewTracker] has banked since
  /// the last feed request, and is cleared only once the server has taken
  /// them - see [_flushViewCache].
  ///
  /// Except on YOUR OWN profile, where the view drops it on the floor:
  ///
  ///     if user.username != username:
  ///         save_viewcache_engagements(entity, viewcache)
  ///
  /// Sending it there and then clearing on a 200 would throw away every view
  /// banked while browsing the feed, because "the request succeeded" and "the
  /// server recorded them" are not the same thing on this endpoint. So the
  /// condition is mirrored exactly rather than relying on the response.
  ///
  /// Note this is a property of the ENDPOINT, not of whose posts they are.
  /// Individual posts are already filtered by author in [PostViewTracker],
  /// and they have to be: profile_filter matches `tagging__entity` as well as
  /// `entity`, so your own profile legitimately carries other people's posts
  /// that tagged you, and someone else's carries yours.
  Future<PagedResult<PostPreview>> getProfilePostsRequest({
    required String handle,
    int page = 1,
    int pageSize = 10,
    bool archive = false,
  }) async {
    try {
      final viewCache = isOwnProfileHandle(handle)
          ? const <Map<String, dynamic>>[]
          : await _pendingViewCache();
      final response = await _dio.post(
        '${_endpoints.newsfeedProfile}${Uri.encodeComponent(handle)}/',
        data: {'viewcache': viewCache},
        queryParameters: {
          'page': page,
          'page_size': pageSize,
          'archive': archive,
        },
      );
      await _flushViewCache(viewCache);
      return PagedResult.fromDrf(response.data, PostPreview.fromJson);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return PagedResult.empty();
    }
  }

  /// The main newsfeed - everything ranked for this viewer.
  ///
  /// Same shape and quirks as [getProfilePostsRequest]: a POST rather than a
  /// GET because the body carries `viewcache` (which posts the viewer has
  /// already seen, for engagement scoring), and DRF pagination in the response.
  ///
  /// This is the request that most needs its `viewcache` to be real: the
  /// server DELETES every post id it receives from this viewer's
  /// NewsfeedIndex bucket, and that deletion is the only thing that drains
  /// the fan-out inbox. Send an empty list forever and page 1 never moves.
  Future<PagedResult<PostPreview>> getNewsfeedRequest({
    int page = 1,
    // 20, like web. See _kPageSize in newsfeed_view.dart - page_size caps the
    // server's candidate query before it filters for visibility, so too small
    // a page can come back empty with a non-zero count.
    int pageSize = 20,
  }) async {
    try {
      // Logged either side of the await, deliberately. The Node requests print
      // their URL via ContentValidator and this one printed nothing at all, so
      // a silent log was indistinguishable from three different failures: the
      // call never being made, the viewcache read never completing, and the
      // POST hanging. Now each of those looks different in the console.
      if (kDebugMode) {
        print("[newsfeed] GET page=$page size=$pageSize - reading viewcache");
      }
      final viewCache = await _pendingViewCache();
      if (kDebugMode) {
        print("[newsfeed] POST ${_endpoints.userApiUrl}"
            "${_endpoints.newsfeedDefault} viewcache=${viewCache.length}");
      }
      final response = await _dio.post(
        _endpoints.newsfeedDefault,
        data: {'viewcache': viewCache},
        queryParameters: {'page': page, 'page_size': pageSize},
      );
      if (kDebugMode) {
        final body = response.data;
        final rows = body is Map ? body['results'] : null;
        print("[newsfeed] ${response.statusCode} "
            "type=${body.runtimeType} "
            "count=${body is Map ? body['count'] : 'n/a'}");
        // count mirrors page_size on this endpoint (it counts CANDIDATES,
        // not matches), so logging both together is what made the empty-page
        // cause visible.
        print("[newsfeed] rows=${rows is List ? rows.length : 'n/a'}");
      }
      // Parse FIRST, and never let bookkeeping cost us a page that already
      // arrived. _flushViewCache writes to disk; if that throws, the old shape
      // of this method fell into the catch below and returned an empty page -
      // discarding posts the server had successfully sent. The flush is a
      // side effect, not part of the answer.
      final result = PagedResult.fromDrf(response.data, PostPreview.fromJson);
      try {
        await _flushViewCache(viewCache);
      } catch (e) {
        if (kDebugMode) print("[newsfeed] viewcache flush failed: $e");
      }
      if (kDebugMode) {
        print("[newsfeed] parsed ${result.results.length} posts "
            "(hasNext=${result.hasNext})");
      }
      return result;
    } catch (e) {
      if (kDebugMode) {
        // Named, and with the status when there is one - "ERROR" alone told us
        // nothing while this was being diagnosed.
        print("[newsfeed] request failed: $e");
        if (e is DioException) {
          print("[newsfeed] status=${e.response?.statusCode} "
              "body=${e.response?.data}");
        }
      }
      return PagedResult.empty();
    }
  }

  /// Delivers banked view durations WITHOUT wanting the posts back.
  ///
  /// Needed because the feed request is the only thing that carries a
  /// viewcache and there is no endpoint that takes one on its own - so in a
  /// session that never asks for another page, views are recorded and never
  /// sent. That isn't a rare corner: the newsfeed lives in an IndexedStack
  /// branch whose initState runs once per launch, so a feed short enough to
  /// need no paging (one post will do it) has no second request in it at all.
  ///
  /// page_size 1 because the response is thrown away - the useful work is
  /// save_viewcache_engagements, which the view runs before it builds the
  /// feed queryset, so the payload comes back regardless of how little is
  /// asked for.
  Future<void> flushPendingViewsRequest() async {
    try {
      final viewCache = await _pendingViewCache();
      if (viewCache.isEmpty) return;
      await _dio.post(
        _endpoints.newsfeedDefault,
        data: {'viewcache': viewCache},
        queryParameters: {'page': 1, 'page_size': 1},
      );
      await _flushViewCache(viewCache);
    } catch (e) {
      // Keeping the entries is the whole point of failing quietly here:
      // they'll ride along on the next request that wants them.
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
    }
  }

  /// The view durations banked for whoever is currently acting.
  Future<List<Map<String, dynamic>>> _pendingViewCache() =>
      ViewCache.instance.snapshot(appStore.state.userAuth.user.entityId);

  /// Clears the cache, but ONLY after a request that carried it came back
  /// without throwing - the failure path deliberately keeps the entries so a
  /// dropped connection doesn't silently discard view history (webapp clears
  /// in `.then`, never in `.catch`, for the same reason).
  ///
  /// Skipped when nothing was sent: an empty snapshot means either there was
  /// nothing to flush or nobody is signed in, and in the second case clearing
  /// would throw away another entity's pending entries.
  Future<void> _flushViewCache(List<Map<String, dynamic>> sent) async {
    if (sent.isEmpty) return;
    await ViewCache.instance.clear();
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
          : await _dio
              .delete(_endpoints.newsfeedSaves, data: {'post_id': postId});
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
