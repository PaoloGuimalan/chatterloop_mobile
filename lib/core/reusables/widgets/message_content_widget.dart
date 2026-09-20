import 'package:chatterloop_app/core/reusables/widgets/message_reactions_dialog.dart';
import 'package:chatterloop_app/core/reusables/widgets/reactions_sheet.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/core/reusables/players/voice_message_player.dart';
import 'package:chatterloop_app/core/reusables/widgets/link_preview_card.dart';
import 'package:chatterloop_app/core/reusables/widgets/media_viewer.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/core/reusables/widgets/report_sheet.dart';
import 'package:chatterloop_app/core/utils/message_format.dart';
import 'package:chatterloop_app/core/utils/media_downloader.dart';
import 'package:chatterloop_app/models/http_models/request_models.dart';
import 'package:chatterloop_app/models/messages_models/message_content_model.dart';
import 'package:chatterloop_app/models/messages_models/message_item_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_redux/flutter_redux.dart';

/// Mirrors webapp's EmojiPickerHandler.tsx QUICK_REACTIONS exactly. The
/// "more emojis" affordance is NOT in this list - the package renders every
/// entry here as plain emoji-sized Text, so a "➕" character here always
/// reads as a mismatched, low-res emoji rather than an app icon. It lives
/// instead as a real Material icon in the context-menu row below (see
/// _menuItemsFor), which the package renders as an actual Icon widget.
const List<String> _quickReactions = ['👍', '❤️', '😆', '😮', '😢', '😡'];

