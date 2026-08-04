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
import 'package:chatterloop_app/core/requests/feed_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/link_preview_card.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_attachments.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_composer.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_options.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_reactions.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_share.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_tagging.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/core/utils/linkify_text.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PostCard extends StatefulWidget {
  final PostPreview post;

  /// Called with the updated post after any local change (a reaction), so the
  /// owner can keep its own copy - a feed's list item, or the screen's state.
  final ValueChanged<PostPreview>? onChanged;

  /// Marks this as a ROW rather than the post's own screen, and says where
  /// "open the post" goes. Null on the screen itself, where there is nowhere
  /// further to go.
  ///
  /// It no longer makes the body tappable - only the comment affordances open
  /// a post now, so that tapping a video plays it and tapping a link follows
  /// it, rather than either navigating away. What this still decides is what
  /// differs between a row and a screen: the caption clamps in a row.
  final VoidCallback? onOpen;

  /// Where the comment action goes - the ONLY route from a row into the post.
  /// Null renders the count as plain text.
  final VoidCallback? onComment;

  /// Fired after the options menu deletes this post. A feed drops the row; the
  /// post screen pops. Null hides nothing - the menu still offers Delete, it
  /// just leaves the caller to notice, so surfaces that can react pass this.
  final VoidCallback? onDeleted;

  /// Shared-post recursion mode: false hides the reaction summary and
  /// react/comment/share row while keeping the full body (header/caption/media).
  final bool showEngagement;

  /// Current nesting depth when rendering shared-post recursion.
  final int sharedDepth;

  /// Safety cap against accidental cyclic share chains.
  final int maxSharedDepth;

  const PostCard({
    super.key,
    required this.post,
    this.onChanged,
    this.onOpen,
    this.onComment,
    this.onDeleted,
    this.showEngagement = true,
    this.sharedDepth = 0,
    this.maxSharedDepth = 6,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _reactionBusy = false;

  Future<PostPreview?>? _sharedPostFuture;
  String? _sharedPostId;

  @override
  void initState() {
    super.initState();
    _syncSharedPostFuture();
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.post.postId != widget.post.postId ||
        oldWidget.post.isShared != widget.post.isShared ||
        oldWidget.post.sharedPostId != widget.post.sharedPostId) {
      _syncSharedPostFuture();
    }
  }

  void _syncSharedPostFuture() {
    final sharedId = widget.post.sharedPostId;
    if (widget.post.isShared &&
        sharedId != null &&
        sharedId.isNotEmpty &&
        widget.sharedDepth < widget.maxSharedDepth) {
      _sharedPostId = sharedId;
      _sharedPostFuture = FeedApi().getPostPreviewRequest(sharedId);
      return;
    }

    _sharedPostId = null;
    _sharedPostFuture = null;
  }

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

  Widget _sharedUnavailableCard(CLPalette p, {String? label}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(CLRadii.md),
        border: Border.all(color: p.border),
      ),
      child: Text(
        label ?? 'Original shared post is unavailable.',
        style: TextStyle(fontSize: CLType.caption, color: p.text3),
      ),
    );
  }

  Widget _sharedPostCard(CLPalette p) {
    final future = _sharedPostFuture;
    if (widget.sharedDepth >= widget.maxSharedDepth) {
      return _sharedUnavailableCard(
        p,
        label: 'Nested shared post limit reached.',
      );
    }

    if (future == null || _sharedPostId == null) {
      return _sharedUnavailableCard(p);
    }

    return FutureBuilder<PostPreview?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: BorderRadius.circular(CLRadii.md),
              border: Border.all(color: p.border),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: p.brand,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Loading shared post...',
                  style: TextStyle(fontSize: CLType.caption, color: p.text3),
                ),
              ],
            ),
          );
        }

        final shared = snapshot.data;
        if (shared == null) return _sharedUnavailableCard(p);

        return ClipRRect(
          borderRadius: BorderRadius.circular(CLRadii.md),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(CLRadii.md),
              border: Border.all(color: p.border),
            ),
            child: PostCard(
              post: shared,
              onOpen: () => context.push('/post/${shared.postId}'),
              showEngagement: false,
              sharedDepth: widget.sharedDepth + 1,
              maxSharedDepth: widget.maxSharedDepth,
            ),
          ),
        );
      },
    );
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
    final privacyIcon = postPrivacyIcon(post.privacyStatus);

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Author + "is with A, B and C" as ONE wrapping sentence.
                    // Spans, not a Row of widgets: a Row can't wrap mid-phrase,
                    // so a couple of tagged names would either overflow or push
                    // the author's own name to an ellipsis.
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: post.author.displayName,
                          style: TextStyle(
                            fontSize: CLType.title,
                            fontWeight: FontWeight.w700,
                            color: p.text,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = _openAuthor,
                        ),
                        if (post.author.isVerified)
                          const TextSpan(text: "\u00A0\u2060"),
                        if (post.author.isVerified)
                          TextSpan(
                            text: String.fromCharCode(Icons.verified.codePoint),
                            style: TextStyle(
                              fontFamily: Icons.verified.fontFamily,
                              package: Icons.verified.fontPackage,
                              fontSize: 14,
                              color: p.brand,
                            ),
                          ),
                        ...taggingSummarySpans(
                          context,
                          post.tagged,
                          baseStyle: TextStyle(
                              fontSize: CLType.title, color: p.text2),
                          linkColor: p.text,
                        ),
                      ]),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (post.datePosted != null ||
                        post.isArchived ||
                        privacyIcon != null) ...[
                      const SizedBox(height: 2),
                      GestureDetector(
                        onTap: _openAuthor,
                        // Spans rather than a Row for the same reason the line
                        // above uses them: "2h ago + Archived" has to be able
                        // to wrap, and a Row can't.
                        child: Text.rich(
                          TextSpan(
                            style: TextStyle(
                                fontSize: CLType.caption, color: p.text3),
                            children: [
                              // Before the date, at the same size as the
                              // Archived marker beside it - an icon on its own,
                              // since a word for every post's audience would be
                              // noise on the common case (public).
                              if (privacyIcon != null) ...[
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Icon(privacyIcon,
                                        size: 12, color: p.text3),
                                  ),
                                ),
                              ],
                              if (post.datePosted != null)
                                TextSpan(text: timeSince(post.datePosted!)),
                              // Archiving doesn't remove the row from the
                              // author's own profile, so without this the
                              // menu's only feedback would be the label
                              // flipping to "Unarchive" next time it's opened.
                              if (post.isArchived) ...[
                                if (post.datePosted != null)
                                  const TextSpan(text: " \u00B7 "),
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 3),
                                    child: Icon(Icons.archive_outlined,
                                        size: 12, color: p.text3),
                                  ),
                                ),
                                const TextSpan(text: "Archived"),
                              ],
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Hidden inside a nested shared post: its options belong to the
              // original, which the reader can open in its own right.
              if (widget.showEngagement)
                PostOptionsButton(
                  post: post,
                  onChanged: widget.onChanged,
                  onDeleted: widget.onDeleted,
                ),
            ],
          ),
        ),
        if (post.caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            // Deliberately NOT a tap target for opening the post. The comment
            // affordances are the only way in - so a tap anywhere else in a row
            // (a link, a video, a tagged name) does what it looks like it does
            // instead of navigating away mid-gesture.
            child: GestureDetector(
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
        if (post.isShared)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _sharedPostCard(p),
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
            // Plays in place wherever it appears, feed row included - a video
            // you have to open a screen to watch isn't a feed. Safe to do in
            // both at once because the row and the screen share ONE controller
            // per url; see SharedVideoControllers.
            child: PostAttachments(references: post.references),
          ),
        if (widget.showEngagement)
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
                        style: TextStyle(
                          fontSize: CLType.caption,
                          color: p.text3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (widget.showEngagement)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Divider(height: 1, color: p.border),
          ),
        if (widget.showEngagement)
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
        if (!widget.showEngagement)
          const SizedBox(height: 12),
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
              // Flexible so the label ellipsizes rather than overflowing: the
              // three actions split the row evenly, and the slot narrows with
              // anything wrapping the card (PostItem's border) or at a large
              // text scale. Same reason CLMiniBtn's label is flexible.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: CLType.label,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
