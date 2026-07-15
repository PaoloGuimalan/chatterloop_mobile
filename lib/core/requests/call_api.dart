// Signaling relay endpoints (server/routes/users/index.js) - JWT-signed
// {token} bodies, same convention as ConversationsApi's sendMessageRequest/
// reactToMessageRequest. Distinct from WebrtcApi: nothing here touches
// mediasoup at all, this purely rings/notifies the other participant(s)
// over their existing SSE connection.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/call_models/call_signed_payloads_model.dart';
import 'package:flutter/foundation.dart';

class CallApi {
  final _dio = ApiClient.instance.dio;
  final _endpoints = Endpoints();

  /// Fans out an `incomingcall` SSE event to every recipient - server-side,
  /// routes/users/index.js's /call handler re-derives the recipient list
  /// itself from the conversation's saved participants (GetAllReceivers),
  /// it does NOT trust payload.recepients for that - recepients here is
  /// only relayed through as part of callmetadata for /u/endcall to use
  /// later, and for group calls' "X is calling in Y" display text.
  Future<bool> callRequest(ICallRequest payload) async {
    try {
      final response = await _dio.post(_endpoints.call,
          data: {'token': JwtCodec.sign(payload.toJson())});
      return response.data['status'] != false;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// Only notifies for conversationType=="single" - server-side no-op for
  /// group calls today (see IRejectCallRequest's doc comment).
  Future<bool> rejectCallRequest(IRejectCallRequest payload) async {
    try {
      final response = await _dio.post(_endpoints.rejectCall,
          data: {'token': JwtCodec.sign(payload.toJson())});
      return response.data['status'] != false;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// Only the caller should ever call this (mirrors webapp's isCaller gate
  /// in CallWindow.tsx) - server fans CallRejectNotif out to every id in
  /// recepients with {conversationID, endedBy: the numeric userID}.
  Future<bool> endCallRequest(IEndCallRequest payload) async {
    try {
      final response = await _dio.post(_endpoints.endCall,
          data: {'token': JwtCodec.sign(payload.toJson())});
      return response.data['status'] != false;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }
}
