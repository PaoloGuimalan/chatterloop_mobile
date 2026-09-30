import 'dart:convert';

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

  /// Group calls used to be announced as "{group name} (Group)"; the name
  /// alone is what every screen shows now, whatever an older app sent.
  static String _withoutGroupSuffix(Object? name) =>
      (name ?? '').toString().replaceFirst(RegExp(r'\s*\(Group\)$'), '');

  final CallerInfo caller;

  /// Every OTHER participant's entityID - used by the caller's own
  /// /u/endcall to know who to notify when they hang up. Not needed by the
  /// callee's UI, kept for parity with the wire shape.
  final List<String> recepients;

  final String? displayImage;

  /// When the server started ringing this call, as it stamped it (ms since
  /// epoch, verbatim). Identifies this RING - see NotificationRenderer's
  /// decline marker. Null from a server that predates it.
  final String? ringStartedAt;

  bool get isGroup => conversationType != "single";

  const IncomingCallAlert({
    required this.conversationID,
    required this.conversationType,
    required this.callType,
    required this.callDisplayName,
    required this.caller,
    this.recepients = const [],
    this.displayImage,
    this.ringStartedAt,
  });

  factory IncomingCallAlert.fromJson(Map<String, dynamic> json) {
    final rawRecepients = json['recepients'];
    return IncomingCallAlert(
      conversationID: (json['conversationID'] ?? '').toString(),
      conversationType: (json['conversationType'] ?? 'single').toString(),
      callType: (json['callType'] ?? 'audio').toString(),
      callDisplayName: _withoutGroupSuffix(json['callDisplayName']),
      caller: json['caller'] is Map
          ? CallerInfo.fromJson(Map<String, dynamic>.from(json['caller']))
          : const CallerInfo(name: '', entityId: ''),
      recepients: rawRecepients is List
          ? rawRecepients.map((e) => e.toString()).toList()
          : const [],
      displayImage: json['displayImage']?.toString(),
      ringStartedAt: json['ringStartedAt']?.toString(),
    );
  }

  /// The same alert from a `call` push's flattened, string-only data block
  /// (server/reusables/hooks/pushnotification.js sendCall) - FCM data can't
  /// nest, so `caller` arrives as callerName/callerEntityID and `recepients`
  /// as JSON. Total, like everything that runs in the background isolate.
  factory IncomingCallAlert.fromPushData(Map<String, dynamic> data) {
    List<String> recepients = const [];
    try {
      final decoded = jsonDecode((data['recepients'] ?? '[]').toString());
      if (decoded is List) {
        recepients = decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    final image = data['displayImage']?.toString();
    return IncomingCallAlert(
      conversationID: (data['conversationID'] ?? '').toString(),
      conversationType: (data['conversationType'] ?? 'single').toString(),
      callType: (data['callType'] ?? 'audio').toString(),
      callDisplayName: _withoutGroupSuffix(data['callDisplayName']),
      caller: CallerInfo(
        name: (data['callerName'] ?? '').toString(),
        entityId: (data['callerEntityID'] ?? '').toString(),
      ),
      recepients: recepients,
      displayImage: image == null || image.isEmpty ? null : image,
      ringStartedAt: data['sentAt']?.toString(),
    );
  }

  /// This alert as `call` push data - the inverse of [fromPushData]. For an
  /// alert that came over SSE while the app was in the background, so it can
  /// ring through exactly the notification a push would have drawn.
  Map<String, dynamic> toPushData() {
    final kind = callType == 'video' ? 'video call' : 'voice call';
    final body =
        isGroup ? '${caller.name} is calling · $kind' : 'Incoming $kind';
    return <String, dynamic>{
      'type': 'call',
      'conversationID': conversationID,
      'conversationType': conversationType,
      'callType': callType,
      'callDisplayName': callDisplayName,
      'callerName': caller.name,
      'callerEntityID': caller.entityId,
      'recepients': jsonEncode(recepients),
      'displayImage':
          displayImage == null || displayImage == 'none' ? '' : displayImage,
      'title': callDisplayName,
      'body': body,
      // The server's stamp when there is one, so a Decline here matches the
      // missed call the server later sends. Without it (an older server) the
      // ring still works; only that match can't be made.
      'sentAt':
          ringStartedAt ?? DateTime.now().millisecondsSinceEpoch.toString(),
    };
  }
}
