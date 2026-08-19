// The saved-posts section of your own profile - webapp's SavesContainer /
// SavedPostItem.
//
// A SECTION, not a screen, and for the same reason ProfileFeed is one: the
// profile is a single scroll view, and a nested scrollable would trap the
// gesture and give the screen two independent scroll positions. The host
// drives paging by calling [SavedPostsFeedState.loadMore] as it nears its own
// bottom - the same contract ProfileFeed offers, so the profile can swap
// between them without changing how it pages.
//
// The rows are NOT feed posts. GET /api/newsfeed/saves returns
// PostSaveSerializer, whose nested post is a PostBasicSerializer - the Post
// row and its author, and nothing else. No attachments, no reaction or
// comment counts. Rendering that through PostItem would produce posts
// claiming zero of everything, so each row shows what it actually has and
// opens /post/<id> for the real thing - the same split webapp's View button
// makes.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/paginated_scroll.dart';
import 'package:chatterloop_app/models/post_models/saved_post_model.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const int _kPageSize = 20;

class SavedPostsFeed extends StatefulWidget {
  const SavedPostsFeed({super.key});

  @override
  State<SavedPostsFeed> createState() => SavedPostsFeedState();
}

class SavedPostsFeedState extends State<SavedPostsFeed> {
  final List<SavedPost> _items = [];

  int _page = 1;
  bool _hasNext = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  /// The row being unsaved, so only its own button shows the pending label.
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _fetch(1);
  }

  /// Called by the host as it nears the bottom of its own scroll.
  void loadMore() {
    if (_isLoading || _isLoadingMore || !_hasNext) return;
    _fetch(_page + 1);
  }

  Future<void> reload() => _fetch(1);

  Future<void> _fetch(int page) async {
    if (page == 1) {
      setState(() => _isLoading = true);
    } else {
      if (_isLoadingMore || !_hasNext) return;
      setState(() => _isLoadingMore = true);
    }

    final result = await NewsfeedApi()
        .getSavedPostsRequest(page: page, pageSize: _kPageSize);
    if (!mounted) return;

    setState(() {
      if (page == 1) _items.clear();
      // Dedupe on the SAVE row id: unsaving something elsewhere while this is
      // being paged shifts every later row up by one, which otherwise repeats
      // whatever sat on the page boundary.
      final seen = _items.map((entry) => entry.id).toSet();
      for (final entry in result.results) {
        if (entry.id.isEmpty || seen.add(entry.id)) _items.add(entry);
      }
      _page = page;
      _hasNext = result.hasNext;
      _isLoading = false;
      _isLoadingMore = false;
    });
  }

  /// Unsaving from here drops the row: this list IS the saved set, so a row
  /// that has left it has nothing to say. Optimistic, and put back on
  /// failure - otherwise it silently returns on the next refresh.
  Future<void> _unsave(SavedPost item) async {
    if (_busyId != null) return;
    setState(() => _busyId = item.id);

    final ok = await NewsfeedApi()
        .setPostSavedRequest(postId: item.postId, saved: false);
    if (!mounted) return;

    setState(() {
      _busyId = null;
      if (ok) _items.removeWhere((entry) => entry.id == item.id);
    });

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't unsave that post.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      // Its own skeleton rather than PostItemSkeleton: these rows are compact
      // bookmarks, not post cards, and a post-shaped placeholder would
      // promise a layout that never arrives.
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: CLSpacing.contentGutter),
        child: Column(children: [
          _SavedPostRowSkeleton(),
          _SavedPostRowSkeleton(),
          _SavedPostRowSkeleton(),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CLSpacing.contentGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_items.isEmpty)
            const CLSectionEmpty(
              icon: Icons.bookmark_border,
              title: "Nothing saved yet",
              subtitle: "Posts you save are kept here, just for you.",
            )
          else
            ..._items.map((item) => _SavedPostRow(
                  item: item,
                  busy: _busyId == item.id,
                  onOpen: item.postId.isEmpty
                      ? null
                      : () => context.push('/post/${item.postId}'),
                  onUnsave: () => _unsave(item),
                )),
          if (_isLoadingMore) const CLLoadMoreIndicator(),
        ],
      ),
    );
  }
}

/// Mirrors [_SavedPostRow]'s geometry exactly - same height, same avatar,
/// same two text lines and button row - so the list doesn't jump when the
/// real rows land.
class _SavedPostRowSkeleton extends StatelessWidget {
  const _SavedPostRowSkeleton();

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: p.surface2,
            borderRadius: BorderRadius.circular(6),
          ),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(CLRadii.md),
        border: Border.all(color: p.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: p.surface2, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(double.infinity, 13),
                const SizedBox(height: 6),
                bar(140, 11),
                const SizedBox(height: 12),
                Row(children: [bar(64, 26), const SizedBox(width: 6), bar(76, 26)]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedPostRow extends StatelessWidget {
  final SavedPost item;
  final bool busy;
  final VoidCallback? onOpen;
  final VoidCallback onUnsave;

  const _SavedPostRow({
    required this.item,
    required this.busy,
    required this.onUnsave,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final meta = [
      if (item.contentTypeLabel.isNotEmpty) item.contentTypeLabel,
      if (item.author.displayName.isNotEmpty) item.author.displayName,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(CLRadii.md),
        border: Border.all(color: p.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CLAvatar(
            id: item.author.handle.isNotEmpty
                ? item.author.handle
                : item.author.entityId,
            name: item.author.displayName,
            src: item.author.profile,
            size: 44,
            // A page reads as a room rather than a person, the same
            // distinction group tiles draw.
            cornerRadius: item.author.isRealm ? 12 : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.text,
                    fontSize: CLType.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: p.text2, fontSize: CLType.caption)),
                ],
                const SizedBox(height: 10),
                Row(children: [
                  CLMiniBtn(
                    label: 'View',
                    variant: CLBtnVariant.soft,
                    onPressed: onOpen,
                  ),
                  const SizedBox(width: 6),
                  CLMiniBtn(
                    label: busy ? 'Unsaving…' : 'Unsave',
                    variant: CLBtnVariant.outline,
                    onPressed: busy ? null : onUnsave,
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
