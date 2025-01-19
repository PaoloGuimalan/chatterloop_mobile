import 'package:chatterloop_app/models/messages_models/message_item_model.dart';
import 'package:chatterloop_app/models/user_models/group_model.dart';
import 'package:chatterloop_app/models/user_models/server_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';

class MessageItem {
  final String sortID;
  final String conversationID;
  final String messageID;
  final String sender;
  final List<String> receivers;
  final List<String> seeners;
  final String content;
  final ActionDate messageDate;
  final bool isReply;
  final String replyingTo;
  final List<ReactionItem> reactions;
  final bool? isDeleted;
  final String messageType;
  final String conversationType;
  final int unread;
  final List<UsersContactPreview> users; // list of users in group
  final GroupDetails? groupdetails;
  final ServerDetails? serverdetails; // list of users in server are inside this

  MessageItem(
      this.sortID,
      this.conversationID,
      this.messageID,
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
      this.unread,
      this.users,
      this.groupdetails,
      this.serverdetails);

  factory MessageItem.fromJson(Map<String, dynamic> json) {
    return MessageItem(
        json["sortID"],
        json["conversationID"],
        json["messageID"],
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
        json["isDeleted"] ?? false,
        json["messageType"],
        json["conversationType"],
        json["unread"],
        (json["users"] as List)
            .map((user) => UsersContactPreview.fromJson(user))
            .toList(),
        json["groupdetails"] != null
            ? GroupDetails.fromJson(json["groupdetails"])
            : null,
        json["serverdetails"] != null
            ? ServerDetails.fromJson(json["serverdetails"])
            : null);
  }
}
