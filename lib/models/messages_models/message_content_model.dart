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

  factory MessageContent.fromJson(Map<String, dynamic> json) {
    return MessageContent(
        json["messageID"],
        json["conversationID"],
        json["pendingID"] ?? "",
        json["sender"],
        (json["receivers"] as List)
            .map((receiver) => receiver.toString())
            .toList(),
        (json["seeners"] as List).map((seener) => seener.toString()).toList(),
        json["content"],
        ActionDate.fromJson(json["messageDate"]),
        json["isReply"],
        json["replyingTo"] ?? "",
        json["reactions"] != null
            ? (json["reactions"] as List)
                .map((reaction) => ReactionItem.fromJson(reaction))
                .toList()
            : [],
        json["isDeleted"],
        json["messageType"],
        json["conversationType"],
        json["replyedmessage"] != null
            ? (json["replyedmessage"] as List)
                .map((reply) => MessageContent.fromJson(reply))
                .toList()
            : [],
        json["reactionWithInfo"] != null
            ? (json["reactionsWithInfo"] as List)
                .map((reactionInfo) =>
                    UsersContactPreview.fromJson(reactionInfo))
                .toList()
            : []);
  }
}
