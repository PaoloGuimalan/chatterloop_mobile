// The mediasoup REST half of calling (server/routes/webrtc/index.js) -
// plain JSON bodies, ordinary jwtchecker auth via ApiClient's interceptor
// (unlike CallApi's three endpoints, nothing here is JWT-signed in the
// body). Every one of these calls only ever resolves {status:true} - the
// actual payload (router capabilities, transport params, consumer params,
// roster events) arrives later over the app's existing global SSE
// connection, so callers must correlate outgoing calls with incoming SSE
// events themselves (CallController, M3, via Completers - same pattern
// proven in lib/views/calls/dev/call_spike_view.dart).

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:flutter/foundation.dart';

class WebrtcApi {
  final _dio = ApiClient.instance.dio;
  final _endpoints = Endpoints();

  /// Server also replays `new_producer` over SSE for anyone already
  /// producing in the room (late-join sync) - no separate "list existing
  /// producers" call exists or is needed.
  Future<bool> joinRoomRequest({
    required String conversationID,
    required List<String> members,
    required bool muted,
    required bool cameraOff,
    required String username,
    required String clientId,
  }) =>
      _post(_endpoints.webrtcJoinRoom, {
        'conversationID': conversationID,
        'members': members,
        'muted': muted,
        'cameraOff': cameraOff,
        'username': username,
        'clientId': clientId,
      });

  /// One send + one recv transport per session total, regardless of
  /// participant count - mediasoup's SFU model, not per-peer mesh. Call
  /// this twice at join time (direction: "send" then "recv"), never again
  /// afterwards for the same session.
  Future<bool> createTransportRequest({
    required String conversationID,
    required String direction, // "send" | "recv"
    required String clientId,
  }) =>
      _post(_endpoints.webrtcCreateTransport, {
        'conversationID': conversationID,
        'direction': direction,
        'clientId': clientId,
      });

  Future<bool> transportConnectRequest({
    required String conversationID,
    required String transportId,
    required Map<String, dynamic> dtlsParameters,
    required String clientId,
  }) =>
      _post(_endpoints.webrtcTransportConnect, {
        'conversationID': conversationID,
        'transportId': transportId,
        'dtlsParameters': dtlsParameters,
        'clientId': clientId,
      });

  Future<bool> produceRequest({
    required String conversationID,
    required String transportId,
    required String kind, // "audio" | "video"
    required Map<String, dynamic> rtpParameters,
    required List<String> members,
    required String clientId,
    Map<String, dynamic> appData = const {},
  }) =>
      _post(_endpoints.webrtcProduce, {
        'conversationID': conversationID,
        'transportId': transportId,
        'kind': kind,
        'rtpParameters': rtpParameters,
        'members': members,
        'clientId': clientId,
        'appData': appData,
      });

  Future<bool> consumeRequest({
    required String conversationID,
    required String transportId,
    required String producerId,
    required Map<String, dynamic> rtpCapabilities,
    required String clientId,
  }) =>
      _post(_endpoints.webrtcConsume, {
        'conversationID': conversationID,
        'transportId': transportId,
        'producerId': producerId,
        'rtpCapabilities': rtpCapabilities,
        'clientId': clientId,
      });

  Future<bool> closeProducerRequest({
    required String conversationID,
    required String producerId,
    required String clientId,
  }) =>
      _post(_endpoints.webrtcCloseProducer, {
        'conversationID': conversationID,
        'producerId': producerId,
        'clientId': clientId,
      });

  /// recipients (entity ids to notify of the departure) is optional -
  /// server falls back to the conversation's own saved participant list
  /// when omitted (server/routes/webrtc/index.js's leave-room handler).
  Future<bool> leaveRoomRequest({
    required String conversationID,
    required String clientId,
    List<String>? recipients,
  }) =>
      _post(_endpoints.webrtcLeaveRoom, {
        'conversationID': conversationID,
        'clientId': clientId,
        if (recipients != null) 'recipients': recipients,
      });

  Future<bool> participantStatusRequest({
    required String conversationID,
    required String clientId,
    required bool muted,
    required bool cameraOff,
  }) =>
      _post(_endpoints.webrtcParticipantStatus, {
        'conversationID': conversationID,
        'clientId': clientId,
        'muted': muted,
        'cameraOff': cameraOff,
      });

  /// instance is the pod name this client was previously connected to
  /// (persisted alongside clientId across the reconnect attempt) - only
  /// meaningful here, matches resolveTargetPod's explicitInstance override
  /// in server/routes/webrtc/index.js. M9's concern; included now so the
  /// API surface doesn't need revisiting when reconnect lands.
  Future<bool> reconnectRequest({
    required String conversationID,
    required String clientId,
    String? instance,
  }) =>
      _post(_endpoints.webrtcReconnect, {
        'conversationID': conversationID,
        'clientId': clientId,
        if (instance != null) 'instance': instance,
      });

  /// Unlike every other method here, this is a plain synchronous GET - no
  /// SSE round-trip, since it's static server config, not room state.
  /// webapp fetches this once before joining and passes the "camera" list
  /// straight through to transport.produce()'s encodings param when
  /// producing video - matches server/reusables/hooks/webRTC.js's
  /// CAMERA_ENCODINGS (3-layer simulcast: rid r0/r1/r2). Returns an empty
  /// list on any failure so callers can fall back to producing without
  /// explicit encodings rather than blocking the whole call on this.
  Future<List<Map<String, dynamic>>> getCameraEncodingsRequest() async {
    try {
      final response = await _dio.get(_endpoints.webrtcEncodings);
      final camera = response.data?['camera'];
      if (camera is! List) return const [];
      return camera.whereType<Map>().map(Map<String, dynamic>.from).toList();
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return const [];
    }
  }

  Future<bool> _post(String path, Map<String, dynamic> data) async {
    try {
      final response = await _dio.post(path, data: data);
      return response.data?['status'] != false;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }
}
