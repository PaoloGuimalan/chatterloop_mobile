// Conversation list + thread + messaging endpoints (Node backend). Mirrors
// chatterloop_mobile/lib/services/conversations_api.dart's role.

import 'dart:convert';

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/utils/content_validator.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/http_models/request_models.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ConversationsApi {
  final _dio = ApiClient.instance.dio;
  final _endpoints = Endpoints();

  Future<EncodedResponse?> getConversationListRequest() async {
    ContentValidator()
        .printer('${_endpoints.apiUrl}${_endpoints.getConversationList}');
    try {
      final response = await _dio.get(_endpoints.getConversationList);
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

  Future<EncodedResponse?> initConversationRequest(
      String conversationID, int range) async {
    ContentValidator().printer(
        '${_endpoints.apiUrl}${_endpoints.initConversation}$conversationID');
    try {
      final response = await _dio.get(
          '${_endpoints.initConversation}$conversationID',
          options: Options(headers: {'range': range.toString()}));
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
}
