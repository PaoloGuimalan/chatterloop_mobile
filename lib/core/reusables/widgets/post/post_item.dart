// One post AS A ROW IN A FEED - profile feeds today, the newsfeed next.
//
// The distinction from the two neighbouring widgets is worth stating, because
// all three render "a post":
//
//   SearchContentCard  a search HIT. Author line, clamped caption, two
//                      counters. No reactions, no actions - it exists to be
//                      recognised and tapped, not used.
//   PostItem (here)    the full post as content: author + who they're with,
//                      caption, link preview, attachments, reaction tallies
//                      and the react/comment/share bar. Everything webapp's
//                      PostItem shows above its inline comments.
//   PostPreviewScreen  the pushed screen - the same post plus its comment
//                      thread and the docked composer.
//
// It renders [PostCard] inside feed chrome rather than duplicating it. Forking
// the two would mean every future change to a post's body - a new attachment
// kind, a badge, an options menu - has to be made twice and will eventually be
// made once. What PostItem adds is what a FEED needs and a screen doesn't: a
// bounded card surface, separation from its neighbours, and the whole thing
// being a tap target that opens the post.

import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_card.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_composer.dart';
import 'package:chatterloop_app/core/utils/view_cache.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:visibility_detector/visibility_detector.dart';

class PostItem extends StatelessWidget {
  final PostPreview post;

  /// Reports the post back after a local change (a reaction), so the feed can
  /// keep its own list entry in step without refetching the page.
  final ValueChanged<PostPreview>? onChanged;

  /// Defaults to pushing the post screen. Overridable so a feed can intercept
  /// - e.g. to pass a warm copy through instead of refetching.
  final VoidCallback? onOpen;

  /// The feed drops this row - the post is gone server-side.
  final VoidCallback? onDeleted;

  /// Whether YOUR OWN posts get view-tracked in this feed. See
  /// [PostViewTracker] for why the answer differs by surface.
  final bool trackOwnPosts;

  const PostItem({
    super.key,
    required this.post,
    this.onChanged,
    this.onOpen,
    this.onDeleted,
    this.trackOwnPosts = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    void open() {
      if (onOpen != null) return onOpen!();
      context.push('/post/${post.postId}');
    }

    return PostViewTracker(
      post: post,
      trackOwnPosts: trackOwnPosts,
      // A post is a floating panel of its own - the feed is a stack of cards
      // on the canvas, not one list with rules between the rows.
      child: Container(
        margin: const EdgeInsets.only(bottom: CLSpacing.canvasGutter),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(CLRadii.panel),
          boxShadow: p.panelShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: PostCard(
          post: post,
          onChanged: onChanged,
          // onOpen marks this as a FEED row rather than the post's own screen -
          // that's what clamps the caption. It is no longer a body tap target:
          // onComment is the only way into the post from here, so tapping a
          // video in a row plays it instead of navigating off it.
          onOpen: open,
          onComment: open,
          onDeleted: onDeleted,
        ),
      ),
    );
  }
}

/// Times how long a post row is actually on screen and files it in
/// [ViewCache], which the next feed request drains. See view_cache.dart for
/// why this is load-bearing rather than analytics.
///
/// Wraps the ROW, not [PostCard], so it covers exactly the feeds - the
/// newsfeed and both profile feeds - and never double-counts a post you're
/// reading on its own screen. Webapp puts it on PostItem for the same reason.
class PostViewTracker extends StatefulWidget {
  final PostPreview post;
  final Widget child;

  /// Whether to track posts you wrote yourself. False on profile feeds, true
  /// in the newsfeed - and the asymmetry is the point:
  ///
  /// A view does two separate things server-side. It writes an engagement
  /// log, which the server refuses for your own posts (`if str(poid) !=
  /// str(entity.id)`), and it deletes the post from your NewsfeedIndex
  /// bucket - which it does UNCONDITIONALLY, self-authored or not. That
  /// deletion is the only thing that ever drains the bucket.
  ///
  /// So skipping your own posts in the newsfeed doesn't avoid a pointless
  /// record, it strands one: your own post is fanned into your own bucket,
  /// never reports a view, and sits at the top of your feed permanently. The
  /// engagement log is still skipped - by the server, which is where that
  /// rule belongs.
  ///
  /// On a profile there's no bucket to drain, so the only thing a self-view
  /// could produce is the log the server would throw away. Hence off - which
  /// is also what webapp does everywhere, including its newsfeed, where it
  /// has this same stranded-post problem.
  final bool trackOwnPosts;

  const PostViewTracker({
    super.key,
    required this.post,
    required this.child,
    this.trackOwnPosts = false,
  });

  /// How much of the row has to be showing to count as being read. Matches
  /// webapp's `useInView(ref, { amount: 0.6 })` - a sliver of a card passing
  /// the edge of the viewport is not a view.
  static const double visibleThreshold = 0.6;

