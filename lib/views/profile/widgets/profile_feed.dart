// The posts under a profile - the same widget for a user and for a realm.
//
// One widget because it's one endpoint: /api/newsfeed/profile/<handle>/
// resolves `handle` as an Account username OR a Realm slug and returns the
// same paginated PostSerializer either way. Splitting this per profile kind
// would be two copies of identical paging over identical rows.
//
// It renders as a SECTION inside the profile's existing scroll view rather
// than owning a scrollable of its own - a nested scrollable inside the
// profile's SingleChildScrollView would trap the gesture and give the screen
// two independent scroll positions. The parent drives paging by calling
// [ProfileFeedState.loadMore] as it nears its own bottom, the same arrangement
// the post screen uses for its comments.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/paginated_scroll.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_item.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/material.dart';

const int _kPageSize = 10;

class ProfileFeed extends StatefulWidget {
  /// Account username or realm slug - the endpoint accepts either.
  final String handle;

  /// Shown above the first post. Omitted for a profile that has none.
  final String title;

  /// What the empty state says when the profile has no posts. Differs by kind
  /// ("hasn't posted yet" vs "no posts on this page yet"), so the caller owns
  /// the wording.
  final String emptyMessage;

  /// Your OWN archived posts instead of the visible ones. Same endpoint and
  /// same rows - the server swaps which set it returns - so the archive
  /// screen is this widget with one flag rather than a second copy of the
  /// paging, dedupe and empty-state handling.
  ///
  /// Only ever true for your own handle: the server returns nobody else's
  /// archive regardless of what is asked for.
  final bool archive;

  const ProfileFeed({
    super.key,
    required this.handle,
    this.title = "Posts",
    required this.emptyMessage,
    this.archive = false,
  });

  @override
  State<ProfileFeed> createState() => ProfileFeedState();
}

class ProfileFeedState extends State<ProfileFeed> {
  final List<PostPreview> _posts = [];

  int _page = 0;
  bool _hasNext = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _fetch(1);
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

    final result = await NewsfeedApi().getProfilePostsRequest(
      handle: widget.handle,
      page: page,
      pageSize: _kPageSize,
      archive: widget.archive,
    );
    if (!mounted) return;

    int added = 0;
    setState(() {
      if (page == 1) _posts.clear();
      added = appendDistinctPosts(_posts, result.results);
      _page = page;
      _hasNext = result.hasNext;
      _isLoading = false;
      _isLoadingMore = false;
    });

    // A page that dedupes away entirely adds no height, so the scroll
    // position that asked for it is still at the bottom and nothing will ask
    // again - infinite scroll just stops, short of the end. Pull the next
    // page inline instead. Bounded so a server stuck returning one page
    // can't spin here.
    if (added == 0 &&
        result.results.isNotEmpty &&
        _hasNext &&
        skips < _maxDuplicatePageSkips) {
      return _fetch(page + 1, skips: skips + 1);
    }
  }

  /// Driven by the profile screen's scroll listener.
  void loadMore() {
    if (_hasNext && !_isLoadingMore && !_isLoading) _fetch(_page + 1);
  }

  /// For the profile's pull-to-refresh.
  Future<void> reload() => _fetch(1);

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: CLSpacing.contentGutter),
        child: Column(children: [PostItemSkeleton(), PostItemSkeleton()]),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CLSpacing.contentGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // An empty title is a host that wants the rows without a
          // heading (the archive screen), not a blank one.
          if (_posts.isNotEmpty && widget.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                widget.title,
                style: TextStyle(
                  fontSize: CLType.sectionTitle,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                  color: p.text,
                ),
              ),
            ),
          if (_posts.isEmpty)
            CLSectionEmpty(
              icon: Icons.article_outlined,
              title: "No posts yet",
              subtitle: widget.emptyMessage,
            )
          else
            ..._posts.map((post) => PostItem(
                  post: post,
                  // Archived posts are visible to nobody but their author, so
                  // the react/comment/share row has no one to act on.
                  showEngagement: !widget.archive,
                  // A reaction inside a row updates that row in place - without
                  // this the tally would snap back on the next rebuild, since
                  // PostCard holds no post state of its own.
                  onChanged: (updated) => setState(() {
                    for (var i = 0; i < _posts.length; i++) {
                      if (_posts[i].postId == updated.postId) {
                        _posts[i] = updated;
                      }
                    }
                  }),
                  // Drop it here rather than refetching the page: a refetch
                  // would renumber every following page's offset mid-scroll.
                  onDeleted: () => setState(() => _posts
                      .removeWhere((entry) => entry.postId == post.postId)),
                )),
          if (_isLoadingMore) const CLLoadMoreIndicator(),
        ],
      ),
    );
  }
}
