import 'package:chatterloop_app/models/messages_models/message_item_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';

/// Matches webapp's IConversation shape (interfaces.ts) as returned by the
/// real GET /m/conversations endpoint - NOT the old Node
/// /u/initConversationList shape this file previously held (that endpoint
/// has zero call sites in the live webapp).
///
/// The backend now resolves "what to display" server-side into a single
/// `details` object regardless of conversation type (for a single chat:
/// the other person; for a group: the group's own name/avatar) - so
/// widgets no longer need to branch on conversationType to pick an avatar
/// or title the way the old shape (separate users/groupdetails/
/// serverdetails) required.
class MessageItem {
  final String id;
  final String conversationID;
  final String conversationType;
  final String sortID;
  final String messageID;
  final String sender;
  final List<String> receivers;
  final List<String> seeners;
  final String content;
  final ActionDate messageDate;
  final bool isReply;
  final String replyingTo;
  final List<ReactionItem> reactions;
  final bool isDeleted;
  final String messageType;
  final int unread;
  final ConversationDisplayDetails details;

  const MessageItem({
    required this.id,
    required this.conversationID,
    required this.conversationType,
    required this.sortID,
    required this.messageID,
    required this.sender,
    required this.receivers,
    required this.seeners,
    required this.content,
    required this.messageDate,
    required this.isReply,
    required this.replyingTo,
    required this.reactions,
    required this.isDeleted,
    required this.messageType,
    required this.unread,
    required this.details,
  });

  factory MessageItem.fromJson(Map<String, dynamic> json) {
    return MessageItem(
      id: (json["_id"] ?? json["conversationID"] ?? "").toString(),
      conversationID: (json["conversationID"] ?? "").toString(),
      conversationType: (json["conversationType"] ?? "single").toString(),
      sortID: (json["sortID"] ?? "").toString(),
      messageID: (json["messageID"] ?? "").toString(),
      sender: (json["sender"] ?? "").toString(),
      receivers: (json["receivers"] as List? ?? [])
          .map((receiver) => receiver.toString())
          .toList(),
      seeners: (json["seeners"] as List? ?? [])
          .map((seener) => seener.toString())
          .toList(),
      content: (json["content"] ?? "").toString(),
      messageDate: _parseDate(json["messageDate"]),
      isReply: json["isReply"] == true,
      replyingTo: (json["replyingTo"] ?? "").toString(),
      reactions: json["reactions"] != null
          ? (json["reactions"] as List)
              .map((r) => ReactionItem.fromJson(r))
              .toList()
          : const [],
      isDeleted: json["isDeleted"] == true,
      messageType: (json["messageType"] ?? "text").toString(),
      unread: _intValue(json["unread"]),
      details: ConversationDisplayDetails.fromJson(json["details"] is Map
          ? Map<String, dynamic>.from(json["details"])
          : const {}),
    );
  }

  static int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  /// messageDate's exact wire format wasn't confirmed byte-for-byte against
  /// a live response - accept either the {date, time} map shape used
  /// elsewhere in this app or a raw ISO/string timestamp, so parsing
  /// degrades gracefully instead of throwing either way.
  static ActionDate _parseDate(dynamic raw) {
    if (raw is Map) {
      return ActionDate.fromJson(Map<String, dynamic>.from(raw));
    }
    return ActionDate(raw?.toString() ?? "", "");
  }
}

class ConversationDisplayDetails {
  final String id;
  final String entityId;
  final String username;
  final String displayName;
  final String? profile;

  const ConversationDisplayDetails({
    required this.id,
    required this.entityId,
    required this.username,
    required this.displayName,
    this.profile,
  });

  factory ConversationDisplayDetails.fromJson(Map<String, dynamic> json) {
    return ConversationDisplayDetails(
      id: (json["id"] ?? "").toString(),
      entityId: (json["entity_id"] ?? "").toString(),
      username: (json["username"] ?? "").toString(),
      displayName: (json["display_name"] ?? "").toString(),
      profile: json["profile"]?.toString(),
    );
  }
}
