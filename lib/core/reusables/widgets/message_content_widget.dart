import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/core/reusables/players/voice_message_player.dart';
import 'package:chatterloop_app/core/reusables/widgets/link_preview_card.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/core/utils/linkify_text.dart';
import 'package:chatterloop_app/models/http_models/request_models.dart';
import 'package:chatterloop_app/models/messages_models/message_content_model.dart';
import 'package:chatterloop_app/models/messages_models/message_item_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_reactions/flutter_chat_reactions.dart';
import 'package:flutter_chat_reactions/model/menu_item.dart';
import 'package:flutter_chat_reactions/utilities/default_data.dart';
import 'package:flutter_chat_reactions/utilities/hero_dialog_route.dart';
import 'package:flutter_redux/flutter_redux.dart';

/// Mirrors webapp's EmojiPickerHandler.tsx QUICK_REACTIONS exactly. The
/// "more emojis" affordance is NOT in this list - the package renders every
/// entry here as plain emoji-sized Text, so a "➕" character here always
/// reads as a mismatched, low-res emoji rather than an app icon. It lives
/// instead as a real Material icon in the context-menu row below (see
/// _reactionMenuItems), which the package renders as an actual Icon widget.
const List<String> _quickReactions = ['👍', '❤️', '😆', '😮', '😢', '😡'];

/// Default Reply/Copy/Delete plus a "React" entry that opens the full emoji
/// picker - real Icon(Icons.add_reaction_outlined), not an emoji character.
final List<MenuItem> _reactionMenuItems = [
  ...DefaultData.menuItems,
  const MenuItem(label: 'React', icon: Icons.add_reaction_outlined),
];

/// Mirrors webapp's cl-message-reaction-pill exactly: a 20px-tall fully
/// rounded pill, the emoji row clipped to 100px wide, and a "+N" overflow
/// badge past 4 reactions - webapp doesn't slice the list either, it just
/// clips it visually and shows the count alongside.
Widget buildReactionPill(List<ReactionItem> reactions, CLPalette p) {
  return Container(
    height: 20,
    constraints: const BoxConstraints(maxWidth: 100),
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: p.surface,
      border: Border.all(color: p.border2, width: 1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ClipRect(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: reactions
                  .map((reaction) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Text(reaction.emoji.toString(),
                            style: const TextStyle(fontSize: 12)),
                      ))
                  .toList(),
            ),
          ),
        ),
        if (reactions.length > 4)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Text(
              "+${reactions.length - 4}",
              style: TextStyle(fontSize: 10, color: p.text2),
            ),
          ),
      ],
    ),
  );
}

class MessageContentWidget extends StatefulWidget {
  final MessageContent messageContent;
  final String previousContentUserID;
  final String currentUserID;
  final void Function(bool, String) onPressed;

  /// Resolves an entity id (message.sender) to a display name - "You" for
  /// the current user, otherwise looked up from conversationInfo.usersWithInfo,
  /// falling back to the raw id if that hasn't loaded yet/has no match.
  /// Read directly from widget.* at build time rather than cached in
  /// initState, since conversationInfo only arrives after messages already
  /// have (see conversation_view.dart's _startLoading sequencing).
  final String Function(String entityId) resolveSenderName;

  /// The conversation's actual type, from conversationMetaData - not
  /// messageContent.conversationType, which is set per-message by whichever
  /// client/code path created it and isn't reliably "single" even for a
  /// single/DM conversation (was letting the sender-name header row below
  /// render for DMs when it should only show in group/channel threads).
  final bool isSingleConversation;

  /// Needed to submit reactions (POST /m/addreaction requires it alongside
  /// the messageID) - not used for anything else in this widget.
  final String conversationID;

  const MessageContentWidget(
      {super.key,
      required this.messageContent,
      required this.previousContentUserID,
      required this.currentUserID,
      required this.onPressed,
      required this.resolveSenderName,
      required this.isSingleConversation,
      required this.conversationID});

  @override
  MessageContentWidgetState createState() => MessageContentWidgetState();
}

class MessageContentWidgetState extends State<MessageContentWidget> {
  late MessageContent _messageContent;
  late String _previousContentUserID;
  late String _currentUserID;
  late void Function(bool, String) _onPressed;

  bool isChecked = false;

