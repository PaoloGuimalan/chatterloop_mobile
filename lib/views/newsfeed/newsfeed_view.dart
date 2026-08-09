// The newsfeed - the app's first tab.
//
// Deliberately thin: the composer, the row and the paging behaviour all
// already exist because the profile feed needed them first, so this screen is
// mostly an endpoint and a scroll. Anything it invented for itself would be a
// second version of something a profile already does.
//
// It owns its own list rather than reusing ProfileFeed, though, because the
// two differ where it counts: ProfileFeed is a SECTION inside a profile's
// scroll view (its parent drives paging), while this IS the scroll view.

import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/paginated_scroll.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_composer.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_item.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// 20, matching web's `GetFeedRequest(range: 20)` - and it is load-bearing,
/// not a preference.
///
/// The server's `count` mirrors whatever page_size is sent, because page_size
/// caps the CANDIDATE query (fetch_friends_posts / fetch_trending_posts) before
/// visibility filtering runs against it. Ask for 10 candidates and, if those 10
/// all fail the filter, the response is `{count: 10, results: []}` - a page
/// that looks like "the feed is empty" while the next 10 candidates were never
/// asked for. That is exactly what a page's feed did on mobile at 10 while web
/// showed posts at 20.
const int _kPageSize = 20;

/// Bumped when the Home tab is tapped while the newsfeed is already showing.
///
/// A ValueNotifier rather than a callback registry or a redux action: exactly
/// one widget cares, it is either mounted or it isn't, and the value carries no
/// meaning beyond "again" - which is why it is a counter. A bool would coalesce
/// two taps into one, and re-tapping Home is precisely the gesture someone
/// repeats.
final ValueNotifier<int> newsfeedRefreshRequests = ValueNotifier<int>(0);

class NewsfeedView extends StatefulWidget {
  const NewsfeedView({super.key});

  @override
  State<NewsfeedView> createState() => _NewsfeedViewState();
}

