// The quoted card above a message that replies to - or sends - a post, a
// moment or a thought. Message replies keep their existing quote
// (messageTypeSwitch over replyedmessage); this draws the other three from the
// server's `replyedtarget`. Mirrors webapp's ReplyTargetPreview.tsx.
//
// One layout for all three: a thumbnail (or a glyph when there is no media),
// "Kind · Author", and a line of text. A card that has expired or become
// unavailable keeps its author - so the reply still reads as "about Ana's
// moment" - and swaps the content for a muted line saying why it is gone.

import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/models/messages_models/reply_target_model.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// "sent a post" / "replied to your moment" / "replied to Ana's thought" -
/// the small label above a non-message reply, where a message reply says
/// "replied to X".
/// One line for what a note-less message carried - the composer's reply
/// panel when you reply to it ("Sent a post · caption", "Moment · caption",
/// "Thought · its text"). Web's replyPreviewLabel, with the target's words.
String replyTargetSummary(ReplyTarget target) {
  final words =
      (target.type == ReplyTarget.typeThought ? target.text : target.caption)
          ?.trim();
  final kind = switch (target.type) {
    ReplyTarget.typePost => "Sent a post",
    ReplyTarget.typeMoment => "Moment",
    ReplyTarget.typeThought => "Thought",
    _ => "Message",
  };
  return words == null || words.isEmpty ? kind : "$kind · $words";
}

String replyTargetLabel(ReplyTarget target, {required String currentEntityId}) {
  if (target.type == ReplyTarget.typePost) return "sent a post";
  final author = target.author;
  final owner = author == null
      ? "a"
      : author.entityId == currentEntityId
          ? "your"
          : author.displayName.isNotEmpty
              ? "${author.displayName}'s"
              : "a";
  return "replied to $owner ${target.type}";
}

class ReplyTargetCard extends StatefulWidget {
  final ReplyTarget target;

  /// Whether the REPLY is yours - which side of the thread the card sits on.
  final bool alignEnd;

  /// The card IS the message (a post sent with no note), not a quote: a
  /// normal bubble's surface instead of the faded quote look.
  final bool asMessage;

  const ReplyTargetCard({
    super.key,
    required this.target,
    this.alignEnd = false,
    this.asMessage = false,
  });

  @override
  State<ReplyTargetCard> createState() => _ReplyTargetCardState();
}

class _ReplyTargetCardState extends State<ReplyTargetCard> {
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    _scheduleExpiry();
  }

  @override
  void didUpdateWidget(ReplyTargetCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.expiresAt != widget.target.expiresAt) {
      _scheduleExpiry();
    }
  }

  /// Rebuilds once, the moment a live moment/thought expires, so the card
  /// greys out while the conversation is open rather than on the next load.
  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final expiresAt = widget.target.expiresAt;
    if (expiresAt == null) return;
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return;
    _expiryTimer = Timer(remaining + const Duration(milliseconds: 500), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  String get _kindLabel {
    final target = widget.target;
    switch (target.type) {
      case ReplyTarget.typeMoment:
        return "Moment";
      case ReplyTarget.typeThought:
        return "Thought";
      default:
        return target.sharedPostId != null ? "Shared post" : "Post";
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final target = widget.target;
    final live = target.isLiveAt(DateTime.now());

    // Only a live feed post has somewhere to go today: moments get their
    // viewer in phase 2, and a thought is entirely on the card already.
    final opensPost = live && target.type == ReplyTarget.typePost;
    final text =
        target.type == ReplyTarget.typeThought ? target.text : target.caption;
    final goneLine = target.isUnavailable
        ? "This ${target.type} is no longer available"
        : "$_kindLabel expired";
    final authorName = target.author?.displayName ?? "";
    // The thumbnail box is for media. A moment always has some (its box also
    // shows the expired glyph); a post only when it carries an attachment - a
    // text post, a share, or one that is gone gets no empty placeholder.
    final showThumbnail = target.type == ReplyTarget.typeMoment ||
        (target.type == ReplyTarget.typePost &&
            live &&
            target.thumbnail != null);

    final card = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Material(
        // As a message: a step off the conversation's surface, with an edge
        // and a lift - on the plain surface it had no edge against the thread
        // and read flat. The same for yours and theirs (no brand tint).
        color: widget.asMessage ? p.surface2 : p.surface3,
        elevation: widget.asMessage ? 2 : 0,
        shadowColor: Colors.black38,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CLRadii.sm),
          side: BorderSide(color: p.border2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: opensPost
              ? () => context.push('/post/${target.sharedPostId ?? target.id}')
              : null,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showThumbnail) ...[
                  _Thumbnail(target: target, live: live),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authorName.isEmpty
                            ? _kindLabel
                            : "$_kindLabel · $authorName",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: CLType.meta, color: p.text3),
                      ),
                      if (live && text != null && text.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: CLType.caption, color: p.text),
                        ),
                      ],
                      if (!live) ...[
                        const SizedBox(height: 2),
                        Text(
                          goneLine,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: CLType.caption,
                            color: p.text3,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Row(
        mainAxisAlignment:
            widget.alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [Flexible(child: card)],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final ReplyTarget target;
  final bool live;

  const _Thumbnail({required this.target, required this.live});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    // A moment is portrait, like the moment itself; a post's square.
    final isMoment = target.type == ReplyTarget.typeMoment;
    final width = isMoment ? 40.0 : 52.0;
    final height = isMoment ? 64.0 : 52.0;
    final thumbnail = live ? target.thumbnail : null;

    Widget child;
    if (thumbnail != null && !target.isVideo) {
      child = CLNetworkImage(
        src: thumbnail,
        width: width,
        height: height,
        fit: BoxFit.cover,
        placeholderHeight: height,
      );
    } else {
      // A video's first frame would mean a player per card in a chat; a
      // glyph says the same thing for nothing.
      child = Icon(
        !live
            ? Icons.schedule_rounded
            : target.isVideo
                ? Icons.play_circle_outline_rounded
                : Icons.image_outlined,
        color: p.text3,
        size: 22,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(CLRadii.xs),
      child: Container(
        width: width,
        height: height,
        color: p.surface2,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