  /// The replied-to message, if there genuinely is one. replyedmessage
  /// defaults to [] (not null) whenever the server's $lookup found nothing
  /// (e.g. the original was deleted, or isReply is true but the reference
  /// never resolved) - a bare `replyedmessage?[0]` still throws in that
  /// case since ?[] only guards a null receiver, not an empty list, so
  /// every reply-preview access below goes through this instead.
  MessageContent? get _repliedTo {
    final list = _messageContent.replyedmessage;
    return (list != null && list.isNotEmpty) ? list[0] : null;
  }

  @override
  void initState() {
    super.initState();
    _messageContent = widget.messageContent;
    _previousContentUserID = widget.previousContentUserID;
    _currentUserID = widget.currentUserID;
    _onPressed = widget.onPressed;
  }

  @override
  void didUpdateWidget(MessageContentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The cached fields above go stale on rebuild otherwise - ListView.builder
    // can reuse this State for a different index's message content.
    _messageContent = widget.messageContent;
    _previousContentUserID = widget.previousContentUserID;
    _currentUserID = widget.currentUserID;
    _onPressed = widget.onPressed;
  }

  /// Matches webapp's ContentHandler.tsx exactly: the "url%%%filename"
  /// encoding is only ever used for legacy Google Cloud Storage uploads
  /// (storage.googleapis.com) - every other upload (e.g. the DigitalOcean
  /// Spaces URLs this backend actually uses now) is just a plain URL with
  /// no delimiter, and the filename is its last "/"-segment. Blindly
  /// splitting on "%%%" for all content both threw (no [1] to index into)
  /// and, after the earlier crash fix's "File" fallback, silently hid the
  /// real filename that was sitting right there in the URL the whole time.
  String _fileNamePart(String content) {
    if (content.contains("storage.googleapis.com")) {
      final parts = content.split("%%%");
      return parts.length > 1 ? parts[1] : "File";
    }
    final segments = content.split("/");
    return segments.isNotEmpty && segments.last.isNotEmpty
        ? segments.last
        : "File";
  }

  /// Shared reply-assist checkbox handler - was copy-pasted near-identically
  /// across every content-type branch (text/image/video/audio/file/etc.)
  /// in this widget's build method.
  void _handleReplyAssistToggle(bool? value, bool isParentSenderCurrentUser) {
    if (value != null) {
      final replyContext = ReplyAssistContext(
          isParentSenderCurrentUser, _messageContent.messageID);
      StoreProvider.of<AppState>(context).dispatch(DispatchModel(
          value ? setReplyAssistContextT : removeReplyAssistContextT,
          replyContext));
    }
    setState(() {
      isChecked = value!;
    });
  }

  /// Matches webapp's EmojiPickerHandler.tsx applyReaction: optimistically
  /// appends locally, then fires the request - no rollback on failure there
  /// either, just a console.log, so this doesn't roll back locally on error.
  void _submitReaction(String emoji) {
    final userAuth = StoreProvider.of<AppState>(context).state.userAuth.user;
    // userID here means the user_account row id, NOT the entity id and NOT
    // the username, despite how easy it is to assume otherwise - confirmed
    // against server/routes/users/index.js's reactionsWithInfo query, which
    // does `id AS "userID"` (id is user_account's primary key), and against
    // webapp's ContentHandler.tsx, which joins raw reactions to that lookup
    // by `t2.userID === t1.userID`. Sending the username or entity id here
    // silently breaks that join server-side, so webapp can never resolve
    // the reactor's name/avatar even though the emoji itself still shows.
    setState(() {
      _messageContent.reactions = [
        ...?_messageContent.reactions,
        ReactionItem(
            userAuth.id, "", emoji, "", false, [], "", "", userAuth.entityId),
      ];
    });
    ConversationsApi().reactToMessageRequest(IReactToMessageRequest(
        widget.conversationID,
        _messageContent.messageID,
        userAuth.id,
        userAuth.entityId,
        emoji));
  }

  /// Matches webapp's MessageOptions.tsx DeleteMessageProcess: fires the
  /// request with no confirmation dialog and no optimistic local removal -
  /// the server enforces sender-only ownership itself, and the visible
  /// "Message deleted" placeholder only appears once the isDeleted flag
  /// round-trips back through the messages_list SSE event handled in
  /// conversation_view.dart.
  void _deleteMessage(String messageID) {
    ConversationsApi().deleteMessageRequest(
        IDeleteMessageRequest(widget.conversationID, messageID));
  }

