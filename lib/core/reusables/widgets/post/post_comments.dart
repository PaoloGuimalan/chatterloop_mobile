// A post's comment thread: paginated list, replies, per-comment reactions and
// the composer.
//
// Threads are TWO levels by server design - a top-level comment and its
// replies, with a reply-to-a-reply re-parented to the top-level ancestor. So
// this renders exactly two levels and never recurses; replies are fetched
// lazily per comment, because a post with fifty comments shouldn't fetch fifty
// reply pages nobody expanded.
//
// Owns no post state: it reports comment-count changes through [onCountChanged]
// so whoever renders the post (this screen now, a feed row later) keeps its own
// count right.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/link_preview_card.dart';
import 'package:chatterloop_app/core/reusables/widgets/paginated_scroll.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_reactions.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/core/utils/linkify_text.dart';
import 'package:chatterloop_app/models/post_models/newsfeed_models.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const int _kCommentsPageSize = 20;

/// The comment thread, as a section inside the post screen's scroll view.
///
/// Not a sheet: the post screen shows the post and its comments as one
/// continuous read, which is what web does and what makes the comment count in
/// the action bar mean "scroll down", not "open a thing".
class PostComments extends StatefulWidget {
  final String postId;

  /// Fires with the signed delta whenever a comment is added, so the owner can
  /// keep the post's own count in step without refetching the post.
  final ValueChanged<int>? onCountChanged;

  /// Who the composer is replying to, owned by the SCREEN.
  ///
  /// The composer is docked to the bottom of the viewport (like the
  /// conversation screen's input) rather than sitting at the end of this list,
  /// so it lives outside this widget - but "Reply" is tapped in here. A
  /// notifier is what lets the two talk without either owning the other.
  final ValueNotifier<PostComment?>? replyTarget;

  const PostComments({
    super.key,
    required this.postId,
    this.onCountChanged,
    this.replyTarget,
  });

  @override
  State<PostComments> createState() => PostCommentsState();
}

class PostCommentsState extends State<PostComments> {
  final List<PostComment> _comments = [];

  int _page = 0;
  bool _hasNext = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  /// Replies fetched per top-level comment id, and which of those are expanded.
  final Map<String, List<PostComment>> _replies = {};
  final Set<String> _expanded = <String>{};
  final Set<String> _repliesLoading = <String>{};

  /// Reaction taps in flight, keyed by comment id.
  final Set<String> _reactionBusy = <String>{};

  PostComment? get _replyingTo => widget.replyTarget?.value;

  @override
  void initState() {
    super.initState();
    _fetch(1);
  }

  Future<void> _fetch(int page) async {
    if (page == 1) {
      setState(() => _isLoading = true);
    } else {
      if (_isLoadingMore || !_hasNext) return;
      setState(() => _isLoadingMore = true);
    }

    final result = await NewsfeedApi().getCommentsRequest(
      postId: widget.postId,
      page: page,
      pageSize: _kCommentsPageSize,
    );
    if (!mounted) return;

    setState(() {
      if (page == 1) _comments.clear();
      _comments.addAll(result.results);
      _page = page;
      _hasNext = result.hasNext;
      _isLoading = false;
      _isLoadingMore = false;
    });
  }

  /// Public so the post screen's pull-to-refresh reloads comments too.
  Future<void> reload() => _fetch(1);

  void loadMore() {
    if (_hasNext && !_isLoadingMore && !_isLoading) _fetch(_page + 1);
  }

  bool get hasMore => _hasNext;

  Future<void> _loadReplies(PostComment comment) async {
    if (_repliesLoading.contains(comment.commentId)) return;
    setState(() => _repliesLoading.add(comment.commentId));

    final result = await NewsfeedApi().getCommentsRequest(
      postId: widget.postId,
      parentId: comment.commentId,
      pageSize: _kCommentsPageSize,
    );
    if (!mounted) return;
    setState(() {
      _replies[comment.commentId] = result.results;
      _repliesLoading.remove(comment.commentId);
    });
  }

  void _toggleReplies(PostComment comment) {
    final id = comment.commentId;
    if (_expanded.contains(id)) {
      setState(() => _expanded.remove(id));
      return;
    }
    setState(() => _expanded.add(id));
    if (!_replies.containsKey(id)) _loadReplies(comment);
  }

