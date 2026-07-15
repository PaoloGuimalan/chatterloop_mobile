class IsReplying {
  bool isReply;
  String replyingTo;

  IsReplying(this.isReply, this.replyingTo);

  factory IsReplying.fromJson(Map<String, dynamic> json) {
    return IsReplying(json["isReply"], json["replyingTo"]);
  }
}

class PendingMessages {
  String conversationID;
  String pendingID;
  String content;
  String type;

  PendingMessages(this.conversationID, this.pendingID, this.content, this.type);

  factory PendingMessages.fromJson(Map<String, dynamic> json) {
    return PendingMessages(json["conversationID"], json["pendingID"],
        json["content"], json["type"]);
  }
}

class IsTypingMetaData {
  String userID;
  String conversationID;

  Map<String, dynamic> toJson() {
    return {"userID": userID, "conversationID": conversationID};
  }

  IsTypingMetaData(this.userID, this.conversationID);

  factory IsTypingMetaData.fromJson(Map<String, dynamic> json) {
    return IsTypingMetaData(json["userID"], json["conversationID"]);
  }
}

/// Online status + last-seen timestamp for one entity - stored in
/// AppState.presence, keyed by entity id.
class PresenceInfo {
  final bool online;

  /// When they were last seen - only meaningful while !online (matches
  /// webapp's userSessionStatusFromContacts, which only ever reads
  /// sessiondate for the "not currently active" case). Null when no
  /// session record exists for them at all yet (never connected).
  final DateTime? lastSeen;

  const PresenceInfo({required this.online, this.lastSeen});
}

/// Payload for a single "active_users" SSE event - server/reusables/hooks
/// /sse.js's UpdateContactswSessionStatus sends {_id: entityID,
/// sessionStatus: bool, sessiondate}, JWT-wrapped as {user: {...}}.
class ActiveUserUpdate {
  String entityId;
  bool isOnline;
  DateTime? lastSeen;

  ActiveUserUpdate(this.entityId, this.isOnline, [this.lastSeen]);
}

class ReplyAssistContext {
  bool me;
  String messageID;

  ReplyAssistContext(this.me, this.messageID);

  Map<String, dynamic> toJson() {
    return {"me": me, "messageID": messageID};
  }

  factory ReplyAssistContext.fromJson(Map<String, dynamic> json) {
    return ReplyAssistContext(json["me"], json["messageID"]);
  }
}
