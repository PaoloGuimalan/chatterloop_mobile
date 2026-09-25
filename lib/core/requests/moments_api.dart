// Moments and Thoughts: reads/updates on user_service
// (newsfeed/moment_views.py), creation on Node (/posts/moments/create,
// /posts/thoughts/create - JWT-signed like /posts/createpost). Mirrors
// webapp's requests.ts (GetMomentTrayRequest ... SendEphemeralReplyRequest).
//
// Reacting reuses NewsfeedApi.setPostReactionRequest (the post reaction
// endpoint gates ephemeral posts itself) and deleting reuses
// NewsfeedApi.deletePostRequest.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/post_models/ephemeral_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// "moment" or "thought" - the path segment the seen/viewers endpoints share.
enum EphemeralKind { moment, thought }

class MomentsApi {
  final _dio = ApiClient.userService.dio;
  final _nodeDio = ApiClient.instance.dio;
  final _endpoints = Endpoints();

  static const _base = '/api/newsfeed';

  void _log(Object e) {
    if (kDebugMode) {
      print("ERROR");
      print(e);
    }
  }

  /// The server's own refusal message, when it sent one.
  static String? errorMessage(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data["message"] != null) {
        return data["message"].toString();
      }
      if (data is String && data.isNotEmpty && data.length < 200) return data;
    }
    return null;
  }

  Future<MomentTray> getTrayRequest() async {
    try {
      final response = await _dio.get('$_base/moments/tray/');
      return MomentTray.fromJson(Map<String, dynamic>.from(response.data));
    } catch (e) {
      _log(e);
      return MomentTray.empty;
    }
  }

  /// Rings for a batch of avatars. Absent = no live moment.
  Future<Map<String, MomentRing>> getRingsRequest(
      List<String> entityIds) async {
    final ids = entityIds.where((id) => id.isNotEmpty).toSet().take(100);
    if (ids.isEmpty) return const {};
    try {
      final response = await _dio.get('$_base/moments/status/',
          queryParameters: {'entity_ids': ids.join(",")});
      final results = response.data is Map ? response.data["results"] : null;
      if (results is! Map) return const {};
      return {
        for (final entry in results.entries)
          if (entry.value is Map && entry.value["has_moment"] == true)
            entry.key.toString():
                MomentRing.fromJson(Map<String, dynamic>.from(entry.value)),
      };
    } catch (e) {
      _log(e);
      return const {};
    }
  }

  /// One entity's live moments, oldest first (play order).
  Future<List<Moment>> getEntityMomentsRequest(String entityId) async {
    try {
      final response = await _dio.get('$_base/moments/entity/$entityId/');
      final results = response.data is Map ? response.data["results"] : null;
      if (results is! List) return const [];
      return results
          .whereType<Map>()
          .map((m) => Moment.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      _log(e);
      return const [];
    }
  }

  /// Your expired moments, newest first - the profile's Archived > Moments.
  Future<({List<Moment> items, bool hasMore})> getArchiveRequest(
      {int page = 1}) async {
    try {
      final response = await _dio
          .get('$_base/archive/moments/', queryParameters: {'page': page});
      final data = response.data is Map ? response.data as Map : const {};
      final results = data["results"];
      return (
        items: results is List
            ? results
                .whereType<Map>()
                .map((m) => Moment.fromJson(Map<String, dynamic>.from(m)))
                .toList()
            : const <Moment>[],
        hasMore: data["next"] != null,
      );
    } catch (e) {
      _log(e);
      return (items: const <Moment>[], hasMore: false);
    }
  }

  Future<void> markSeenRequest(EphemeralKind kind, String postId,
      {int duration = 0}) async {
    try {
      await _dio.post('$_base/${kind.name}s/$postId/seen/',
          data: {'duration': duration});
    } catch (e) {
      _log(e);
    }
  }

  /// [filter]: "all" | "reacted" | "replied".
  Future<EphemeralViewers> getViewersRequest(EphemeralKind kind, String postId,
      {String filter = "all", int page = 1}) async {
    try {
      final response = await _dio.get('$_base/${kind.name}s/$postId/viewers/',
          queryParameters: {'filter': filter, 'page': page});
      return EphemeralViewers.fromJson(
          Map<String, dynamic>.from(response.data));
    } catch (e) {
      _log(e);
      return EphemeralViewers.empty;
    }
  }

  /// [archive] ends it now - it leaves the board and moves to the archive.
  Future<bool> updateMomentRequest(String postId,
      {String? privacyStatus, bool? allowReplies, bool? archive}) async {
    try {
      await _dio.put('$_base/moments/$postId/', data: {
        if (privacyStatus != null) 'privacy_status': privacyStatus,
        if (allowReplies != null) 'allow_replies': allowReplies,
        if (archive != null) 'archive': archive,
      });
      return true;
    } catch (e) {
      _log(e);
      return false;
    }
  }

  /// ONE uploaded photo/video ([mediaUrl] + [mediaType] from
  /// ProfileApi.uploadMediaRequest) OR one shared post ([sharedPostId]).
  /// Returns null on success, else the reason.
  ///
  /// A moment made in the editor (an MP4 rendered on the device) also sends
  /// its [poster] (an uploaded JPEG), what it was made from ([source]:
  /// "photo" | "video") and whether it has sound ([hasAudio]). The server
  /// then checks the file is a streamable H.264/AAC MP4 of at most 2 minutes.
  Future<String?> createMomentRequest({
    String? mediaUrl,
    String? mediaType,
    String? fileName,
    String? sharedPostId,
    ({String url, int width, int height})? poster,
    String? source,
    bool? hasAudio,
    required String caption,
    required String privacy,
    required bool allowReplies,
  }) async {
    final payload = {
      'content': {
        if (mediaUrl != null)
          'reference': {
            'reference': mediaUrl,
            'referenceMediaType': mediaType,
            'name': fileName,
          },
        if (sharedPostId != null) 'sharedPostID': sharedPostId,
        'data': caption,
      },
      'privacy': {'status': privacy},
      'allowReplies': allowReplies,
      if (poster != null)
        'poster': {'url': poster.url, 'w': poster.width, 'h': poster.height},
      if (source != null) 'source': source,
      if (hasAudio != null) 'hasAudio': hasAudio,
    };
    try {
      final response = await _nodeDio.post('/posts/moments/create',
          data: {'token': JwtCodec.sign(payload)});
      if (response.data["status"] == false) {
        return (response.data["message"] ?? "Couldn't share your moment.")
            .toString();
      }
      return null;
    } catch (e) {
      _log(e);
      return errorMessage(e) ?? "Couldn't share your moment.";
    }
  }

  Future<ThoughtsRail> getThoughtsRailRequest() async {
    try {
      final response = await _dio.get('$_base/thoughts/rail/');
      return ThoughtsRail.fromJson(Map<String, dynamic>.from(response.data));
    } catch (e) {
      _log(e);
      return ThoughtsRail.empty;
    }
  }

  /// Live thoughts for a batch of entities, keyed by entity id.
  Future<Map<String, Thought>> getThoughtsRequest(
      List<String> entityIds) async {
    final ids = entityIds.where((id) => id.isNotEmpty).toSet().take(100);
    if (ids.isEmpty) return const {};
    try {
      final response = await _dio.get('$_base/thoughts/',
          queryParameters: {'entity_ids': ids.join(",")});
      final results = response.data is Map ? response.data["results"] : null;
      if (results is! Map) return const {};
      return {
        for (final entry in results.entries)
          if (entry.value is Map)
            entry.key.toString():
                Thought.fromJson(Map<String, dynamic>.from(entry.value)),
      };
    } catch (e) {
      _log(e);
      return const {};
    }
  }

  /// Your own thought, with its view count.
  Future<Thought?> getOwnThoughtRequest(String postId) async {
    try {
      final response = await _dio.get('$_base/thoughts/$postId/');
      return Thought.fromJson(Map<String, dynamic>.from(response.data));
    } catch (e) {
      _log(e);
      return null;
    }
  }

  /// Returns null on success, else the reason. A new thought replaces
  /// (expires) your previous one server-side.
  Future<String?> createThoughtRequest(
      {required String text, String? mood, required String privacy}) async {
    final payload = {
      'content': {'text': text, 'mood': mood},
      'privacy': {'status': privacy},
    };
    try {
      final response = await _nodeDio.post('/posts/thoughts/create',
          data: {'token': JwtCodec.sign(payload)});
      if (response.data["status"] == false) {
        return (response.data["message"] ?? "Couldn't share your thought.")
            .toString();
      }
      return null;
    } catch (e) {
      _log(e);
      return errorMessage(e) ?? "Couldn't share your thought.";
    }
  }

  /// Edits in place - the timer and views are kept. Null on success.
  Future<String?> updateThoughtRequest(String postId,
      {required String text, String? mood, required String privacy}) async {
    try {
      await _dio.put('$_base/thoughts/$postId/',
          data: {'text': text, 'mood': mood, 'privacy_status': privacy});
      return null;
    } catch (e) {
      _log(e);
      return errorMessage(e) ?? "Couldn't update your thought.";
    }
  }

  /// A reply to someone's moment / thought: into your DM with its author
  /// (opened like /m/crtc when there is none), carrying `replyingTo
  /// {type, id}` so the chat shows what it answers. Null on success.
  Future<String?> sendReplyRequest({
    required String authorEntityId,
    required EphemeralKind kind,
    required String postId,
    required String content,
  }) async {
    final conversationId = await ConversationsApi()
        .createInitialConversationRequest(authorEntityId);
    if (conversationId == null || conversationId.isEmpty) {
      return "Couldn't open your chat with them.";
    }
    final payload = {
      'conversationID': conversationId,
      'pendingID': 'reply_${DateTime.now().millisecondsSinceEpoch}',
      'receivers': [],
      'content': content,
      'isReply': true,
      'replyingTo': {'type': kind.name, 'id': postId},
      'messageType': 'text',
      'conversationType': 'single',
    };
    try {
      final response = await _nodeDio.post(_endpoints.sendNewMessage,
          data: {'token': JwtCodec.sign(payload)});
      if (response.data["status"] == false) {
        return (response.data["message"] ?? "Couldn't send that reply.")
            .toString();
      }
      return null;
    } catch (e) {
      _log(e);
      return errorMessage(e) ?? "Couldn't send that reply.";
    }
  }
}
