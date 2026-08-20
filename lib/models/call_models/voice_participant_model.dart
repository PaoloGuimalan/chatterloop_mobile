// One occupant of a voice room, as the PRESENCE payloads describe them -
// distinct from CallParticipant, which covers mediasoup's own roster shapes
// (join-room-response / participant-joined, camelCase `clientId`, muted and
// cameraOff). These come from /u/notify-voice-join's fan-out and from the
// `voice_participants` array on a conversation or channel row, both of which
// use `clientID` and carry no media state at all.

class VoiceParticipant {
  /// The only field the presence events guarantee: "update_participants"
  /// removes by clientId alone, which is why it, not entityId, is the key.
  final String clientId;

  /// Display name, when the payload carried one. Null for a participant
  /// restored from an ids-only source, so anything rendering it must have a
  /// fallback - see VoiceRoomPresence.seed.
  final String? username;

  final String? entityId;
  final String? profile;

  const VoiceParticipant({
    required this.clientId,
    this.username,
    this.entityId,
    this.profile,
  });

  /// Tolerant of both casings: the server writes `clientID`/`entityID`, but
  /// the app's own webrtc payloads use `clientId`, and this shape is read
  /// from both a REST row and an SSE frame.
  factory VoiceParticipant.fromJson(Map<String, dynamic> json) {
    return VoiceParticipant(
      clientId: (json["clientID"] ?? json["clientId"] ?? "").toString(),
      username: json["username"]?.toString(),
      entityId: (json["entityID"] ?? json["entityId"])?.toString(),
      profile: json["profile"]?.toString(),
    );
  }

  /// Same person, keeping whichever details are already known. A later
  /// snapshot that only knows the clientId must not blank out a username an
  /// earlier event supplied.
  VoiceParticipant mergedWith(VoiceParticipant? existing) {
    if (existing == null) return this;
    return VoiceParticipant(
      clientId: clientId,
      username: username ?? existing.username,
      entityId: entityId ?? existing.entityId,
      profile: profile ?? existing.profile,
    );
  }
}