  /// Optimistic, same three-verb rule as a post reaction.
  Future<void> _react(PostComment comment, {required bool isReply}) async {
    if (_reactionBusy.contains(comment.commentId)) return;

    final picked = await showReactionPicker(
      context,
      currentEmojiId: comment.entityReaction,
    );
    if (picked == null || !mounted) return;

    final method = reactionMethodFor(
      currentEmojiId: comment.entityReaction,
      tappedEmojiId: picked.emojiId,
    );
    final removing = method == ReactionMethod.remove;

    final updated = comment.copyWith(
      reactions: applyReactionLocally(
        current: comment.reactions,
        // Emoji IDS both sides - see applyReactionLocally.
        previousEmojiId: comment.entityReaction,
        nextEmojiId: removing ? null : picked.emojiId,
      ),
      entityReaction: removing ? null : picked.emojiId,
      clearEntityReaction: removing,
    );

    setState(() {
      _reactionBusy.add(comment.commentId);
      _replaceComment(updated, isReply: isReply);
    });

    final ok = await NewsfeedApi().setCommentReactionRequest(
      commentId: comment.commentId,
      emojiId: picked.emojiId,
      method: method,
    );
    if (!mounted) return;
    setState(() {
      _reactionBusy.remove(comment.commentId);
      // Put the original back on failure rather than leaving a count the
      // server never accepted.
      if (!ok) _replaceComment(comment, isReply: isReply);
    });
  }

  void _replaceComment(PostComment comment, {required bool isReply}) {
    if (isReply) {
      final parentId = comment.parentId;
      final list = parentId == null ? null : _replies[parentId];
      if (list == null) return;
      for (var i = 0; i < list.length; i++) {
        if (list[i].commentId == comment.commentId) list[i] = comment;
      }
      return;
    }
    for (var i = 0; i < _comments.length; i++) {
      if (_comments[i].commentId == comment.commentId) {
        _comments[i] = comment;
      }
    }
  }

  /// Called by the screen's docked composer.
  Future<void> submitComment(String text) async {
    final target = _replyingTo;
    final ok = await NewsfeedApi().addCommentRequest(
      postId: widget.postId,
      parentId: target?.commentId,
      text: text,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't post that comment. Try again."),
        duration: Duration(seconds: 2),
      ));
      return;
    }

    widget.onCountChanged?.call(1);
    widget.replyTarget?.value = null;

    // The endpoint answers "OK", not the created row - it has the id, the
    // timestamp and the resolved author, none of which can be synthesised
    // here, so the affected list is refetched.
    if (target == null) {
      await _fetch(1);
    } else {
      await _loadReplies(target);
      if (mounted) setState(() => _expanded.add(target.commentId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: CLListSkeleton(count: 3, avatarSize: 34),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            child: Center(
              child: Text(
                "No comments yet. Be the first.",
                style: TextStyle(fontSize: CLType.body, color: p.text3),
              ),
            ),
          )
        else
          ..._comments.map((comment) => _CommentTile(
                comment: comment,
                busy: _reactionBusy.contains(comment.commentId),
                expanded: _expanded.contains(comment.commentId),
                repliesLoading: _repliesLoading.contains(comment.commentId),
                replies: _replies[comment.commentId] ?? const [],
                replyBusy: _reactionBusy,
                onReact: () => _react(comment, isReply: false),
                onReactToReply: (reply) => _react(reply, isReply: true),
                onToggleReplies: () => _toggleReplies(comment),
                onReply: () => widget.replyTarget?.value = comment,
              )),
        if (_isLoadingMore) const CLLoadMoreIndicator(),
        if (_hasNext && !_isLoadingMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(
              child: TextButton(
                onPressed: loadMore,
                child: Text("Load more comments",
                    style: TextStyle(
                        fontSize: CLType.label,
                        fontWeight: FontWeight.w600,
                        color: p.brand)),
              ),
            ),
          ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final PostComment comment;
  final bool busy;
  final bool expanded;
  final bool repliesLoading;
  final List<PostComment> replies;
  final Set<String> replyBusy;
  final VoidCallback onReact;
  final ValueChanged<PostComment> onReactToReply;
  final VoidCallback onToggleReplies;
  final VoidCallback onReply;

  const _CommentTile({
    required this.comment,
    required this.busy,
    required this.expanded,
    required this.repliesLoading,
    required this.replies,
    required this.replyBusy,
    required this.onReact,
    required this.onReactToReply,
    required this.onToggleReplies,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommentRow(
            comment: comment,
            busy: busy,
            onReact: onReact,
            onReply: onReply,
          ),
          if (comment.replyCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 54, top: 2),
              child: InkWell(
                onTap: onToggleReplies,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    expanded
                        ? "Hide replies"
                        : "View ${comment.replyCount} ${comment.replyCount == 1 ? 'reply' : 'replies'}",
                    style: TextStyle(
                        fontSize: CLType.caption,
                        fontWeight: FontWeight.w600,
                        color: p.brand),
                  ),
                ),
              ),
            ),
          if (expanded) ...[
            if (repliesLoading)
              const Padding(
                padding: EdgeInsets.only(left: 44, top: 4),
                child: CLListRowSkeleton(avatarSize: 28),
              )
            else
              ...replies.map((reply) => Padding(
                    padding: const EdgeInsets.only(left: 44, top: 8),
                    child: CommentRow(
                      comment: reply,
                      busy: replyBusy.contains(reply.commentId),
                      compact: true,
                      onReact: () => onReactToReply(reply),
                      // Replying to a reply is re-parented server-side to the
                      // top-level ancestor, so the affordance stays on the
                      // parent rather than pretending to nest deeper.
                      onReply: null,
                    ),
                  )),
          ],
        ],
      ),
    );
  }
}

