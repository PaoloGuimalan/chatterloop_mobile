// Typed wrappers around the plain-JSON payloads that arrive over SSE for
// each /webrtc/* REST call (server/routes/webrtc/index.js) - every one of
// those REST calls itself only ever resolves {status:true}; the actual
// data comes back later on the SSE stream, confirmed directly against
// server/reusables/hooks/webRTC.js's publish(...) calls and reproduced in
// the M1 spike (lib/views/calls/dev/call_spike_view.dart). rtpCapabilities/
// dtlsParameters/rtpParameters are all kept as raw maps rather than typed
// further - they're consumed directly by mediasoup_client_flutter's own
// fromMap constructors (RtpCapabilities.fromMap, DtlsParameters.fromMap,
// etc.), which already do that parsing; duplicating it here would just be
// two sources of truth for the same shape.

import 'package:chatterloop_app/models/call_models/call_participant_model.dart';

class JoinRoomResponse {
  final Map<String, dynamic> routerRtpCapabilities;
  final String? instance;
  final String? clientId;
  final List<CallParticipant> participants;

  const JoinRoomResponse({
    required this.routerRtpCapabilities,
    this.instance,
    this.clientId,
    this.participants = const [],
  });

  factory JoinRoomResponse.fromJson(Map<String, dynamic> json) {
    final rawParticipants = json['participants'];
    return JoinRoomResponse(
      routerRtpCapabilities: json['routerRtpCapabilities'] is Map
          ? Map<String, dynamic>.from(json['routerRtpCapabilities'])
          : const {},
      instance: json['instance']?.toString(),
      clientId: json['clientId']?.toString(),
      participants: rawParticipants is List
          ? rawParticipants
              .whereType<Map>()
              .map((p) =>
                  CallParticipant.fromJson(Map<String, dynamic>.from(p)))
              .toList()
          : const [],
    );
  }
}

/// `params` is fed straight into device.createSendTransportFromMap /
/// createRecvTransportFromMap - confirmed those expect exactly the nested
/// `response` sub-object (id/iceParameters/iceCandidates/dtlsParameters),
/// not the outer {response, direction, instance, clientId} envelope.
class CreateTransportResponse {
  final String direction; // "send" | "recv"
  final Map<String, dynamic> params;

  const CreateTransportResponse(
      {required this.direction, required this.params});

  factory CreateTransportResponse.fromJson(Map<String, dynamic> json) {
    return CreateTransportResponse(
      direction: (json['direction'] ?? '').toString(),
      params: json['response'] is Map
          ? Map<String, dynamic>.from(json['response'])
          : const {},
    );
  }
}

class ProduceResponse {
  final String id;

  const ProduceResponse(this.id);

  factory ProduceResponse.fromJson(Map<String, dynamic> json) =>
      ProduceResponse((json['id'] ?? '').toString());
}

class ConsumeResponse {
  final String id;
  final String producerId;
  final String kind; // "audio" | "video"
  final Map<String, dynamic> rtpParameters;

  /// webapp's own producer source convention is "microphone"/"camera" -
  /// confirmed NOT consume-blocking either direction, since consume logic
  /// only ever branches on `kind`, never on this string. Kept for parity.
  final String? source;

  const ConsumeResponse({
    required this.id,
    required this.producerId,
    required this.kind,
    required this.rtpParameters,
    this.source,
  });

  factory ConsumeResponse.fromJson(Map<String, dynamic> json) {
    return ConsumeResponse(
      id: (json['id'] ?? '').toString(),
      producerId: (json['producerId'] ?? '').toString(),
      kind: (json['kind'] ?? '').toString(),
      rtpParameters: json['rtpParameters'] is Map
          ? Map<String, dynamic>.from(json['rtpParameters'])
          : const {},
      source: json['source']?.toString(),
    );
  }
}

class NewProducerEvent {
  final String producerId;
  final String kind;
  final String clientId;

  const NewProducerEvent({
    required this.producerId,
    required this.kind,
    required this.clientId,
  });

  factory NewProducerEvent.fromJson(Map<String, dynamic> json) =>
      NewProducerEvent(
        producerId: (json['producerId'] ?? '').toString(),
        kind: (json['kind'] ?? '').toString(),
        clientId: (json['clientId'] ?? '').toString(),
      );
}

/// participant-left's shape is NOT the same as participant-joined's -
/// carries producerIds (so the consuming side knows which consumers to
/// tear down) instead of muted/cameraOff. participant-joined instead
/// decodes directly via CallParticipant.fromJson, no separate class needed.
class ParticipantLeftEvent {
  final String clientId;
  final String? entityId;
  final List<String> producerIds;

  const ParticipantLeftEvent({
    required this.clientId,
    this.entityId,
    this.producerIds = const [],
  });

  factory ParticipantLeftEvent.fromJson(Map<String, dynamic> json) {
    final raw = json['producerIds'];
    return ParticipantLeftEvent(
      clientId: (json['clientId'] ?? '').toString(),
      entityId: json['entityID']?.toString(),
      producerIds:
          raw is List ? raw.map((e) => e.toString()).toList() : const [],
    );
  }
}
