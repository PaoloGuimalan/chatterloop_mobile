// Roster entry for a mediasoup room. Covers two different wire shapes that
// both describe "a participant" - confirmed against real device logs and
// server/reusables/hooks/webRTC.js:
//   - join-room-response's `participants` list: {clientId, username, muted,
//     cameraOff} - no entityID/instance.
//   - participant-joined: {conversationID, username, entityID, clientId,
//     muted, cameraOff, timestamp, instance}.
// participant-left carries a different shape entirely (producerIds instead
// of muted/cameraOff) - see ParticipantLeftEvent in webrtc_payloads_model.dart.

class CallParticipant {
  final String clientId;
  final String? entityId;
  final String? username;
  final bool muted;
  final bool cameraOff;
  final String? instance;

  const CallParticipant({
    required this.clientId,
    this.entityId,
    this.username,
    this.muted = false,
    this.cameraOff = false,
    this.instance,
  });

  factory CallParticipant.fromJson(Map<String, dynamic> json) {
    return CallParticipant(
      clientId: (json['clientId'] ?? '').toString(),
      entityId: json['entityID']?.toString(),
      username: json['username']?.toString(),
      muted: json['muted'] == true,
      cameraOff: json['cameraOff'] == true,
      instance: json['instance']?.toString(),
    );
  }

  CallParticipant copyWith({bool? muted, bool? cameraOff}) {
    return CallParticipant(
      clientId: clientId,
      entityId: entityId,
      username: username,
      muted: muted ?? this.muted,
      cameraOff: cameraOff ?? this.cameraOff,
      instance: instance,
    );
  }
}