  /// Credited the moment a post comes into view, before any dwell time
  /// accrues, so a fast scroll still registers as "seen" and drains the row
  /// from the feed bucket. Webapp seeds the same 0.5.
  static const double enterCredit = 0.5;

  @override
  State<PostViewTracker> createState() => _PostViewTrackerState();
}

class _PostViewTrackerState extends State<PostViewTracker>
    with WidgetsBindingObserver {
  DateTime? _sessionStart;

  /// Whether the row is on screen, tracked separately from whether a session
  /// is open. They come apart when the app is backgrounded with the row still
  /// visible: the session has to close (see [didChangeAppLifecycleState]) but
  /// the row hasn't gone anywhere, so coming back has to reopen it - and
  /// nothing else will, because visibility never changed.
  bool _visible = false;

  /// Whether this row is tracked at all. Read per-event rather than cached,
  /// since the acting entity can change under a live row.
  bool get _untracked =>
      !widget.trackOwnPosts && isActingEntity(widget.post.author.entityId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    if (_untracked) return;
    _visible = info.visibleFraction >= PostViewTracker.visibleThreshold;
    if (_visible) {
      _openSession(credit: true);
    } else {
      _closeSession();
    }
  }

  /// [credit] gives the 0.5 "it was seen at all" seed. Only on a real first
  /// sighting - resuming from the background is the same view continuing, and
  /// crediting it again would let backgrounding and returning inflate a post's
  /// score for free.
  void _openSession({required bool credit}) {
    if (_sessionStart != null) return;
    final now = DateTime.now();
    _sessionStart = now;
    if (credit) _record(PostViewTracker.enterCredit, now);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_untracked) return;
    if (state == AppLifecycleState.resumed) {
      // Visibility didn't change while we were away, so the detector won't
      // say anything - reopen from what we already know.
      if (_visible) _openSession(credit: false);
      return;
    }
    // Leaving the app doesn't hide the row as far as VisibilityDetector is
    // concerned, so without this the clock keeps running: put the phone down
    // for an hour on an open feed and every visible post banks an hour of
    // "reading time". Closing here also means the flush that runs on the same
    // event sends a complete duration rather than a half-measured one.
    _closeSession();
  }

  /// Banks whatever the open session has accrued.
  void _closeSession() {
    final start = _sessionStart;
    if (start == null) return;
    _sessionStart = null;
    final seconds = DateTime.now().difference(start).inMilliseconds / 1000;
    if (seconds <= 0) return;
    _record(seconds, start);
  }

  void _record(double duration, DateTime at) {
    final viewerEntityId = appStore.state.userAuth.user.entityId;
    if (viewerEntityId.isEmpty) return;
    // Fire-and-forget: a feed row must never wait on a disk write to paint.
    unawaited(ViewCache.instance.record(
      widget.post.postId,
      viewerEntityId: viewerEntityId,
      postOwnerId: widget.post.author.entityId,
      duration: duration,
      createdAt: at.toUtc().toIso8601String(),
    ));
  }

  @override
  void dispose() {
    // A row can leave while still visible - switching tabs, pushing a screen,
    // pulling to refresh - and the dwell time of whatever was on screen at
    // that moment is exactly the dwell time of the posts that held attention
    // longest, so losing it biases every duration downwards.
    //
    // Belt and braces, not the primary mechanism: visibility_detector does
    // report a final zero-visibility callback when a detector is unmounted,
    // and that already closes the session (verified - removing this line
    // does not fail the teardown test below). It stays because it's free and
    // idempotent (_closeSession clears _sessionStart), and because the
    // package's final callback goes through the same scheduling path as any
    // other update, which is not a guarantee worth resting the data on.
    WidgetsBinding.instance.removeObserver(this);
    _closeSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to measure on your own post, and VisibilityDetector isn't free:
    // it keeps a compositing layer and a global scheduler callback per
    // instance. Don't mount one that would no-op.
    if (_untracked) return widget.child;
    return VisibilityDetector(
      key: Key('post-view-${widget.post.postId}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: widget.child,
    );
  }
}

/// Placeholder shaped like a PostItem, for a feed page still loading.
class PostItemSkeleton extends StatelessWidget {
  const PostItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Container(
      margin: const EdgeInsets.only(bottom: CLSpacing.canvasGutter),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(CLRadii.panel),
        boxShadow: p.panelShadow,
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CLSkeleton(
                  width: 38,
                  height: 38,
                  borderRadius: BorderRadius.all(Radius.circular(19))),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CLSkeleton(width: 140, height: 12),
                    SizedBox(height: 7),
                    CLSkeleton(width: 80, height: 10),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          CLSkeleton(width: double.infinity, height: 11),
          SizedBox(height: 7),
          CLSkeleton(width: 220, height: 11),
          SizedBox(height: 14),
          CLSkeleton(
              width: double.infinity,
              height: 150,
              borderRadius: BorderRadius.all(Radius.circular(CLRadii.md))),
        ],
      ),
    );
  }
}
