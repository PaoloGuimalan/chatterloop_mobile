// Request bodies for the three JWT-signed /u/call* endpoints
// (server/routes/users/index.js) - all sent as {token: JwtCodec.sign(...)},
// same convention as ISendMessagePayload/IReactToMessageRequest in
// http_models/request_models.dart. Field names/shapes confirmed directly
// against webapp's actual call sites (ConversationV2.tsx's initializeCall,
// Alert.tsx's decline handler, CallWindow.tsx's hangup handler), not just
// the loosely-typed `requests.ts` wrappers (which take `params: any`).

import 'package:chatterloop_app/models/call_models/incoming_call_alert_model.dart';

/// Mirrors ConversationV2.tsx's CallRequest({...}) call site exactly. The
/// callee receives this SAME map back, unchanged, as the `callmetadata`
/// field of the `incomingcall` SSE event (sse.js's ReachCallRecepients
/// relays decodedToken through as-is) - decoded on that end via
/// IncomingCallAlert.fromJson.
class ICallRequest {
  String callType;
  String callDisplayName;
  String conversationType;
  String conversationID;
  CallerInfo caller;
  List<String> recepients;
  String? displayImage;

  ICallRequest({
    required this.callType,
    required this.callDisplayName,
    required this.conversationType,
    required this.conversationID,
    required this.caller,
    required this.recepients,
    this.displayImage,
  });

  Map<String, dynamic> toJson() => {
        'callType': callType,
        'callDisplayName': callDisplayName,
        'conversationType': conversationType,
        'conversationID': conversationID,
        'caller': caller.toJson(),
        'recepients': recepients,
        'displayImage': displayImage ?? 'none',
      };
}

/// Mirrors Alert.tsx's decline handler. `caller` here is the ORIGINAL
/// caller echoed back from the incoming alert (server needs it to know who
/// to notify) - the rejecter's own identity is inferred server-side from
/// the JWT auth (entity_id), not from this payload. Server only actually
/// notifies for conversationType=="single" (routes/users/index.js's
/// /rejectcall) - group-call decline is a known no-op today, tracked as an
/// M10 hardening item.
class IRejectCallRequest {
  String conversationType;
  String conversationID;
  CallerInfo caller;

  IRejectCallRequest({
    required this.conversationType,
    required this.conversationID,
    required this.caller,
  });

  Map<String, dynamic> toJson() => {
        'conversationType': conversationType,
        'conversationID': conversationID,
        'caller': caller.toJson(),
      };
}

/// Mirrors CallWindow.tsx's hangup handler. Only ever sent by whichever
/// side placed the call (webapp gates this on isCaller) - server fans
/// CallRejectNotif out to every id in `recepients` with {conversationID,
/// endedBy: the caller's numeric userID}, which is a different id space than
/// rejectedBy above (compare endedBy against UserAccount.id, not
/// .entityId - see the mobile calling plan's id-space note).
class IEndCallRequest {
  String conversationID;
  String conversationType;
  List<String> recepients; // entity ids the caller notifies on hangup

  IEndCallRequest({
    required this.conversationID,
    required this.conversationType,
    required this.recepients,
  });

  Map<String, dynamic> toJson() => {
        'conversationID': conversationID,
        'conversationType': conversationType,
        'recepients': recepients,
      };
}
