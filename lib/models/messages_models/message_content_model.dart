import 'package:chatterloop_app/models/messages_models/message_item_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';

class MessageContent {
  String messageID;
  String conversationID;
  String? pendingID;
  String sender;
  List<String> receivers;
  List<String> seeners;
  String content;
  ActionDate messageDate;
  bool isReply;
  String? replyingTo;
  List<ReactionItem>? reactions;
  bool? isDeleted;
  String messageType;
  String conversationType;
  List<MessageContent>? replyedmessage;
  List<UsersContactPreview>? reactionsWithInfo;

  MessageContent(
      this.messageID,
      this.conversationID,
      this.pendingID,
      this.sender,
      this.receivers,
      this.seeners,
      this.content,
      this.messageDate,
      this.isReply,
      this.replyingTo,
      this.reactions,
      this.isDeleted,
      this.messageType,
      this.conversationType,
      this.replyedmessage,
      this.reactionsWithInfo);

  /// Every field is defensive - a real persisted message threw here (Null
  /// is not a subtype of String) despite matching the Mongoose schema on
  /// paper, so something about the actual data doesn't match the fields
  /// this assumed were always present. Degrading missing fields to sane
  /// defaults beats losing the whole conversation to one malformed message.
  factory MessageContent.fromJson(Map<String, dynamic> json) {
    return MessageContent(
        (json["messageID"] ?? "").toString(),
        (json["conversationID"] ?? "").toString(),
        json["pendingID"]?.toString() ?? "",
        (json["sender"] ?? "").toString(),
        json["receivers"] is List
            ? (json["receivers"] as List)
                .map((receiver) => receiver.toString())
                .toList()
            : [],
        json["seeners"] is List
            ? (json["seeners"] as List)
                .map((seener) => seener.toString())
                .toList()
            : [],
        (json["content"] ?? "").toString(),
        ActionDate.fromJson(json["messageDate"]),
        json["isReply"] == true,
        json["replyingTo"]?.toString() ?? "",
        json["reactions"] is List
            ? (json["reactions"] as List)
                .whereType<Map>()
                .map((reaction) =>
                    ReactionItem.fromJson(Map<String, dynamic>.from(reaction)))
                .toList()
            : [],
        json["isDeleted"] ?? false,
        (json["messageType"] ?? "text").toString(),
        (json["conversationType"] ?? "single").toString(),
        json["replyedmessage"] is List
            ? (json["replyedmessage"] as List)
                .whereType<Map>()
                .map((reply) =>
                    MessageContent.fromJson(Map<String, dynamic>.from(reply)))
                .toList()
            : [],
        json["reactionsWithInfo"] is List
            ? (json["reactionsWithInfo"] as List)
                .whereType<Map>()
                .map((reactionInfo) => UsersContactPreview.fromJson(
                    Map<String, dynamic>.from(reactionInfo)))
                .toList()
            : []);
  }
}
