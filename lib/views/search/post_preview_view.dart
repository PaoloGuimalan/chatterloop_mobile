// The post screen: one post in full, with its reactions, comments and share.
//
// Reached from an Explore content card today, and from the newsfeed once that
// ships - which is why almost nothing lives here. The post itself is [PostCard]
// and the thread is [PostComments]; this screen only fetches the post, hosts
// those two, and keeps its own copy of the post in step with what PostCard
// reports. A feed row will do the same with the same widgets.
//
// The whole screen is one `surface` sheet - white in light mode, the card
// colour in dark. Header, post and comments all sit on it, so there is no seam
// under the AppBar and no floating-card outline around the post. Everything
// that needs to stand out against it (the comment box) uses `input` instead.
//
// The composer is DOCKED to the bottom of the viewport rather than sitting at
// the end of the comment list, matching the conversation screen's input - a
// comment box you have to scroll to find isn't a comment box.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/feed_api.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_card.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_comments.dart';
import 'package:chatterloop_app/models/post_models/newsfeed_models.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/material.dart';

class PostPreviewScreen extends StatefulWidget {
  final String postId;

  const PostPreviewScreen({super.key, required this.postId});

  @override
  State<PostPreviewScreen> createState() => _PostPreviewScreenState();
}

class _PostPreviewScreenState extends State<PostPreviewScreen> {
  final GlobalKey<PostCommentsState> _commentsKey =
      GlobalKey<PostCommentsState>();
  final ScrollController _scrollController = ScrollController();

  /// Shared with [PostComments]: it sets this when Reply is tapped, the docked
  /// composer below reads it.
  final ValueNotifier<PostComment?> _replyTarget =
      ValueNotifier<PostComment?>(null);

  /// Shared with [PostComments] the same way: it fills this from the post's
  /// live stream, the indicator above the docked composer reads it.
  final ValueNotifier<List<CommentTyper>> _typers =
      ValueNotifier<List<CommentTyper>>(const []);

  PostPreview? _post;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _replyTarget.dispose();
    _typers.dispose();
    super.dispose();
  }

  /// The comment list is a plain Column inside this screen's scroll view, so
  /// paging is driven from here rather than by a nested scrollable.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 280) {
      _commentsKey.currentState?.loadMore();
    }
  }

  Future<void> _load() async {
    final result = await FeedApi().getPostPreviewRequest(widget.postId);
    if (!mounted) return;
    setState(() {
      _post = result;
      _isLoading = false;
    });
  }

  /// Re-read the post's reaction tallies after somebody ELSE reacted.
  ///
  /// Only `reactions` is replaced - `entityReaction` is the viewer's own
  /// choice, which somebody else reacting cannot change. A full _load() would
  /// also rebuild the media and caption for a change to one number.
  Future<void> _refreshReactionTotals() async {
    final post = _post;
    if (post == null) return;

    final totals =
        await NewsfeedApi().getPostReactionTotalsRequest(post.postId);
    if (!mounted) return;

    setState(() => _post = _post?.copyWith(reactions: totals));
  }

  Future<void> _refresh() async {
    await Future.wait([
      _load(),
      _commentsKey.currentState?.reload() ?? Future<void>.value(),
    ]);
  }

  void _scrollToComments() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final post = _post;

    return CLScreen(
      backgroundColor: p.surface,
      appBar: AppBar(
        title: const Text("Post"),
        // Matched to the body so the header doesn't read as its own slab.
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        // Android tints a scrolled-under AppBar by default, which would
        // reintroduce exactly the contrast this is avoiding.
        scrolledUnderElevation: 0,
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: p.brand))
          : post == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: CLEmptyState(
                      icon: Icons.article_outlined,
                      iconBg: p.surface2,
                      iconColor: p.text2,
                      iconBorderColor: p.border,
                      title: "Post unavailable",
                      subtitle:
                          "It may have been deleted, or you may not have access to it.",
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          children: [
                            PostCard(
                              post: post,
                              // No onOpen: this IS the post's own screen.
                              onComment: _scrollToComments,
                              onChanged: (updated) =>
                                  setState(() => _post = updated),
                              // Nothing left to show once it's deleted, so the
                              // screen leaves rather than rendering "Post
                              // unavailable" at the user who just deleted it.
                              onDeleted: () {
                                if (Navigator.of(context).canPop()) {
                                  Navigator.of(context).pop();
                                } else {
                                  setState(() => _post = null);
                                }
                              },
                            ),
                            Divider(height: 1, color: p.border),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                            ),
                            PostComments(
                              key: _commentsKey,
                              postId: post.postId,
                              replyTarget: _replyTarget,
                              // This screen IS the post-in-full surface: one
                              // post the reader is sitting on, which is the
                              // case a live comment section is for. A feed row
                              // showing the same widget would leave this off,
                              // so scrolling past posts does not leave a
                              // connection behind for each one.
                              realtime: true,
                              typers: _typers,
                              // The comment section holds the post's stream
                              // (it is the one child mounted on every
                              // full-post surface), so a reaction on the POST
                              // is reported back up to here, where the post
                              // state lives.
                              onPostReaction: _refreshReactionTotals,
                              onCountChanged: (delta) => setState(() {
                                _post = post.copyWith(
                                    commentsCount: post.commentsCount + delta);
                              }),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Sits directly above the composer rather than at the end
                    // of the comment list: the composer is DOCKED to the
                    // viewport, so an indicator at the end of the list would be
                    // off-screen exactly when someone is typing into it.
                    //
                    CommentTypingIndicator(typers: _typers),
                    // Rebuilds only the composer when the reply target changes,
                    // rather than the whole screen.
                    ValueListenableBuilder<PostComment?>(
                      valueListenable: _replyTarget,
                      builder: (context, replyingTo, _) => CommentComposer(
                        replyingToName: replyingTo?.author.displayName,
                        // Pre-fills "@handle" so the person being replied to is
                        // actually notified - null for your own comment, see
                        // replyMentionHandleFor.
                        mentionHandle: replyMentionHandleFor(replyingTo),
                        onCancelReply: () => _replyTarget.value = null,
                        onTyping: () =>
                            _commentsKey.currentState?.broadcastTyping(),
                        onSubmit: (text) async =>
                            _commentsKey.currentState?.submitComment(text),
                      ),
                    ),
                  ],
                ),
    );
  }
}
