import 'package:chatterloop_app/core/reusables/widgets/message_reactions_dialog.dart';
import 'package:chatterloop_app/core/reusables/widgets/reactions_sheet.dart';
import 'package:chatterloop_app/core/utils/chat_mentions.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
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
  ...kDefaultMessageMenuItems,
  const MenuItem(label: 'React', icon: Icons.add_reaction_outlined),
];

/// The 20px-tall rounded pill under a message, based on webapp's
/// cl-message-reaction-pill.
///
/// Deviates from web in one way, deliberately: reactions are GROUPED by emoji
/// with a count instead of repeating the glyph. Ten thumbs-up used to render
/// as ten identical emoji clipped at 100px, which read as noise and told you
/// nothing - "👍 10" says the same thing in less space. Web still repeats
/// them; this is the better behaviour, not a parity gap to close.
///
/// Distinct emoji past 3 collapse into a "+N" badge counting the REMAINING
/// REACTIONS, not the remaining emoji kinds - the number people read it as.
/// Collapses cosmetic code-point differences so the same visible emoji groups
/// as one: drops the U+FE0F variation selector and any skin-tone modifier
/// (U+1F3FB-U+1F3FF). ZWJ sequences are left alone - those join genuinely
/// different emoji and must not be flattened.
String normalizeEmojiKey(String emoji) => emoji
    .replaceAll('\uFE0F', '')
    .replaceAll(RegExp(r'[\u{1F3FB}-\u{1F3FF}]', unicode: true), '');

