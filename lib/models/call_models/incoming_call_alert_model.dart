/// {name, entityID} - identifies whoever placed the call. Same shape is
/// echoed back verbatim in a decline (server/routes/users/index.js's
/// /rejectcall reads decodeToken.caller.entityID to know who to notify).
class CallerInfo {
  final String name;
  final String entityId;

  const CallerInfo({required this.name, required this.entityId});

  factory CallerInfo.fromJson(Map<String, dynamic> json) {
    return CallerInfo(
      name: (json['name'] ?? '').toString(),
      entityId: (json['entityID'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'entityID': entityId};
}

/// A ringing alert on the callee's side. This is exactly the `callmetadata`
/// field of a JWT-decoded `incomingcall` SSE event - server/reusables/hooks/
/// sse.js's ReachCallRecepients relays the caller's own /u/call token
/// payload through unchanged (`createJWTwExp({callmetadata: decodedToken})`),
/// so this model's fromJson doubles as the decoder for both that payload
/// AND (via ICallRequest.toJson in call_signed_payloads_model.dart) the
/// outgoing request the caller originally sent - confirmed against
/// webapp/src/app/tabs/messenger/ConversationV2.tsx's CallRequest({...})
/// call site.
class IncomingCallAlert {
  final String conversationID;

  /// "single" | "group" - conferences/voice channels are a future addition,
  /// not part of this scope (see the mobile calling plan's isGroup-generic
  /// architecture note).
  final String conversationType;

  /// "audio" | "video"
  final String callType;

  /// Caller's own first name for a 1:1 call, or "{group name} (Group)" for
  /// a group call - webapp builds this string caller-side, not the callee,
  /// so it's just displayed as-is here.
  final String callDisplayName;

  final CallerInfo caller;

  /// Every OTHER participant's entityID - used by the caller's own
  /// /u/endcall to know who to notify when they hang up. Not needed by the
  /// callee's UI, kept for parity with the wire shape.
  final List<String> recepients;

  final String? displayImage;

  bool get isGroup => conversationType != "single";

  const IncomingCallAlert({
    required this.conversationID,
    required this.conversationType,
    required this.callType,
    required this.callDisplayName,
    required this.caller,
    this.recepients = const [],
    this.displayImage,
  });

  factory IncomingCallAlert.fromJson(Map<String, dynamic> json) {
    final rawRecepients = json['recepients'];
    return IncomingCallAlert(
      conversationID: (json['conversationID'] ?? '').toString(),
      conversationType: (json['conversationType'] ?? 'single').toString(),
      callType: (json['callType'] ?? 'audio').toString(),
      callDisplayName: (json['callDisplayName'] ?? '').toString(),
      caller: json['caller'] is Map
          ? CallerInfo.fromJson(Map<String, dynamic>.from(json['caller']))
          : const CallerInfo(name: '', entityId: ''),
      recepients: rawRecepients is List
          ? rawRecepients.map((e) => e.toString()).toList()
          : const [],
      displayImage: json['displayImage']?.toString(),
    );
  }
}