/// One comment or reply. Public so a feed row can reuse it for previews.
class CommentRow extends StatelessWidget {
  final PostComment comment;
  final bool busy;
  final bool compact;
  final VoidCallback onReact;
  final VoidCallback? onReply;

  const CommentRow({
    super.key,
    required this.comment,
    required this.busy,
    this.compact = false,
    required this.onReact,
    this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final avatarSize = compact ? 28.0 : 34.0;
    final author = comment.author;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _openAuthor(context, author),
          borderRadius: BorderRadius.circular(CLRadii.pill),
          child: CLAvatar(
            id: author.entityId,
            name: author.displayName,
            src: author.profile,
            size: avatarSize,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The bubble carries name + text, the way a chat comment reads -
              // and keeps the reaction row outside it, where it belongs.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: p.surface2,
                  borderRadius: BorderRadius.circular(CLRadii.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The name opens the profile too - tapping a name and
                    // having nothing happen, when the photo beside it works,
                    // reads as broken.
                    InkWell(
                      onTap: () => _openAuthor(context, author),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              author.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: CLType.caption,
                                fontWeight: FontWeight.w700,
                                color: p.text,
                              ),
                            ),
                          ),
                          if (author.isVerified) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.verified, size: 12, color: p.brand),
                          ],
                        ],
                      ),
                    ),
                    if (comment.text.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(
                          children: linkifySpans(
                            comment.text,
                            TextStyle(
                                fontSize: CLType.bodySm,
                                height: 1.35,
                                color: p.text),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (comment.linkPreview != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: LinkPreviewCard(preview: comment.linkPreview),
                ),
              Padding(
                // Added left padding so actions align nicely under the text bubble
                padding: const EdgeInsets.only(top: 2, left: 12, right: 12),
                child: Row(
                  children: [
                    _CommentAction(
                      label:
                          comment.entityReaction != null ? "Reacted" : "React",
                      active: comment.entityReaction != null,
                      onTap: busy ? null : onReact,
                    ),
                    if (onReply != null) ...[
                      const SizedBox(width: 12),
                      _CommentAction(label: "Reply", onTap: onReply),
                    ],
                    if (comment.reactions.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      ReactionSummary(reactions: comment.reactions),
                    ],
                    const Spacer(),
                    if (comment.createdAt != null)
                      Text(
                        timeSince(comment.createdAt!),
                        style: TextStyle(fontSize: CLType.meta, color: p.text3),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

void _openAuthor(BuildContext context, PostPreviewAuthor author) {
  if (author.handle.isEmpty) return;
  context.push(
      author.isRealm ? '/realm/${author.handle}' : '/user/${author.handle}');
}

class _CommentAction extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _CommentAction({
    required this.label,
    this.active = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            fontSize: CLType.meta,
            fontWeight: FontWeight.w700,
            color: active ? p.brand : p.text3,
          ),
        ),
      ),
    );
  }
}

/// The write box, docked to the bottom of the screen like the conversation
/// screen's message input.
///
/// Its own `surface` bar with a top border, and an `input`-filled field inside:
/// the page is `surface` too, so a field filled with the same colour would have
/// no visible edge at all in light mode.
class CommentComposer extends StatefulWidget {
  final String? replyingToName;
  final VoidCallback onCancelReply;
  final Future<void> Function(String text) onSubmit;

  const CommentComposer({
    super.key,
    this.replyingToName,
    required this.onCancelReply,
    required this.onSubmit,
  });

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    await widget.onSubmit(text);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final replyingTo = widget.replyingToName;

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (replyingTo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Replying to $replyingTo",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: CLType.caption,
                            fontWeight: FontWeight.w600,
                            color: p.brand),
                      ),
                    ),
                    InkWell(
                      onTap: widget.onCancelReply,
                      child: Icon(Icons.close, size: 16, color: p.text3),
                    ),
                  ],
                ),
              ),
            Row(
              // Changed to center so the send button stays vertically aligned with the shorter input box
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Container(
                    // 1. Reduced minHeight from 44 to 36
                    constraints: const BoxConstraints(minHeight: 42),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: p.input,
                      borderRadius: BorderRadius.circular(CLRadii.md),
                      border: Border.all(color: p.border2),
                    ),
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(color: p.text, fontSize: CLType.title),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        // 2. Reduced vertical padding from 12 to 8 to shrink text field height
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        isDense:
                            true, // 3. Added to collapse unnecessary internal Material padding
                        hintText: replyingTo == null
                            ? "Write a comment…"
                            : "Write a reply…",
                        hintStyle: TextStyle(color: p.text3),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _sending
                    ? const Padding(
                        // 4. Slightly reduced padding to match the shorter input height
                        padding: EdgeInsets.all(7),
                        child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : CLIconBtn(
                        icon: Icons.send,
                        color: p.brand,
                        tooltip: "Post",
                        onPressed: _send,
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