Widget buildReactionPill(List<ReactionItem> reactions, CLPalette p) {
  // Insertion-ordered so the pill does not reshuffle as reactions arrive.
  // Keyed on the NORMALIZED emoji but displaying the first glyph seen: two
  // clients can send the same emoji with different code points - a heart with
  // a U+FE0F variation selector vs a bare one, or the same hand with
  // different skin-tone modifiers. They render identically, so grouping on
  // the raw string left what looked like duplicates sitting side by side.
  final counts = <String, int>{};
  final glyphs = <String, String>{};
  for (final reaction in reactions) {
    final emoji = reaction.emoji?.toString() ?? "";
    if (emoji.isEmpty) continue;
    final key = normalizeEmojiKey(emoji);
    counts[key] = (counts[key] ?? 0) + 1;
    glyphs.putIfAbsent(key, () => emoji);
  }

  const maxDistinct = 3;
  final shown = counts.entries.take(maxDistinct).toList();
  final hiddenReactions = counts.entries
      .skip(maxDistinct)
      .fold<int>(0, (sum, entry) => sum + entry.value);

  return Container(
    height: 20,
    constraints: const BoxConstraints(maxWidth: 110),
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
              children: [
                for (final entry in shown)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Emoji glyph sized to its container - not a CLType step.
                        Text(glyphs[entry.key] ?? entry.key,
                            style: const TextStyle(fontSize: 12)),
                        // The count is dropped at 1: "👍 1" is just noise.
                        if (entry.value > 1) ...[
                          const SizedBox(width: 2),
                          Text(
                            "${entry.value}",
                            style: TextStyle(
                                fontSize: CLType.meta, color: p.text2),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (hiddenReactions > 0)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Text(
              "+$hiddenReactions",
              style: TextStyle(fontSize: CLType.meta, color: p.text2),
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

  /// The conversation's participants, used ONLY to highlight mentions.
  ///
  /// Chat mentions are plain text - nothing is stored alongside the message -
  /// so "@anna" is only a mention if Anna is actually in this conversation.
  /// That is why the list has to reach down here rather than being derived
  /// from the message itself. Empty means nothing is highlighted, which is the
  /// correct fallback before the conversation info has loaded.
  final List<UsersContactPreview> mentionMembers;

  const MessageContentWidget(
      {super.key,
      required this.messageContent,
      required this.previousContentUserID,
      required this.currentUserID,
      required this.onPressed,
      required this.resolveSenderName,
      required this.isSingleConversation,
      required this.conversationID,
      this.mentionMembers = const []});

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

  /// Mentions and links, composed rather than exclusive: split the text into
  /// mention / non-mention runs first, then linkify only the non-mention runs.
  /// Linkifying a mention would try to turn "@anna" into a link.
  ///
  /// On your own (brand-coloured) bubble the text is already white, so the
  /// mention is distinguished by weight alone - a second colour there would be
  /// invisible or clash.
  List<InlineSpan> _mentionAwareSpans(
      String content, TextStyle baseStyle, Color mentionColor) {
    final spans = splitMentionSpans(content, widget.mentionMembers);
    final out = <InlineSpan>[];

    for (final span in spans) {
      if (span.isMention) {
        out.add(TextSpan(
          text: span.text,
          style: baseStyle.copyWith(
              color: mentionColor, fontWeight: FontWeight.w700),
        ));
      } else {
        out.addAll(linkifySpans(span.text, baseStyle));
      }
    }
    return out;
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
  /// The emoji this user currently has on this message, if any.
  String? get _myReactionEmoji {
    final me = StoreProvider.of<AppState>(context).state.userAuth.user.entityId;
    final mine = _messageContent.reactions?.where((r) => r.entityID == me);
    return (mine != null && mine.isNotEmpty)
        ? mine.first.emoji?.toString()
        : null;
  }

  /// Tapping the pill opens the list of who reacted - webapp parity with
  /// ReactionsModal. Your own row removes your reaction, which goes through
  /// the same toggle path as picking it again.
  void _openReactionsSheet() {
    final reactions = _messageContent.reactions;
    if (reactions == null || reactions.isEmpty) return;

    showMessageReactionsSheet(
      context,
      reactions: reactions,
      reactorsInfo: _messageContent.reactionsWithInfo ?? const [],
      selfEntityID:
          StoreProvider.of<AppState>(context).state.userAuth.user.entityId,
      onRemoveOwn: () {
        final mine = _myReactionEmoji;
        // Re-submitting the emoji you already have is the remove path, so
        // this reuses the toggle rather than duplicating the request.
        if (mine != null) _submitReaction(mine);
      },
    );
  }

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
    final previous = _messageContent.reactions;
    final mine = previous?.where((r) => r.entityID == userAuth.entityId);
    final myEmoji = (mine != null && mine.isNotEmpty) ? mine.first.emoji : null;

    // Tapping the emoji you already have undoes it; a different one swaps it.
    // Matches webapp's toggleMyReaction.
    final next = myEmoji == emoji ? null : emoji;

    // Optimistic, and a REPLACE not an append: drop my existing reaction
    // before adding the new one. The old /m/addreaction route only ever
    // pushed, which is how a message ended up carrying two reactions from the
    // same person.
    setState(() {
      final withoutMine = [
        ...?previous?.where((r) => r.entityID != userAuth.entityId),
      ];
      _messageContent.reactions = next == null
          ? withoutMine
          : [
              ...withoutMine,
              ReactionItem(userAuth.id, "", next, "", false, [], "", "",
                  userAuth.entityId),
            ];
    });

    ConversationsApi()
        .setMessageReactionRequest(
      conversationID: widget.conversationID,
      messageID: _messageContent.messageID,
      userID: userAuth.id,
      emoji: next,
    )
        .then((ok) {
      // Restore on failure - the old code fired and forgot, so a failed
      // reaction stayed on screen until the thread was reloaded.
      if (!ok && mounted) {
        setState(() => _messageContent.reactions = previous);
      }
    });
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
      useRootNavigator: true,
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
      return CLAccent.of(context);
    }
    return isChecked ? CLAccent.of(context) : Colors.white;
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

    // Reactions belong to the REAL bubble only. Both preview modes render a
    // copy of a message: the long-press hero preview (isHoverPreview) and the
    // quoted snippet above a reply (isReply - which means "rendering AS a reply
    // preview", not "this message is a reply"). The reply case was doubly
    // wrong, because these fields are the OUTER message's - so the snippet
    // showed the replying message's reactions attached to the quoted one.
    final showReactions = !isReply &&
        !isHoverPreview &&
        (_messageContent.reactions?.isNotEmpty ?? false);

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
                        color: CLAccent.of(context),
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
                      color: isCurrentUser ? CLAccent.of(context) : p.border2,
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding:
                        EdgeInsets.only(top: 10, bottom: 10, left: 7, right: 7),
                    child: Text.rich(
                      TextSpan(
                        children: _mentionAwareSpans(
                          content,
                          TextStyle(
                              fontSize: CLType.title,
                              color: isCurrentUser ? Colors.white : p.text),
                          isCurrentUser ? Colors.white : CLAccent.of(context),
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
                showReactions
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: GestureDetector(
                          onTap: _openReactionsSheet,
                          child:
                              buildReactionPill(_messageContent.reactions!, p),
                        ),
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
                        color: CLAccent.of(context),
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
                        color: CLAccent.of(context),
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
                showReactions
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: GestureDetector(
                          onTap: _openReactionsSheet,
                          child:
                              buildReactionPill(_messageContent.reactions!, p),
                        ),
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
                        color: CLAccent.of(context),
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
                        color: CLAccent.of(context),
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
                showReactions
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: GestureDetector(
                          onTap: _openReactionsSheet,
                          child:
                              buildReactionPill(_messageContent.reactions!, p),
                        ),
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
                        color: CLAccent.of(context),
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
                        color: CLAccent.of(context),
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
                showReactions
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: GestureDetector(
                          onTap: _openReactionsSheet,
                          child:
                              buildReactionPill(_messageContent.reactions!, p),
                        ),
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
                        color: CLAccent.of(context),
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
                      style: TextStyle(
                          fontSize: CLType.caption, color: Color(0xFF565656)),
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
                        color: CLAccent.of(context),
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
                              style: TextStyle(
                                  fontSize: CLType.title, color: p.text),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ))
                          ],
                        ),
                      ),
                    )),
                showReactions
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: GestureDetector(
                          onTap: _openReactionsSheet,
                          child:
                              buildReactionPill(_messageContent.reactions!, p),
                        ),
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
                        color: CLAccent.of(context),
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
                style:
                    TextStyle(fontSize: CLType.body, color: Color(0xFFdedede)),
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
                                          fontSize: CLType.caption,
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
                                padding: EdgeInsets.only(
                                    left: 7, right: 7, bottom: 7),
                                child: Text(
                                  "replied to ${widget.resolveSenderName(_repliedTo!.sender)}",
                                  style: TextStyle(
                                      fontSize: CLType.caption,
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
                                // Our own dialog, not the package's: its context
                                // menu hardcodes Material typography and has no
                                // card padding. See message_reactions_dialog.dart.
                                return CLMessageReactionsDialog(
                                  // Draws your existing pick as selected, so the
                                  // row shows the current state rather than
                                  // looking untouched.
                                  myReaction: _myReactionEmoji,
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
                                        _messageContent.sender ==
                                            _currentUserID,
                                        _messageContent.sender ==
                                            _currentUserID,
                                        false,
                                        true,
                                        false),
                                  ), // message widget
                                  onReactionTap: (reaction) {
                                    _submitReaction(reaction);
                                  },
                                  onContextMenuTap: (menuItem) {
                                    if (menuItem.label == "Reply") {
                                      _onPressed(
                                          true, _messageContent.messageID);
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
                        // The Material is INSIDE the Hero so it flies with it. A
                        // hero's child is re-parented into the Navigator's overlay
                        // for the flight, leaving the page's Material behind - and
                        // without one, text falls back to DefaultTextStyle.fallback,
                        // whose yellow double-underline decoration shows straight
                        // through the bubble's own style. That's what marked the
                        // message with yellow lines on the way back from the
                        // long-press preview. transparency = no paint of its own.
                        child: Hero(
                            tag: _messageContent.messageID,
                            child: Material(
                              type: MaterialType.transparency,
                              child: messageTypeSwitch(
                                  _messageContent.content,
                                  _messageContent.messageType,
                                  _messageContent.messageID,
                                  _messageContent.sender == _currentUserID,
                                  _messageContent.sender == _currentUserID,
                                  false,
                                  false,
                                  // Reply assist v2 takes a single anchor message,
                                  // so there is no per-message selection step and
                                  // the marking checkboxes stay off.
                                  false),
                            )),
                      )
              ],
            ),
          );
        },
        converter: (store) => store.state.isUsingReplyAssist);
  }
}