class _NewsfeedViewState extends State<NewsfeedView>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final List<PostPreview> _posts = [];

  int _page = 0;
  bool _hasNext = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _fetch(1);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
    newsfeedRefreshRequests.addListener(_onRefreshRequested);
  }

  /// Tapping Home on the feed you are already looking at means "give me
  /// something new" - the same thing the pull-to-refresh gesture means, so it
  /// runs the same code AND drives the same indicator, rather than silently
  /// refetching with no sign anything happened.
  /// Tapping Home while already on Home: refetch page 1, nothing else.
  ///
  /// Identical to what pull-to-refresh does, because it is the same call -
  /// _fetch(1) sets _isLoading, which puts the skeletons on screen. Earlier
  /// versions of this also animated the scroll and drove the RefreshIndicator's
  /// spinner through a GlobalKey; both were unnecessary and both failed
  /// silently, which is why this is now one line.
  void _onRefreshRequested() {
    if (!mounted) return;
    _fetch(1);
  }

  @override
  void dispose() {
    newsfeedRefreshRequests.removeListener(_onRefreshRequested);
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Views are banked locally the moment a row is seen, but the only thing that
  /// carries them to the server is a feed request - and this screen makes one
  /// per launch unless the user pages or refreshes. A feed with one post has
  /// neither, so without a flush of its own nothing you looked at this session
  /// is ever recorded, and the server keeps serving the same row back because
  /// its NewsfeedIndex entry is only deleted when a view arrives.
  ///
  /// Both triggers below are moments the user has stopped reading, so the
  /// durations sent are complete rather than half-measured.
  void _flushPendingViews() {
    unawaited(() async {
      // Let the rows close their open sessions first. They react to the same
      // two moments this does, and whichever observer is registered first
      // wins - snapshotting ahead of them would send the 0.5 entry credit and
      // leave the actual dwell behind, filing two engagement logs for one read.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await NewsfeedApi().flushPendingViewsRequest();
    }());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app. Best-effort - if the process dies before the request
    // lands the entries are still on disk and go out on the next launch's
    // first fetch, which is the case this can't improve on.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _flushPendingViews();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      if (_hasNext && !_isLoadingMore && !_isLoading) _fetch(_page + 1);
    }
  }

  /// How many all-duplicate pages in a row to walk past before giving up.
  /// See [_fetch].
  static const _maxDuplicatePageSkips = 3;

  Future<void> _fetch(int page, {int skips = 0}) async {
    if (page == 1) {
      setState(() => _isLoading = true);
    } else {
      if (_isLoadingMore || !_hasNext) return;
      setState(() => _isLoadingMore = true);
    }

    if (kDebugMode) {
      print("[newsfeed-view] fetch page=$page "
          "entity=${appStore.state.userAuth.user.entityId}");
    }
    final result = await NewsfeedApi().getNewsfeedRequest(
      page: page,
      pageSize: _kPageSize,
    );
    if (!mounted) return;

    int added = 0;
    setState(() {
      if (page == 1) _posts.clear();
      // Ranked feed: a post that was #10 on page 1 can be #11 by the time
      // page 2 is fetched, so the same post legitimately arrives twice.
      added = appendDistinctPosts(_posts, result.results);
      _page = page;
      _hasNext = result.hasNext;
      _isLoading = false;
      _isLoadingMore = false;
    });

    // A page that dedupes away entirely adds no height, so the scroll
    // position that asked for it is still at the bottom and _onScroll never
    // fires again - the feed just stops, short of the end. Pull the next page
    // inline instead. Bounded so a server stuck returning one page can't spin.
    if (added == 0 &&
        result.results.isNotEmpty &&
        _hasNext &&
        skips < _maxDuplicatePageSkips) {
      return _fetch(page + 1, skips: skips + 1);
    }
  }

  Future<void> _refresh() => _fetch(1);

  /// The acting entity this feed's contents belong to.
  ///
  /// A page has its OWN feed - its own NewsfeedIndex bucket, its own follows,
  /// its own trending pool - and the server resolves all of that from the
  /// token's acting entity. But this screen lives in a shell branch whose
  /// initState runs once per launch, and HomeTabScaffold's switch handling
  /// re-inits messages, contacts, notifications and presence WITHOUT touching
  /// the feed. So after switching, the feed kept asking nothing and showing
  /// whatever the previous identity had - empty, if the switch happened before
  /// the first load.
  String? _lastEntityId;

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    return StoreConnector<AppState, String>(
      distinct: true,
      converter: (store) => store.state.userAuth.user.entityId,
      builder: (context, entityId) {
        if (_lastEntityId != null && _lastEntityId != entityId) {
          // After the frame: this runs during build, and _fetch calls
          // setState.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _fetch(1);
          });
        }
        _lastEntityId = entityId;
        return _feed(p);
      },
    );
  }

  Widget _feed(CLPalette p) {
    return VisibilityDetector(
      // The other flush trigger: switching tabs, or pushing any screen over
      // the feed. An IndexedStack branch that isn't selected doesn't paint,
      // so this reports hidden for a tab switch just as it does for a push.
      key: const Key('newsfeed-screen'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction == 0) _flushPendingViews();
      },
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            CLSpacing.contentGutter,
            12,
            CLSpacing.contentGutter,
            24,
          ),
          children: [
            // The same composer the profiles use. No autoTag: this is your own
            // feed, not someone's profile, so there is nobody to tag by default.
            ProfileComposerCard.forActingEntity(
              placeholder: "Share your thoughts…",
              onPosted: _refresh,
            ),
            if (_isLoading) ...[
              const PostItemSkeleton(),
              const PostItemSkeleton(),
            ] else if (_posts.isEmpty)
              Padding(
                // Enough height that the empty state sits in the body of the
                // screen rather than clinging to the composer above it.
                padding: const EdgeInsets.only(top: 48),
                child: CLEmptyState(
                  icon: Icons.dynamic_feed_outlined,
                  iconBg: p.surface2,
                  iconColor: p.text2,
                  iconBorderColor: p.border,
                  title: "Your feed is quiet",
                  // One sentence per line. CLEmptyState's subtitle sets no
                  // maxLines, so the breaks render rather than being collapsed
                  // or clipped.
                  subtitle:
                      "Posts from people and pages you follow show up here.\n"
                      "Follow a few, or share something yourself to get started.",
                ),
              )
            else
              // No separators or padding of their own - PostItem already carries
              // its own card margin, and adding spacing here would double it and
              // leave a dead band between every row.
              ..._posts.map((post) => PostItem(
                    post: post,
                    // Including your own. Their NewsfeedIndex rows are drained
                    // by a view arriving like anyone else's, and nothing else
                    // drains them - skip them and your own post is pinned to
                    // the top of your feed forever.
                    trackOwnPosts: true,
                    onChanged: (updated) => setState(() {
                      for (var i = 0; i < _posts.length; i++) {
                        if (_posts[i].postId == updated.postId) {
                          _posts[i] = updated;
                        }
                      }
                    }),
                    onDeleted: () => setState(() => _posts
                        .removeWhere((entry) => entry.postId == post.postId)),
                  )),
            if (_isLoadingMore) const CLLoadMoreIndicator(),
          ],
        ),
      ),
    );
  }
}