/// The long-press menu for one message, in the order it is drawn.
///
/// Spelled out here rather than spreading kDefaultMessageMenuItems: that list
/// put Delete third and offered it unconditionally. Order is now
///
///   Reply · Copy · React · (Delete | Report)
///
/// with the destructive entry always last. The two are mutually exclusive and
/// both key off authorship:
///
///   Delete  YOURS only. /m/deletemessage rejects a message you didn't send
///           ("You do not own this message"), so offering it on someone
///           else's was an action that could only ever fail.
///   Report  everyone ELSE's. A message report resolves to its sender's
///           entity, so reporting your own would be reporting yourself.
///
/// "React" is a real Icon(Icons.add_reaction_outlined) rather than an emoji
/// character - the package renders every label's icon as an Icon widget, and
/// a "➕" glyph here reads as a mismatched, low-res emoji.
List<MenuItem> _menuItemsFor({
  required bool isOwnMessage,
  required bool isCopyable,
  required bool isDownloadable,
}) =>
    [
      const MenuItem(label: 'Reply', icon: Icons.reply),
      // Off for a system notice and for an empty message - see _isCopyable.
      // An entry that cannot do anything is the state this one was already in
      // for every message, and it is the thing being fixed.
      if (isCopyable) const MenuItem(label: 'Copy', icon: Icons.copy),
      const MenuItem(label: 'React', icon: Icons.add_reaction_outlined),
      // Anything with a file behind it - a photo, a video, a voice message, a
      // document. The bubble itself only offers this for the types where a
      // button fits (the file card, and the viewer a photo/video opens into),
      // so for a voice message this menu is the ONLY way to save it.
      if (isDownloadable)
        const MenuItem(label: 'Save', icon: Icons.download_rounded),
      if (isOwnMessage)
        const MenuItem(
          label: 'Delete',
          icon: Icons.delete_forever,
          isDestructive: true,
        ),
      if (!isOwnMessage)
        const MenuItem(
          label: 'Report',
          icon: Icons.report,
          // Red, like Delete - every LABELLED report entry in the app is.
          isDestructive: true,
        ),
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

  /// Command names available in this conversation. Only these are highlighted
  /// in message text - see chat_commands.splitLeadingCommand.
  final Set<String> commandNames;

  const MessageContentWidget(
      {super.key,
      required this.messageContent,
      required this.previousContentUserID,
      required this.currentUserID,
      required this.onPressed,
      required this.resolveSenderName,
      required this.isSingleConversation,
      required this.conversationID,
      this.mentionMembers = const [],
      this.commandNames = const {}});

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

  /// Report this message. Sends the MESSAGE id - the server looks the message
  /// up and resolves its sender's entity, so the report lands on whoever sent
  /// it without this widget having to know who that is.
  ///
  /// True when this message has a real file behind it, i.e. anything but a
  /// plain text bubble and the centred system "notif" line. Deliberately NOT a
  /// list of known media types: the server resolves the real mimetype on
  /// upload, so a message can arrive as "application/pdf", "image/heic" or
  /// anything else a user picked - and every one of those is downloadable.
  bool get _isDownloadable =>
      _messageContent.messageType != "text" &&
      _messageContent.messageType != "notif" &&
      _messageContent.isDeleted != true &&
      _messageContent.content.trim().isNotEmpty;

  /// Fetches an attachment and files it away on the device. Fire-and-forget:
  /// it keeps running after this bubble (or the whole conversation) is gone,
  /// and reports where the file landed through the app-wide messenger.
  void _downloadAttachment(String content, String messageType) {
    MediaDownloader.instance.download(content, mimeType: messageType);
  }

  /// What "Copy" puts on the clipboard.
  ///
  /// A text message copies its words. Anything with a file behind it copies
  /// the file's URL - that is the only thing about such a message that can BE
  /// text, and a link is what someone reaching for Copy on a photo wants. It
  /// goes through [chatMediaUrl] rather than the raw field so the copied link
  /// is the one that actually resolves: the stored value can carry the legacy
  /// "url%%%filename" suffix, and an unescaped "###" inside a storage key
  /// turns everything after it into a fragment.
  ///
  /// A system notice ("notif") is excluded by [_isCopyable] rather than
  /// handled here - it is the app talking, not a message anyone wrote.
  String get _copyText => _messageContent.messageType == "text"
      ? _messageContent.content
      : chatMediaUrl(_messageContent.content);

  /// Whether the menu offers Copy at all. There is nothing to put on a
  /// clipboard for an empty message or a system notice.
  bool get _isCopyable =>
      _messageContent.messageType != "notif" &&
      _messageContent.isDeleted != true &&
      _copyText.trim().isNotEmpty;

  /// Was never wired - the menu entry rendered and did nothing when tapped,
  /// which is worse than not offering it.
  ///
  /// The dialog has already closed by the time this runs (see
  /// CLMessageReactionsDialog's _handleMenuTap, which pops before calling
  /// back), so the confirmation lands on the conversation rather than behind a
  /// full-screen overlay. Confirmed at all because a clipboard write is
  /// completely invisible otherwise: nothing on screen changes, and the only
  /// way to find out whether it worked is to go and paste it somewhere.
  Future<void> _copyMessage() async {
    await Clipboard.setData(ClipboardData(text: _copyText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_messageContent.messageType == "text"
          ? "Message copied"
          : "Link copied"),
      duration: const Duration(seconds: 2),
    ));
  }

  /// Opens one attachment full screen.
  ///
  /// A single-item viewer rather than a gallery of the thread's media: a
  /// conversation's attachments are spread across separate messages with no
  /// ordering a carousel could honour, unlike a post's, which are one set.
  void _openInViewer(String content, String messageType) {
    openMediaViewer(
      context,
      [
        MediaViewerItem(
          source: content,
          isVideo: messageType.contains("video"),
          mimeType: messageType,
        )
      ],
      0,
    );
  }

  /// Fires after the long-press dialog has already popped itself (see
  /// _handleMenuTap), so the sheet opens onto the thread rather than on top of
  /// a dialog that is mid-dismissal.
  void _reportMessage(BuildContext context) {
    showReportSheet(
      context,
      targetType: ReportTargetType.message,
      targetId: _messageContent.messageID,
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
    //
    // The inline delete/reply icons beside a bubble are dropped in BOTH for the
    // same reason, plus one of its own: the long-press preview already offers
    // Reply and Delete in the menu right below it, so the icons were a second
    // copy of two actions - and the Expanded holding them took ~80px from a
    // bubble that only has the dialog's width to work with. A file card, capped
    // at 270, then overflowed a 360px phone by 40.
    final showReactions = !isReply &&
        !isHoverPreview &&
        (_messageContent.reactions?.isNotEmpty ?? false);

    if (messageType == "text") {
      return Row(
        mainAxisAlignment:
            isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          !isMarkingEnabled && !isHoverPreview
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
                    // THE FULL RENDERER for a quote too, not the flattened
                    // preview. A quote used to take the plain-text form on the
                    // reasoning that a heading or a code fence is debris at
                    // this size - but the messages people quote most are bot
                    // replies, which are model prose: headings, numbered
                    // steps, bold and bullets. Flattened, that arrives as a
                    // wall of run-together sentences, harder to read than the
                    // formatting ever was.
                    //
                    // The COMPOSER's reply panel still flattens (see
                    // _quotedPreview): it is a clamped two lines, where blocks
                    // genuinely cannot render.
                    child: isReply
                        ? buildFormattedMessage(
                            source: content,
                            members: widget.mentionMembers,
                            commands: widget.commandNames,
                            style: MessageFormatStyle(
                              base: TextStyle(
                                  fontSize: CLType.title,
                                  color:
                                      isCurrentUser ? Colors.white : p.text),
                              mentionColor: isCurrentUser
                                  ? Colors.white
                                  : CLAccent.textOf(context),
                            ),
                          )
                        : buildFormattedMessage(
                            source: content,
                            members: widget.mentionMembers,
                            commands: widget.commandNames,
                            style: MessageFormatStyle(
                              base: TextStyle(
                                  fontSize: CLType.title,
                                  color: isCurrentUser ? Colors.white : p.text),
                              // On your own (brand-coloured) bubble the text is
                              // already white, so a mention is distinguished by
                              // weight alone - a second colour there would either
                              // be invisible or clash.
                              // textOf, not of: on somebody else's bubble the
                              // mention is a LABEL on an ordinary surface, and
                              // in a channel the fill colour is too light to
                              // read there. On your own bubble it stays white -
                              // the bubble IS the accent.
                              mentionColor: isCurrentUser
                                  ? Colors.white
                                  : CLAccent.textOf(context),
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
          !isMarkingEnabled && !isHoverPreview
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
          !isMarkingEnabled && !isHoverPreview
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
                    child: GestureDetector(
                      // The whole tile takes the tap, not just wherever the
                      // picture happens to be painting. CLNetworkImage fades
                      // itself in from zero opacity, and a zero-opacity
                      // subtree ignores pointers - so with the default
                      // deferToChild the photo was untappable until it had
                      // finished loading, and permanently untappable if it
                      // never did.
                      behavior: HitTestBehavior.opaque,
                      // Not on either preview copy of a message: the
                      // long-press hero (isHoverPreview) is a modal whose
                      // whole surface dismisses it, and the quoted snippet
                      // above a reply (isReply) is a pointer to a message, not
                      // the message - tapping it should do what tapping a
                      // quote does, which is nothing.
                      onTap: isReply || isHoverPreview
                          ? null
                          : () => _openInViewer(content, messageType),
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
                              // Normalised, like every other attachment: the
                              // raw content of a legacy Google Cloud Storage
                              // upload is "url%%%filename", which is not a url
                              // and does not load. A no-op on the plain urls
                              // every current upload produces.
                              src: chatMediaUrl(content),
                            ),
                          ),
                        ),
                      ),
                    ),
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
          !isMarkingEnabled && !isHoverPreview
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
          !isMarkingEnabled && !isHoverPreview
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
                      videoUrl: chatMediaUrl(content),
                      // Expanding lands in the same viewer a photo opens into,
                      // so the save action sits in one place for both kinds of
                      // media - rather than in the bare full-screen player,
                      // which has no actions at all.
                      onFullscreen: () => _openInViewer(content, messageType),
                    ),
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
          !isMarkingEnabled && !isHoverPreview
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
          !isMarkingEnabled && !isHoverPreview
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
          !isMarkingEnabled && !isHoverPreview
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
          !isMarkingEnabled && !isHoverPreview
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
                    // Was an empty callback - the card rendered and tapping it
                    // did nothing at all. Tapping a file now downloads it, and
                    // this branch is every message type that is not text,
                    // image, video, audio or notif, so that covers ANY file a
                    // sender attached.
                    //
                    // Inert on a preview copy: the hero (isHoverPreview) sits
                    // under a menu whose Save entry does exactly this, and the
                    // quoted snippet above a reply (isReply) points at a
                    // message rather than being one. INERT, not null - a null
                    // onPressed renders the card in Material's disabled
                    // colours, and a preview should look like the bubble it is
                    // previewing.
                    onPressed: isReply || isHoverPreview
                        ? () {}
                        : () => _downloadAttachment(content, messageType),
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
                            _AttachmentDownloadIcon(content: content),
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
          !isMarkingEnabled && !isHoverPreview
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
          // Resolved HERE, where the thread's CLAccent is in scope - gold in a
          // channel, brand blue in a conversation. Both the long-press route
          // and the hero flight leave that scope behind, so each has to be
          // handed the colour rather than looking it up for itself.
          final accent = CLAccent.of(context);
          // The LABEL form travels with it. Carrying only the fill left the
          // long-press preview and the hero flight resolving textOf to the
          // raw accent, so a mention in a channel went from the readable gold
          // to the fill gold for the length of the animation.
          final accentOnSurface = CLAccent.textOf(context);
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
                                  menuItems: _menuItemsFor(
                                    isOwnMessage: _messageContent.sender ==
                                        _currentUserID,
                                    isCopyable: _isCopyable,
                                    isDownloadable: _isDownloadable,
                                  ),
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
                                  messageWidget: CLAccent(
                                    color: accent,
                                    onSurface: accentOnSurface,
                                    // A route builds under the Navigator, not
                                    // under the widget that pushed it, so the
                                    // thread's CLAccent is not an ancestor of
                                    // anything in here.
                                    //
                                    // messageTypeSwitch resolves its own
                                    // colours against the STATE's context, so
                                    // the bubble itself was already right - but
                                    // a child widget that reads the accent from
                                    // where it is MOUNTED (the voice message
                                    // player) resolved it here, where there was
                                    // none, and fell back to brand blue. Held
                                    // your own voice message blue in a gold
                                    // channel, but only while long-pressed.
                                    child: Material(
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
                                    ),
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
                                    } else if (menuItem.label == "Save") {
                                      // The dialog has already closed itself
                                      // by the time this runs (see
                                      // _handleMenuTap), so the download's
                                      // snackbar lands on the conversation
                                      // rather than behind a full-screen
                                      // overlay.
                                      _downloadAttachment(
                                          _messageContent.content,
                                          _messageContent.messageType);
                                    } else if (menuItem.label == "Delete") {
                                      // Was unhandled - the entry rendered and
                                      // did nothing when tapped. Same call the
                                      // inline delete button beside the bubble
                                      // already makes, including its
                                      // deliberate lack of a confirmation
                                      // (see _deleteMessage).
                                      _deleteMessage(_messageContent.messageID);
                                    } else if (menuItem.label == "Report") {
                                      _reportMessage(context);
                                    } else if (menuItem.label == "Copy") {
                                      _copyMessage();
                                    }
                                  },
                                );
                              },
                            ),
                          );
                        },
                        // The Material and the CLAccent are INSIDE the Hero so
                        // they fly with it. A hero's child is re-parented into
                        // the Navigator's overlay for the flight, which belongs
                        // to NEITHER route - so everything the child inherits
                        // from the page is gone for the duration.
                        //
                        // Material, because without one text falls back to
                        // DefaultTextStyle.fallback, whose yellow
                        // double-underline decoration shows straight through the
                        // bubble's own style. That is what marked the message
                        // with yellow lines on the way back from the long-press
                        // preview. transparency = no paint of its own.
                        //
                        // CLAccent for the same reason, found the same way: the
                        // default hero flight renders the DESTINATION hero's
                        // child, which on a pop is this one - so a gold channel
                        // bubble flashed brand blue for the length of the
                        // animation back. Only on the way back, because the way
                        // in flies the dialog's copy, which carries its own.
                        child: Hero(
                            tag: _messageContent.messageID,
                            child: CLAccent(
                              color: accent,
                              onSurface: accentOnSurface,
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
                                    // Reply assist v2 takes a single anchor
                                    // message, so there is no per-message
                                    // selection step and the marking checkboxes
                                    // stay off.
                                    false),
                              ),
                            )),
                      )
              ],
            ),
          );
        },
        converter: (store) => store.state.isUsingReplyAssist);
  }
}

/// The file card's leading glyph: the file icon normally, a progress ring
/// while that file is being downloaded.
///
/// Reads the downloader's notifier rather than any local state, because the
/// download outlives this widget. A bubble scrolled off screen and rebuilt -
/// or a conversation left and reopened - picks the ring back up mid-download
/// instead of offering to start a second copy of the same file.
class _AttachmentDownloadIcon extends StatelessWidget {
  final String content;

  const _AttachmentDownloadIcon({required this.content});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: MediaDownloader.instance.progress,
      builder: (context, running, _) {
        final value = running[chatMediaUrl(content)];
        if (value == null) {
          return Icon(
            Icons.file_copy_outlined,
            color: p.text,
            size: 35,
          );
        }
        return SizedBox(
          // The icon's own box, so the card does not resize when a download
          // starts and the row does not jump.
          width: 35,
          height: 35,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: p.text,
                // 0 means the response carried no Content-Length, so there is
                // no percentage to draw - spin rather than sit at an empty
                // ring that reads as stuck.
                value: value > 0 ? value : null,
              ),
            ),
          ),
        );
      },
    );
  }
}
