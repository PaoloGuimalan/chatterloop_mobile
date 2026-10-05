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

/// One "is typing" ping, from the `istyping_broadcast` SSE event.
///
/// The server's /m/istypingbroadcast now sends the typer's identity with it,
/// so a row can say who is typing and draw their face without a member list.
/// An older server sent only the ACCOUNT [userID] and the conversation, so
/// every field past those two is optional and callers fall back to the
/// conversation's members, then to "someone". The webapp reads the same
/// payload (src/reusables/hooks/typing.ts).
class IsTypingMetaData {
  /// The ACCOUNT id - all an older server sends.
  String userID;
  String conversationID;

  /// The acting ENTITY id (a page typing as itself is not its owner). Prefer
  /// it to [userID] wherever it is present - it is what members and message
  /// senders are keyed by.
  final String? entityID;
  final String? displayName;
  final String? profile;

  /// 'user' / 'realm' / 'bot'.
  final String? entityType;

  Map<String, dynamic> toJson() {
    return {
      "userID": userID,
      "conversationID": conversationID,
      if (entityID != null) "entityID": entityID,
      if (displayName != null) "displayName": displayName,
      if (profile != null) "profile": profile,
      if (entityType != null) "entityType": entityType,
    };
  }

  IsTypingMetaData(this.userID, this.conversationID,
      {this.entityID, this.displayName, this.profile, this.entityType});

  /// One typer per (person, conversation): the entity when the ping names it,
  /// else the account.
  String get key =>
      "${(entityID ?? "").isNotEmpty ? entityID : userID}|$conversationID";

  factory IsTypingMetaData.fromJson(Map<String, dynamic> json) {
    String? text(String field) {
      final value = json[field]?.toString();
      return value == null || value.isEmpty ? null : value;
    }

    return IsTypingMetaData(
      (json["userID"] ?? "").toString(),
      (json["conversationID"] ?? "").toString(),
      entityID: text("entityID"),
      displayName: text("displayName"),
      profile: text("profile"),
      entityType: text("entityType"),
    );
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
