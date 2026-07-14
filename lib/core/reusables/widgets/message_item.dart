import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/utils/content_validator.dart';
import 'package:chatterloop_app/models/messages_models/messages_list_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:chatterloop_app/models/view_prop_models/conversation_view_props.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

class MessageItemView extends StatelessWidget {
  final MessageItem message;
  final String userID;

  const MessageItemView(
      {super.key, required this.message, required this.userID});

  bool get _isCurrentUserSender => message.sender == userID;

  UsersContactPreview get _otherParticipant =>
      userID == message.users[0].userID ? message.users[1] : message.users[0];

  /// Shared across every conversation type - was copy-pasted 3x in the
  /// original single/group/server branches.
  String _previewText(bool isTyping) {
    if (isTyping) {
      return message.conversationType == "single"
          ? "is typing…"
          : "someone is typing…";
    }
    if (message.isDeleted == true) return "Message deleted";
    final prefix =
        _isCurrentUserSender && message.messageType != "notif" ? "you: " : "";
    if (message.messageType == "text" || message.messageType == "notif") {
      return "$prefix${message.content}";
    }
    if (message.messageType == "image") return "${prefix}Sent a photo";
    if (message.messageType.contains("video")) return "${prefix}Sent a video";
    if (message.messageType.contains("audio")) return "${prefix}Sent an audio";
    return "${prefix}Sent a file";
  }

  ({String? avatarSrc, String? title, Color? titleColor, IconData? titleIcon})
      _typeConfig() {
    switch (message.conversationType) {
      case "group":
        return (
          avatarSrc: message.groupdetails?.profile,
          title: message.groupdetails?.groupName ?? "Group",
          titleColor: CLColors.brand,
          titleIcon: Icons.people_alt_outlined,
        );
      case "server":
        return (
          avatarSrc: message.serverdetails?.profile,
          title: message.serverdetails?.serverName ?? "Server",
          titleColor: CLColors.gold,
          titleIcon: Icons.dataset_outlined,
        );
      case "single":
        final other = _otherParticipant;
        return (
          avatarSrc: other.profile,
          title: null,
          titleColor: null,
          titleIcon: null
        );
      default:
        // Unrecognized/future conversation type (e.g. realm, conference) -
        // degrade gracefully instead of indexing into `users`, which isn't
        // guaranteed populated the same way single/group/server are.
        return (
          avatarSrc: null,
          title: "Conversation",
          titleColor: null,
          titleIcon: Icons.forum_outlined,
        );
    }
  }

  void _open(BuildContext context) {
    if (message.conversationType == "single") {
      final other = _otherParticipant;
      final previewName = [
        other.fullname.firstName,
        if (other.fullname.middleName.isNotEmpty &&
            other.fullname.middleName != "N/A")
          other.fullname.middleName,
        other.fullname.lastName,
      ].where((part) => part.trim().isNotEmpty).join(" ");
      context.push("/conversation/${message.conversationID}",
          extra: ConversationViewProps(
              message.conversationID,
              message.conversationType,
              ConversationPreview(
                  ContentValidator().validateConversationProfile(
                      other.profile, message.conversationType),
                  previewName)));
    } else if (message.conversationType == "group") {
      context.push("/conversation/${message.conversationID}",
          extra: ConversationViewProps(
              message.conversationID,
              message.conversationType,
              ConversationPreview(
                  ContentValidator().validateConversationProfile(
                      message.groupdetails?.profile, message.conversationType),
                  message.groupdetails?.groupName ?? "")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return StoreConnector<AppState, bool>(builder: (context, isTyping) {
      final config = _typeConfig();
      final other =
          message.conversationType == "single" ? _otherParticipant : null;
      final titleText = config.title ??
          [
            other!.fullname.firstName,
            if (other.fullname.middleName.isNotEmpty &&
                other.fullname.middleName != "N/A")
              other.fullname.middleName,
            other.fullname.lastName,
          ].where((part) => part.trim().isNotEmpty).join(" ");

      return InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(CLRadii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Row(
            children: [
              CLAvatar(
                  id: message.conversationID,
                  name: titleText,
                  src: config.avatarSrc,
                  size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(titleText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14,
                                  color: config.titleColor ?? p.text,
                                  fontWeight: FontWeight.w700)),
                        ),
                        if (config.titleIcon != null) ...[
                          const SizedBox(width: 4),
                          Icon(config.titleIcon,
                              size: 16, color: config.titleColor),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(_previewText(isTyping),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: p.text2)),
                    const SizedBox(height: 2),
                    Text(
                        "${message.messageDate.date} · ${message.messageDate.time}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: p.text3)),
                  ],
                ),
              ),
              if (message.unread > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: CLBadge(
                      label: message.unread > 99
                          ? "99+"
                          : message.unread.toString(),
                      tone: CLBadgeTone.pink),
                ),
            ],
          ),
        ),
      );
    }, converter: (store) {
      return store.state.isTypingList
          .any((typing) => typing.conversationID == message.conversationID);
    });
  }
}
