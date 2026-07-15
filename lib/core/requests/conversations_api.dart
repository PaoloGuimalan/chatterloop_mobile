// Conversation list + thread + messaging endpoints (Node backend). Mirrors
// chatterloop_mobile/lib/services/conversations_api.dart's role.

import 'dart:convert';

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/utils/content_validator.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/http_models/request_models.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/messages_models/messages_list_model.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ConversationsApi {
  final _dio = ApiClient.instance.dio;
  final _endpoints = Endpoints();

  /// type is one of "common" | "direct" | "groups" | "servers" (matches
  /// the tab filter on webapp's Messages screen). page/range/type are all
  /// sent as headers, not query params - that's how the real endpoint
  /// reads them. Response is plain JSON at response.data.result (NOT the
  /// JWT-signed-token-wrapped shape most other /m and /u endpoints use).
  Future<({List<MessageItem> items, int total, String? next})?>
      getConversationListRequest(
          {String type = "common", int page = 1, int range = 20}) async {
    ContentValidator()
        .printer('${_endpoints.apiUrl}${_endpoints.getConversationList}');
    try {
      final response = await _dio.get(_endpoints.getConversationList,
          options: Options(headers: {
            'type': type,
            'page': page.toString(),
            'range': range.toString(),
          }));

      final result = response.data["result"];
      if (result is! Map) return null;
      final items = result["items"];
      if (items is! List) return null;

      return (
        items: items
            .whereType<Map>()
            .map(
                (item) => MessageItem.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
        total: _intValue(result["total"]),
        next: result["next"]?.toString(),
      );
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  /// One-time snapshot of which contacts are currently online, plus a
  /// last-seen timestamp for the rest (GET /u/activecontacts) - matches
  /// webapp's ActiveContactsRequest, called once on app init. Live changes
  /// after that arrive via individual "active_users" SSE events instead
  /// (see sse_events.dart), since this snapshot alone would go stale the
  /// moment anyone connects/disconnects. Plain {status, result: [{_id,
  /// sessionStatus, sessiondate}]} JSON, not JWT-signed.
  Future<Map<String, PresenceInfo>> getActiveContactsRequest() async {
    try {
      final response = await _dio.get(_endpoints.activeContacts);
      if (response.data["status"] != true) return {};
      final result = response.data["result"];
      if (result is! List) return {};
      final presence = <String, PresenceInfo>{};
      for (final row in result.whereType<Map>()) {
        final entityId = row["_id"]?.toString();
        if (entityId == null || entityId.isEmpty) continue;
        final online = row["sessionStatus"] == true;
        final sessiondate =
            row["sessiondate"] is Map ? row["sessiondate"] as Map : null;
        presence[entityId] = PresenceInfo(
          online: online,
          lastSeen: online
              ? null
              : parseServerTimestamp(sessiondate?["date"]?.toString()),
        );
      }
      return presence;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return {};
    }
  }

  int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  /// Must resolve before initConversationRequest/getConversationInfoRequest
  /// are called - see the doc comment on Endpoints.getConversationSetup.
  /// Unlike those two, the response here is plain JSON, not a signed JWT.
  Future<Map<String, dynamic>?> getConversationSetupRequest(
      String conversationID) async {
    ContentValidator().printer(
        '${_endpoints.apiUrl}${_endpoints.getConversationSetup}$conversationID');
    try {
      final response =
          await _dio.get('${_endpoints.getConversationSetup}$conversationID');
      if (response.data["status"] != true) return null;
      final result = response.data["result"];
      return result is Map ? Map<String, dynamic>.from(result) : null;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  /// page is required, not optional - routes/users/index.js's
  /// GET /initConversation/:conversationID does
  /// `$skip: (parseInt(page) - 1) * parseInt(range)` with no fallback.
  /// Without a page header that's NaN, the Mongo aggregation rejects, and
  /// the route responds {status:false} - silently, no thrown exception on
  /// this end, which is why this returned null with nothing printed.
  /// Matches webapp's InitConversationRequest (page: page || 1).
  Future<EncodedResponse?> initConversationRequest(
      String conversationID, int range,
      {int page = 1}) async {
    ContentValidator().printer(
        '${_endpoints.apiUrl}${_endpoints.initConversation}$conversationID');
    try {
      final response =
          await _dio.get('${_endpoints.initConversation}$conversationID',
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

  Future<EncodedResponse?> getConversationInfoRequest(
      String conversationID, String conversationType) async {
    ContentValidator().printer(
        '${_endpoints.apiUrl}${_endpoints.getConversationInfo}$conversationID/$conversationType');
    try {
      final response = await _dio.get(
          '${_endpoints.getConversationInfo}$conversationID/$conversationType');
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

  Future<EncodedResponse?> seenNewMessagesRequest(
      ISeenNewMessagesRequest payload, int range) async {
    ContentValidator()
        .printer('${_endpoints.apiUrl}${_endpoints.seenNewMessages}');
    try {
      final response = await _dio.post(_endpoints.seenNewMessages,
          data: {"token": JwtCodec.sign(payload.toJson())},
          options: Options(headers: {'range': range.toString()}));
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

  Future<EncodedResponse?> isTypingRequest(IisTypingRequest payload) async {
    ContentValidator()
        .printer('${_endpoints.apiUrl}${_endpoints.postIsTyping}');
    try {
      final response = await _dio.post(_endpoints.postIsTyping,
          data: {"token": JwtCodec.sign(payload.toJson())});
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

  Future<EncodedResponse?> sendMessageRequest(
      ISendMessagePayload payload) async {
    ContentValidator()
        .printer('${_endpoints.apiUrl}${_endpoints.sendNewMessage}');
    try {
      final response = await _dio.post(_endpoints.sendNewMessage,
          data: {"token": JwtCodec.sign(payload.toJson())});
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

  /// Matches webapp's ReactToMessageRequest (POST /m/addreaction, JWT-signed
  /// body, x-access-token auth via ApiClient's interceptor) - server just
  /// pushes newreaction onto the message's reactions array and broadcasts a
  /// bare SSE signal (routes/messages/index.js), no data comes back in the
  /// response worth reading, hence the bool return.
  Future<bool> reactToMessageRequest(IReactToMessageRequest payload) async {
    ContentValidator().printer('${_endpoints.apiUrl}${_endpoints.addReaction}');
    try {
      final response = await _dio.post(_endpoints.addReaction,
          data: {"token": JwtCodec.sign(payload.toJson())});
      return response.data["status"] != false;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  Future<MessageBasedResponse?> postReplyAssistRequest(
      String conversationID, List<ReplyAssistContext> messageIDs) async {
    ContentValidator().printer('${_endpoints.apiUrl}${_endpoints.replyAssist}');
    try {
      final response = await _dio.post(_endpoints.replyAssist,
          data: jsonEncode({
            "conversationID": conversationID,
            "messageIDs": messageIDs.map((mp) => mp.toJson()).toList(),
          }));
      if (response.data["status"] == false) return null;
      return MessageBasedResponse(response.data["message"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  /// Get-or-create a direct-message conversation with another entity -
  /// matches webapp's CreateInitialConversation, used by a profile's
  /// "Message" button when there's no existing conversation/connection to
  /// route to yet.
  Future<String?> createInitialConversationRequest(String otherEntityID) async {
    try {
      final response =
          await _dio.post('/m/crtc', data: {'otherEntityID': otherEntityID});
      if (response.data["status"] == false) return null;
      return response.data["conversationID"]?.toString();
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }
}
