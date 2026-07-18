import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/models/messages_models/messages_list_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

/// The real /m/conversations endpoint resolves "what to display" for a
/// conversation server-side into one `details` object regardless of type
/// (for single: the other person; for group/channel: the group's own
/// name/avatar) - so this widget no longer needs to branch on
/// conversationType to pick an avatar/title the way the old, dead
/// /u/initConversationList shape required.
class MessageItemView extends StatelessWidget {
  final MessageItem message;
  final String userID;

  const MessageItemView(
      {super.key, required this.message, required this.userID});

  bool get _isCurrentUserSender => message.sender == userID;

  String _previewText(bool isTyping) {
    if (isTyping) {
      return message.conversationType == "single"
          ? "is typing…"
          : "someone is typing…";
    }
    final prefix =
        _isCurrentUserSender && message.messageType != "notif" ? "you: " : "";
    // Matches webapp's lastMessagePreview() exactly, including that a
    // deleted message still gets the "you: " prefix like every other type.
    if (message.isDeleted) return "$prefix[Deleted message]";
    if (message.messageType == "text" || message.messageType == "notif") {
      return "$prefix${message.content}";
    }
    if (message.messageType == "image") return "${prefix}Sent a photo";
    if (message.messageType.contains("video")) return "${prefix}Sent a video";
    if (message.messageType.contains("audio")) return "${prefix}Sent an audio";
    return "${prefix}Sent a file";
  }

  /// messageDate's wire shape is genuinely ambiguous (see MessageItem's own
  /// _parseDate doc comment) - tries a raw ISO/Mongo-Date string first (the
  /// common case), then the {date: "MM/DD/YYYY", time: "h:mm AM/PM"} shape
  /// some other endpoints use, falling back to date-only if the time
  /// portion doesn't parse.
  DateTime? _parseMessageDate(ActionDate d) {
    final iso = DateTime.tryParse(d.date);
    if (iso != null) return iso;
    final combined = DateTime.tryParse("${d.date} ${d.time}");
    if (combined != null) return combined;
    final parts = d.date.split('/');
    if (parts.length == 3) {
      final month = int.tryParse(parts[0]);
      final day = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (month != null && day != null && year != null) {
        return DateTime(year, month, day);
      }
    }
    return null;
  }

  String _timeLabel() {
    final parsed = _parseMessageDate(message.messageDate);
    if (parsed != null) return timeSinceShort(parsed);
    return "${message.messageDate.date} · ${message.messageDate.time}";
  }

  IconData? get _typeIcon => switch (message.conversationType) {
        "group" => Icons.people_alt_outlined,
        "channel" || "server" => Icons.dataset_outlined,
        _ => null,
      };

  void _open(BuildContext context) {
    // ConversationView only needs the id - it resolves the header name/
    // avatar itself via GET /m/conversation/:id, same as every other entry
    // point (Contacts, Profile, Search).
    context.push("/conversation/${message.conversationID}");
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return StoreConnector<AppState, ({bool isTyping, bool online})>(
        // Without distinct, this row rebuilds on EVERY store dispatch (each
        // presence/typing/message event across the whole app). The converter
        // already returns a small record with value equality, so distinct
        // limits rebuilds to when THIS row's own typing/online actually flips.
        distinct: true,
        builder: (context, data) {
      final title = message.details.displayName.isEmpty
          ? message.details.username
          : message.details.displayName;

      return InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(CLRadii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Row(
            children: [
              CLAvatar(
                id: message.details.id.isEmpty
                    ? message.conversationID
                    : message.details.id,
                name: title,
                src: message.details.profile != "none"
                    ? message.details.profile
                    : null,
                size: 52,
                online: data.online,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14,
                                  color: _typeIcon != null ? p.brand : p.text,
                                  fontWeight: FontWeight.w700)),
                        ),
                        if (_typeIcon != null) ...[
                          const SizedBox(width: 4),
                          Icon(_typeIcon, size: 16, color: p.brand),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(_previewText(data.isTyping),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: p.text2)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_timeLabel(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: p.text3)),
                  if (message.unread > 0) ...[
                    const SizedBox(height: 6),
                    _UnreadDot(count: message.unread),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    }, converter: (store) {
      return (
        isTyping: store.state.isTypingList
            .any((typing) => typing.conversationID == message.conversationID),
        // Only single conversations map to one actual person - a group's
        // avatar has no single "online" state to show, matches webapp's
        // activeuserSpecific gating on conversationType === "single".
        online: message.conversationType == "single" &&
            (store.state.presence[message.details.entityId]?.online ?? false),
      );
    });
  }
}

/// Solid filled-circle unread counter, matching webapp's Messages.tsx badge
/// exactly (background: brand, white text, no 99+ truncation - the raw
/// count is always shown, the pill just grows for wider numbers) - visually
/// distinct from the generic soft-pill CLBadge used elsewhere in the app.
class _UnreadDot extends StatelessWidget {
  final int count;
  const _UnreadDot({required this.count});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.brand,
        borderRadius: BorderRadius.circular(CLRadii.pill),
      ),
      child: Text(
        count.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
