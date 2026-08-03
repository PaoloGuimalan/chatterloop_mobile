// One post: author header, caption, link preview, attachments, reaction tally
// and the action bar. The Flutter counterpart of webapp's PostItem.
//
// THIS is the unit the newsfeed will repeat. It is deliberately presentational
// plus self-contained interaction: it owns the optimistic reaction update
// (because that has to feel instant and the owner shouldn't have to
// re-implement it per surface) but nothing else. It does not fetch the post,
// does not own comments, and does not know whether it's alone on a screen or
// one row of a list.
//
// A feed row and the post screen therefore differ only in what they pass:
//
//   feed row     PostCard(post: ..., onOpen: () => push('/post/<id>'))
//   post screen  PostCard(post: ..., onOpen: null) + PostComments below it

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/link_preview_card.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_attachments.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_reactions.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_share.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/core/utils/linkify_text.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PostCard extends StatefulWidget {
  final PostPreview post;

  /// Called with the updated post after any local change (a reaction), so the
  /// owner can keep its own copy - a feed's list item, or the screen's state.
  final ValueChanged<PostPreview>? onChanged;

  /// Tapping the body opens the post. Null on the post screen itself, where
  /// there is nowhere further to go.
  final VoidCallback? onOpen;

  /// Where the comment action goes. Null renders it as a plain count.
  final VoidCallback? onComment;

  const PostCard({
    super.key,
    required this.post,
    this.onChanged,
    this.onOpen,
    this.onComment,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _reactionBusy = false;

  PostPreview get _post => widget.post;

  Future<void> _react() async {
    if (_reactionBusy) return;

    final picked = await showReactionPicker(
      context,
      currentEmojiId: _post.entityReaction,
    );
    if (picked == null || !mounted) return;

    final method = reactionMethodFor(
      currentEmojiId: _post.entityReaction,
      tappedEmojiId: picked.emojiId,
    );
    final removing = method == ReactionMethod.remove;

    final optimistic = _post.copyWith(
      reactions: applyReactionLocally(
        current: _post.reactions,
        // Both sides are emoji IDS - that's what the server's tallies are
        // keyed by, and what entity_reaction holds.
        previousEmojiId: _post.entityReaction,
        nextEmojiId: removing ? null : picked.emojiId,
      ),
      entityReaction: removing ? null : picked.emojiId,
      clearEntityReaction: removing,
    );

    setState(() => _reactionBusy = true);
    widget.onChanged?.call(optimistic);

    final ok = await NewsfeedApi().setPostReactionRequest(
      postId: _post.postId,
      emojiId: picked.emojiId,
      method: method,
    );
    if (!mounted) return;
    setState(() => _reactionBusy = false);

    if (!ok) {
      // Roll back to exactly what was on screen before the tap.
      widget.onChanged?.call(_post);
      return;
    }

    // Reconcile against the server once it has accepted: another viewer may
    // have reacted in the meantime, and the optimistic arithmetic only knew
    // about this device's change.
    final totals =
        await NewsfeedApi().getPostReactionTotalsRequest(_post.postId);
    if (!mounted || totals.isEmpty) return;
    widget.onChanged?.call(optimistic.copyWith(reactions: totals));
  }

  Future<void> _share() async {
    final shared = await showSharePostSheet(context, post: _post);
    if (!mounted || !shared) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Shared to your feed"),
      duration: Duration(seconds: 2),
    ));
  }

  void _openAuthor() {
    final author = _post.author;
    if (author.handle.isEmpty) return;
    context.push(
        author.isRealm ? '/realm/${author.handle}' : '/user/${author.handle}');
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final post = _post;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(
            children: [
              InkWell(
                onTap: _openAuthor,
                borderRadius: BorderRadius.circular(CLRadii.pill),
                child: CLAvatar(
                  id: post.author.entityId,
                  name: post.author.displayName,
                  src: post.author.profile,
                  size: 38,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: _openAuthor,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              post.author.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: CLType.title,
                                fontWeight: FontWeight.w700,
                                color: p.text,
                              ),
                            ),
                          ),
                          if (post.author.isVerified) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.verified, size: 14, color: p.brand),
                          ],
                        ],
                      ),
                      if (post.datePosted != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          timeSince(post.datePosted!),
                          style: TextStyle(
                              fontSize: CLType.caption, color: p.text3),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (post.caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: GestureDetector(
              onTap: widget.onOpen,
              child: Text.rich(
                TextSpan(
                  children: linkifySpans(
                    post.caption,
                    TextStyle(
                        fontSize: CLType.title, height: 1.45, color: p.text),
                  ),
                ),
                // A feed row clamps; the post screen shows the lot.
                maxLines: widget.onOpen == null ? null : 6,
                overflow: widget.onOpen == null
                    ? TextOverflow.clip
                    : TextOverflow.ellipsis,
              ),
            ),
          ),
        if (post.linkPreview != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: LinkPreviewCard(preview: post.linkPreview),
          ),
        // A shared post's own references are a pointer to the original, not
        // media - PostAttachments filters those out, so this is safe to call
        // unconditionally and renders nothing for a share.
        if (displayableReferences(post.references).isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: PostAttachments(references: post.references),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Row(
            children: [
              ReactionSummary(reactions: post.reactions, onTap: _react),
              const Spacer(),
              if (post.commentsCount > 0)
                InkWell(
                  onTap: widget.onComment ?? widget.onOpen,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      "${post.commentsCount} ${post.commentsCount == 1 ? 'comment' : 'comments'}",
                      style:
                          TextStyle(fontSize: CLType.caption, color: p.text3),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Divider(height: 1, color: p.border),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _PostAction(
                  // Reacting reads as the primary action, so it shows WHICH
                  // reaction is yours rather than a generic thumb.
                  icon: Icons.emoji_emotions_outlined,
                  glyph: ReactionPalette.glyphFor(post.entityReaction),
                  label: post.entityReaction != null ? "Reacted" : "React",
                  active: post.entityReaction != null,
                  onTap: _reactionBusy ? null : _react,
                ),
              ),
              Expanded(
                child: _PostAction(
                  icon: Icons.mode_comment_outlined,
                  label: "Comment",
                  onTap: widget.onComment ?? widget.onOpen,
                ),
              ),
              Expanded(
                child: _PostAction(
                  // Webapp uses Phosphor's PiShareFat: a solid arrow pointing
                  // right, NOT Material's share-node glyph (the three connected
                  // dots, which on Android reads as "open the OS share sheet" -
                  // a different action from sharing to your feed). A mirrored
                  // reply arrow is Material's nearest equivalent.
                  icon: Icons.reply,
                  mirrorIcon: true,
                  label: "Share",
                  onTap: _share,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PostAction extends StatelessWidget {
  final IconData icon;

  /// Replaces [icon] when set - the emoji the viewer actually reacted with.
  final String? glyph;

  /// Flips [icon] horizontally - what turns a reply arrow into a share arrow.
  final bool mirrorIcon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _PostAction({
    required this.icon,
    this.glyph,
    this.mirrorIcon = false,
    required this.label,
    this.active = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final color = active ? p.brand : p.text2;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CLRadii.sm),
      child: Opacity(
        opacity: onTap == null ? 0.55 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (glyph != null)
                Text(glyph!, style: const TextStyle(fontSize: 16))
              else if (mirrorIcon)
                Transform.flip(
                  flipX: true,
                  child: Icon(icon, size: 18, color: color),
                )
              else
                Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: CLType.label,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