  /// Triggered from the context menu's "React" item (a real Icon, not an
  /// emoji character) - matches webapp's EmojiPickerHandler switching from
  /// its quick-reaction bar to a full emoji picker.
  void _showFullEmojiPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SizedBox(
        height: 380,
        child: EmojiPicker(
          onEmojiSelected: (category, emoji) {
            Navigator.of(context).pop();
            _submitReaction(emoji.emoji);
          },
        ),
      ),
    );
  }

  Color getColor(Set<WidgetState> states) {
    const Set<WidgetState> interactiveStates = <WidgetState>{
      WidgetState.pressed,
      WidgetState.hovered,
      WidgetState.focused,
    };
    if (states.any(interactiveStates.contains)) {
      return Color(0xff1c7def);
    }
    return isChecked ? Color(0xff1c7def) : Colors.white;
  }

  Widget messageTypeSwitch(
      String content,
      String messageType,
      String messageID,
      bool isParentSenderCurrentUser,
      bool isCurrentUser,
      bool isReply,
      bool isHoverPreview,
      bool isMarkingEnabled) {
    final p = cl(context);
    if (messageType == "text") {
      return Row(
        mainAxisAlignment:
            isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          !isMarkingEnabled
              ? !isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Expanded(
                      child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        isReply
                            ? SizedBox(
                                height: 0,
                              )
                            : ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: 40, maxHeight: 40),
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        elevation: 0,
                                        padding: EdgeInsets.only(
                                            top: 0,
                                            bottom: 0,
                                            left: 0,
                                            right: 0)),
                                    onPressed: () => _deleteMessage(messageID),
                                    child: Center(
                                      child: Icon(
                                        Icons.delete,
                                        color: Color(0xFF565656),
                                        size: 18,
                                      ),
                                    )),
                              ),
                        isReply
                            ? SizedBox(
                                height: 0,
                              )
                            : ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: 40, maxHeight: 40),
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        elevation: 0,
                                        padding: EdgeInsets.only(
                                            top: 0,
                                            bottom: 0,
                                            left: 0,
                                            right: 0)),
                                    onPressed: () {
                                      _onPressed(true, messageID);
                                    },
                                    child: Center(
                                      child: Icon(
                                        Icons.reply,
                                        color: Color(0xFF565656),
                                        size: 20,
                                      ),
                                    )),
                              )
                      ],
                    ))
              : SizedBox(
                  width: 0,
                ),
          SizedBox(
            width: 5,
          ),
          isMarkingEnabled
              ? isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Checkbox(
                      side: BorderSide(
                        color: Color(0xff1c7def),
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(40)),
                      checkColor: Colors.white,
                      fillColor: WidgetStateProperty.resolveWith(getColor),
                      value: isChecked,
                      visualDensity:
                          const VisualDensity(horizontal: -2.0, vertical: -2.0),
                      onChanged: (bool? value) => _handleReplyAssistToggle(
                          value, isParentSenderCurrentUser),
                    )
              : SizedBox(
                  width: 0,
                ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 270),
            child: Column(
              crossAxisAlignment: isParentSenderCurrentUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                      color: isCurrentUser ? const Color(0xff1c7def) : p.border2,
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding:
                        EdgeInsets.only(top: 10, bottom: 10, left: 7, right: 7),
                    child: Text.rich(
                      TextSpan(
                        children: linkifySpans(
                          content,
                          TextStyle(
                              fontSize: 14,
                              color: isCurrentUser ? Colors.white : p.text),
                        ),
                      ),
                    ),
                  ),
                ),
                // Only on the full render, not the condensed reply-preview
                // snippet (isReply here means "rendering as a reply
                // preview", not "this message is a reply") - matches
                // webapp's ContentHandler.tsx, which only shows
                // LinkPreviewCard on the real message bubble.
                if (!isReply && _messageContent.linkPreview != null)
                  LinkPreviewCard(preview: _messageContent.linkPreview),
                _messageContent.reactions!.isNotEmpty && !isHoverPreview
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: buildReactionPill(_messageContent.reactions!, p),
                      )
                    : SizedBox(
                        height: 0,
                      )
              ],
            ),
          ),
          isMarkingEnabled
              ? !isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Checkbox(
                      side: BorderSide(
                        color: Color(0xff1c7def),
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(40)),
                      checkColor: Colors.white,
                      fillColor: WidgetStateProperty.resolveWith(getColor),
                      value: isChecked,
                      visualDensity:
                          const VisualDensity(horizontal: -2.0, vertical: -2.0),
                      onChanged: (bool? value) => _handleReplyAssistToggle(
                          value, isParentSenderCurrentUser),
                    )
              : SizedBox(
                  width: 0,
                ),
          SizedBox(
            width: 5,
          ),
          !isMarkingEnabled
              ? isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Expanded(
                      child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        isReply
                            ? SizedBox(
                                height: 0,
                              )
                            : ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: 40, maxHeight: 40),
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        elevation: 0,
                                        padding: EdgeInsets.only(
                                            top: 0,
                                            bottom: 0,
                                            left: 0,
                                            right: 0)),
                                    onPressed: () {
                                      _onPressed(true, messageID);
                                    },
                                    child: Center(
                                      child: Icon(
                                        Icons.reply,
                                        color: Color(0xFF565656),
                                        size: 20,
                                      ),
                                    )),
                              )
                      ],
                    ))
              : SizedBox(
                  width: 0,
                )
        ],
      );
    } else if (messageType == "image") {
      return Row(
        mainAxisAlignment:
            isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          !isMarkingEnabled
              ? !isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Expanded(
                      child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        isReply
                            ? SizedBox(
                                height: 0,
                              )
                            : ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: 40, maxHeight: 40),
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        elevation: 0,
                                        padding: EdgeInsets.only(
                                            top: 0,
                                            bottom: 0,
                                            left: 0,
                                            right: 0)),
                                    onPressed: () => _deleteMessage(messageID),
                                    child: Center(
                                      child: Icon(
                                        Icons.delete,
                                        color: Color(0xFF565656),
                                        size: 18,
                                      ),
                                    )),
                              ),
                        isReply
                            ? SizedBox(
                                height: 0,
                              )
                            : ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: 40, maxHeight: 40),
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        elevation: 0,
                                        padding: EdgeInsets.only(
                                            top: 0,
                                            bottom: 0,
                                            left: 0,
                                            right: 0)),
                                    onPressed: () {
                                      _onPressed(true, messageID);
                                    },
                                    child: Center(
                                      child: Icon(
                                        Icons.reply,
                                        color: Color(0xFF565656),
                                        size: 20,
                                      ),
                                    )),
                              )
                      ],
                    ))
              : SizedBox(
                  width: 0,
                ),
          SizedBox(
            width: 5,
          ),
          isMarkingEnabled
              ? isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Checkbox(
                      side: BorderSide(
                        color: Color(0xff1c7def),
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(40)),
                      checkColor: Colors.white,
                      fillColor: WidgetStateProperty.resolveWith(getColor),
                      value: isChecked,
                      visualDensity:
                          const VisualDensity(horizontal: -2.0, vertical: -2.0),
                      onChanged: (bool? value) => _handleReplyAssistToggle(
                          value, isParentSenderCurrentUser),
                    )
              : SizedBox(
                  width: 0,
                ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 270),
            child: Column(
              crossAxisAlignment: isParentSenderCurrentUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Center(
                  child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: double.infinity,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                            color: p.surface3,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: p.border2, width: 1)),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: EdgeInsets.all(0),
                            child: CLNetworkImage(
                              src: content,
                            ),
                          ),
                        ),
                      )),
                ),
                _messageContent.reactions!.isNotEmpty && !isHoverPreview
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: buildReactionPill(_messageContent.reactions!, p),
                      )
                    : SizedBox(
                        height: 0,
                      )
              ],
            ),
          ),
          isMarkingEnabled
              ? !isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Checkbox(
                      side: BorderSide(
                        color: Color(0xff1c7def),
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(40)),
                      checkColor: Colors.white,
                      fillColor: WidgetStateProperty.resolveWith(getColor),
                      value: isChecked,
                      visualDensity:
                          const VisualDensity(horizontal: -2.0, vertical: -2.0),
                      onChanged: (bool? value) => _handleReplyAssistToggle(
                          value, isParentSenderCurrentUser),
                    )
              : SizedBox(
                  width: 0,
                ),
          SizedBox(
            width: 5,
          ),
          !isMarkingEnabled
              ? isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Expanded(
                      child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        isReply
                            ? SizedBox(
                                height: 0,
                              )
                            : ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: 40, maxHeight: 40),
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        elevation: 0,
                                        padding: EdgeInsets.only(
                                            top: 0,
                                            bottom: 0,
                                            left: 0,
                                            right: 0)),
                                    onPressed: () {
                                      _onPressed(true, messageID);
                                    },
                                    child: Center(
                                      child: Icon(
                                        Icons.reply,
                                        color: Color(0xFF565656),
                                        size: 20,
                                      ),
                                    )),
                              )
                      ],
                    ))
              : SizedBox(
                  width: 0,
                )
        ],
      );
    } else if (messageType.contains("video")) {
      return Row(
        mainAxisAlignment:
            isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          !isMarkingEnabled
              ? !isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Expanded(
                      child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        isReply
                            ? SizedBox(
                                height: 0,
                              )
                            : ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: 40, maxHeight: 40),
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        elevation: 0,
                                        padding: EdgeInsets.only(
                                            top: 0,
                                            bottom: 0,
                                            left: 0,
                                            right: 0)),
                                    onPressed: () => _deleteMessage(messageID),
                                    child: Center(
                                      child: Icon(
                                        Icons.delete,
                                        color: Color(0xFF565656),
                                        size: 18,
                                      ),
                                    )),
                              ),
                        isReply
                            ? SizedBox(
                                height: 0,
                              )
                            : ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: 40, maxHeight: 40),
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        elevation: 0,
                                        padding: EdgeInsets.only(
                                            top: 0,
                                            bottom: 0,
                                            left: 0,
                                            right: 0)),
                                    onPressed: () {
                                      _onPressed(true, messageID);
                                    },
                                    child: Center(
                                      child: Icon(
                                        Icons.reply,
                                        color: Color(0xFF565656),
                                        size: 20,
                                      ),
                                    )),
                              )
                      ],
                    ))
              : SizedBox(
                  width: 0,
                ),
          SizedBox(
            width: 5,
          ),
          isMarkingEnabled
              ? isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Checkbox(
                      side: BorderSide(
                        color: Color(0xff1c7def),
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(40)),
                      checkColor: Colors.white,
                      fillColor: WidgetStateProperty.resolveWith(getColor),
                      value: isChecked,
                      visualDensity:
                          const VisualDensity(horizontal: -2.0, vertical: -2.0),
                      onChanged: (bool? value) => _handleReplyAssistToggle(
                          value, isParentSenderCurrentUser),
                    )
              : SizedBox(
                  width: 0,
                ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 270),
            child: Column(
              crossAxisAlignment: isParentSenderCurrentUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    color: Colors.black,
                    child: VideoPlayerScreen(
                        videoUrl: content
                            .split("%%%")[0]
                            .replaceAll("###", "%23%23%23")),
                  ),
                ),
                _messageContent.reactions!.isNotEmpty && !isHoverPreview
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: buildReactionPill(_messageContent.reactions!, p),
                      )
                    : SizedBox(
                        height: 0,
                      )
              ],
            ),
          ),
          isMarkingEnabled
              ? !isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Checkbox(
                      side: BorderSide(
                        color: Color(0xff1c7def),
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(40)),
                      checkColor: Colors.white,
                      fillColor: WidgetStateProperty.resolveWith(getColor),
                      value: isChecked,
                      visualDensity:
                          const VisualDensity(horizontal: -2.0, vertical: -2.0),
                      onChanged: (bool? value) => _handleReplyAssistToggle(
                          value, isParentSenderCurrentUser),
                    )
              : SizedBox(
                  width: 0,
                ),
          SizedBox(
            width: 5,
          ),
          !isMarkingEnabled
              ? isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Expanded(
                      child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        isReply
                            ? SizedBox(
                                height: 0,
                              )
                            : ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: 40, maxHeight: 40),
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        elevation: 0,
                                        padding: EdgeInsets.only(
                                            top: 0,
                                            bottom: 0,
                                            left: 0,
                                            right: 0)),
                                    onPressed: () {
                                      _onPressed(true, messageID);
                                    },
                                    child: Center(
                                      child: Icon(
                                        Icons.reply,
                                        color: Color(0xFF565656),
                                        size: 20,
                                      ),
                                    )),
                              )
                      ],
                    ))
              : SizedBox(
                  width: 0,
                )
        ],
      );
    } else if (messageType.contains("audio")) {
      return Row(
        mainAxisAlignment:
            isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          !isMarkingEnabled
              ? !isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Expanded(
                      child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        isReply
                            ? SizedBox(
                                height: 0,
                              )
                            : ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: 40, maxHeight: 40),
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        elevation: 0,
                                        padding: EdgeInsets.only(
                                            top: 0,
                                            bottom: 0,
                                            left: 0,
                                            right: 0)),
                                    onPressed: () => _deleteMessage(messageID),
                                    child: Center(
                                      child: Icon(
                                        Icons.delete,
                                        color: Color(0xFF565656),
                                        size: 18,
                                      ),
                                    )),
                              ),
                        isReply
                            ? SizedBox(
                                height: 0,
                              )
                            : ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: 40, maxHeight: 40),
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        elevation: 0,
                                        padding: EdgeInsets.only(
                                            top: 0,
                                            bottom: 0,
                                            left: 0,
                                            right: 0)),
                                    onPressed: () {
                                      _onPressed(true, messageID);
                                    },
                                    child: Center(
                                      child: Icon(
                                        Icons.reply,
                                        color: Color(0xFF565656),
                                        size: 20,
                                      ),
                                    )),
                              )
                      ],
                    ))
              : SizedBox(
                  width: 0,
                ),
          SizedBox(
            width: 5,
          ),
          isMarkingEnabled
              ? isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Checkbox(
                      side: BorderSide(
                        color: Color(0xff1c7def),
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(40)),
                      checkColor: Colors.white,
                      fillColor: WidgetStateProperty.resolveWith(getColor),
                      value: isChecked,
                      visualDensity:
                          const VisualDensity(horizontal: -2.0, vertical: -2.0),
                      onChanged: (bool? value) => _handleReplyAssistToggle(
                          value, isParentSenderCurrentUser),
                    )
              : SizedBox(
                  width: 0,
                ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 270),
            child: Column(
              crossAxisAlignment: isParentSenderCurrentUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                VoiceMessagePlayer(
                  src: content.split("%%%")[0].replaceAll("###", "%23%23%23"),
                  isSender: isCurrentUser,
                ),
                _messageContent.reactions!.isNotEmpty && !isHoverPreview
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: buildReactionPill(_messageContent.reactions!, p),
                      )
                    : SizedBox(
                        height: 0,
                      )
              ],
            ),
          ),
          isMarkingEnabled
              ? !isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Checkbox(
                      side: BorderSide(
                        color: Color(0xff1c7def),
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(40)),
                      checkColor: Colors.white,
                      fillColor: WidgetStateProperty.resolveWith(getColor),
                      value: isChecked,
                      visualDensity:
                          const VisualDensity(horizontal: -2.0, vertical: -2.0),
                      onChanged: (bool? value) => _handleReplyAssistToggle(
                          value, isParentSenderCurrentUser),
                    )
              : SizedBox(
                  width: 0,
                ),
          SizedBox(
            width: 5,
          ),
          !isMarkingEnabled
              ? isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Expanded(
                      child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        isReply
                            ? SizedBox(
                                height: 0,
                              )
                            : ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: 40, maxHeight: 40),
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        elevation: 0,
                                        padding: EdgeInsets.only(
                                            top: 0,
                                            bottom: 0,
                                            left: 0,
                                            right: 0)),
                                    onPressed: () {
                                      _onPressed(true, messageID);
                                    },
                                    child: Center(
                                      child: Icon(
                                        Icons.reply,
                                        color: Color(0xFF565656),
                                        size: 20,
                                      ),
                                    )),
                              )
                      ],
                    ))
              : SizedBox(
                  width: 0,
                )
        ],
      );
    } else if (messageType == "notif") {
      return Column(
        children: [
          SizedBox(
            height: 4,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 300),
                child: Container(
                  decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: EdgeInsets.all(7),
                    child: Text(
                      content,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Color(0xFF565656)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(
            height: 4,
          )
        ],
      );
    } else {
      return Row(
        mainAxisAlignment:
            isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          !isMarkingEnabled
              ? !isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Expanded(
                      child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        isReply
                            ? SizedBox(
                                height: 0,
                              )
                            : ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: 40, maxHeight: 40),
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        elevation: 0,
                                        padding: EdgeInsets.only(
                                            top: 0,
                                            bottom: 0,
                                            left: 0,
                                            right: 0)),
                                    onPressed: () => _deleteMessage(messageID),
                                    child: Center(
                                      child: Icon(
                                        Icons.delete,
                                        color: Color(0xFF565656),
                                        size: 18,
                                      ),
                                    )),
                              ),
                        isReply
                            ? SizedBox(
                                height: 0,
                              )
                            : ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: 40, maxHeight: 40),
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        elevation: 0,
                                        padding: EdgeInsets.only(
                                            top: 0,
                                            bottom: 0,
                                            left: 0,
                                            right: 0)),
                                    onPressed: () {
                                      _onPressed(true, messageID);
                                    },
                                    child: Center(
                                      child: Icon(
                                        Icons.reply,
                                        color: Color(0xFF565656),
                                        size: 20,
                                      ),
                                    )),
                              )
                      ],
                    ))
              : SizedBox(
                  width: 0,
                ),
          SizedBox(
            width: 5,
          ),
          isMarkingEnabled
              ? isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Checkbox(
                      side: BorderSide(
                        color: Color(0xff1c7def),
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(40)),
                      checkColor: Colors.white,
                      fillColor: WidgetStateProperty.resolveWith(getColor),
                      value: isChecked,
                      visualDensity:
                          const VisualDensity(horizontal: -2.0, vertical: -2.0),
                      onChanged: (bool? value) => _handleReplyAssistToggle(
                          value, isParentSenderCurrentUser),
                    )
              : SizedBox(
                  width: 0,
                ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 270),
            child: Column(
              crossAxisAlignment: isParentSenderCurrentUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: p.border2,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: EdgeInsets.only(
                            top: 0, bottom: 0, left: 0, right: 0)),
                    onPressed: () {},
                    child: Container(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: EdgeInsets.only(
                            top: 10, bottom: 10, left: 10, right: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Icon(
                              Icons.file_copy_outlined,
                              color: p.text,
                              size: 35,
                            ),
                            SizedBox(
                              width: 10,
                            ),
                            Expanded(
                                child: Text(
                              _fileNamePart(content),
                              style: TextStyle(fontSize: 14, color: p.text),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ))
                          ],
                        ),
                      ),
                    )),
                _messageContent.reactions!.isNotEmpty && !isHoverPreview
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: buildReactionPill(_messageContent.reactions!, p),
                      )
                    : SizedBox(
                        height: 0,
                      )
              ],
            ),
          ),
          isMarkingEnabled
              ? !isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Checkbox(
                      side: BorderSide(
                        color: Color(0xff1c7def),
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(40)),
                      checkColor: Colors.white,
                      fillColor: WidgetStateProperty.resolveWith(getColor),
                      value: isChecked,
                      visualDensity:
                          const VisualDensity(horizontal: -2.0, vertical: -2.0),
                      onChanged: (bool? value) => _handleReplyAssistToggle(
                          value, isParentSenderCurrentUser),
                    )
              : SizedBox(
                  width: 0,
                ),
          SizedBox(
            width: 5,
          ),
          !isMarkingEnabled
              ? isParentSenderCurrentUser
                  ? SizedBox(
                      width: 0,
                    )
                  : Expanded(
                      child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        isReply
                            ? SizedBox(
                                height: 0,
                              )
                            : ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: 40, maxHeight: 40),
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        elevation: 0,
                                        padding: EdgeInsets.only(
                                            top: 0,
                                            bottom: 0,
                                            left: 0,
                                            right: 0)),
                                    onPressed: () {
                                      _onPressed(true, messageID);
                                    },
                                    child: Center(
                                      child: Icon(
                                        Icons.reply,
                                        color: Color(0xFF565656),
                                        size: 20,
                                      ),
                                    )),
                              )
                      ],
                    ))
              : SizedBox(
                  width: 0,
                )
        ],
      );
    }
  }

  Widget messageDeletedItem(String messageType, bool isParentSenderCurrentUser,
      bool isCurrentUser, bool isReply) {
    return Row(
      mainAxisAlignment:
          isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        !isParentSenderCurrentUser
            ? SizedBox(
                width: 0,
              )
            : Expanded(
                child: SizedBox(
                height: 0,
              )),
        SizedBox(
          width: 5,
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 270),
          child: Container(
            decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border.all(color: Color(0xFFdedede), width: 1),
                borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: EdgeInsets.only(top: 10, bottom: 10, left: 7, right: 7),
              child: Text(
                "Message deleted",
                style: TextStyle(fontSize: 14, color: Color(0xFFdedede)),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 5,
        ),
        isParentSenderCurrentUser
            ? SizedBox(
                width: 0,
              )
            : Expanded(
                child: SizedBox(
                height: 0,
              ))
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Each message bubble was subscribed to the WHOLE store and rebuilt on
    // every dispatch app-wide - in a long thread that's N bubbles re-rendering
    // on every presence/typing/seen event. The builder only actually reads
    // isUsingReplyAssist, so narrow to that one bool + distinct.
    return StoreConnector<AppState, bool>(
        distinct: true,
        builder: (context, isUsingReplyAssist) {
      return Padding(
        padding: EdgeInsets.only(top: 2, bottom: 2, left: 0, right: 0),
        child: Column(
          children: [
            SizedBox(
              height: _messageContent.isReply ? 7 : 0,
            ),
            _previousContentUserID != _messageContent.sender ||
                    _previousContentUserID == "end"
                ? Column(
                    children: [
                      SizedBox(
                        height: 5,
                      ),
                      !widget.isSingleConversation &&
                              _messageContent.messageType != "notif" &&
                              _currentUserID != _messageContent.sender
                          ? Row(
                              mainAxisAlignment:
                                  _messageContent.sender == _currentUserID
                                      ? MainAxisAlignment.end
                                      : MainAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(
                                      left: 7, right: 7, bottom: 2),
                                  child: Text(
                                    widget.resolveSenderName(
                                        _messageContent.sender),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF565656),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )
                              ],
                            )
                          : SizedBox(
                              height: 0,
                            )
                    ],
                  )
                : SizedBox(
                    height: 0,
                  ),
            SizedBox(
              height: _messageContent.isReply ? 0 : 5,
            ),
            _messageContent.isReply && _repliedTo != null
                ? Column(
                    children: [
                      SizedBox(
                        height: 0,
                      ),
                      Row(
                        mainAxisAlignment:
                            _messageContent.sender == _currentUserID
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                        children: [
                          Padding(
                            padding:
                                EdgeInsets.only(left: 7, right: 7, bottom: 7),
                            child: Text(
                              "replied to ${widget.resolveSenderName(_repliedTo!.sender)}",
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF565656),
                                  fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        ],
                      ),
                      Opacity(
                        opacity: 0.6,
                        child: _repliedTo!.isDeleted == true
                            ? messageDeletedItem(
                                _repliedTo!.messageType,
                                _messageContent.sender == _currentUserID,
                                _repliedTo!.sender == _currentUserID,
                                true)
                            : messageTypeSwitch(
                                _repliedTo!.content,
                                _repliedTo!.messageType,
                                _repliedTo!.messageID,
                                _messageContent.sender == _currentUserID,
                                _repliedTo!.sender == _currentUserID,
                                true,
                                false,
                                false),
                      )
                    ],
                  )
                : SizedBox(
                    height: 0,
                  ),
            _messageContent.isDeleted as bool
                ? messageDeletedItem(
                    _messageContent.messageType,
                    _messageContent.sender == _currentUserID,
                    _messageContent.sender == _currentUserID,
                    false)
                : GestureDetector(
                    onLongPress: () async {
                      Navigator.of(context).push(
                        HeroDialogRoute(
                          builder: (context) {
                            return ReactionsDialogWidget(
                              id: _messageContent
                                  .messageID, // unique id for message
                              reactions: _quickReactions,
                              menuItems: _reactionMenuItems,
                              // Every message type (including audio) goes
                              // through the same messageTypeSwitch the
                              // normal bubble uses - this used to
                              // special-case audio with its own hardcoded
                              // generic file-card look here, which fell out
                              // of sync the moment the real audio bubble was
                              // redesigned to use VoiceMessagePlayer (the
                              // long-press preview kept showing the old
                              // design since it never went through that
                              // change).
                              // flutter_chat_reactions' MessageBubble places
                              // messageWidget directly with no Material
                              // ancestor of its own (unlike its reaction
                              // row/context menu, which do wrap themselves)
                              // - VoiceMessagePlayer's play/pause InkWell
                              // needs one to paint its ink response, or this
                              // throws "No Material widget found" the
                              // moment the long-press preview renders an
                              // audio message.
                              messageWidget: Material(
                                type: MaterialType.transparency,
                                child: messageTypeSwitch(
                                    _messageContent.content,
                                    _messageContent.messageType,
                                    _messageContent.messageID,
                                    _messageContent.sender == _currentUserID,
                                    _messageContent.sender == _currentUserID,
                                    false,
                                    true,
                                    false),
                              ), // message widget
                              onReactionTap: (reaction) {
                                _submitReaction(reaction);
                              },
                              onContextMenuTap: (menuItem) {
                                if (menuItem.label == "Reply") {
                                  _onPressed(true, _messageContent.messageID);
                                } else if (menuItem.label == "React") {
                                  _showFullEmojiPicker(context);
                                }
                                // handle context menu item
                              },
                            );
                          },
                        ),
                      );
                    },
                    child: Hero(
                        tag: _messageContent.messageID,
                        child: messageTypeSwitch(
                            _messageContent.content,
                            _messageContent.messageType,
                            _messageContent.messageID,
                            _messageContent.sender == _currentUserID,
                            _messageContent.sender == _currentUserID,
                            false,
                            false,
                            isUsingReplyAssist)),
                  )
          ],
        ),
      );
    }, converter: (store) => store.state.isUsingReplyAssist);
  }
}
