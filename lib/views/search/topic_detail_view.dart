// A topic's feed - what a Popular Topics row opens.
//
// Reads the paginated topic endpoint rather than filtering a feed already in
// hand: the posts under a topic are not a subset of whatever page the client is
// holding, and only the server knows which of them this viewer may read.
//
// There is deliberately NO follow/following control. Topics are a discovery
// surface, not something with a subscription behind it, so the header carries
// identity only - name, category, participants.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/interests_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/paginated_scroll.dart';
import 'package:chatterloop_app/core/reusables/widgets/popular_topics.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_item.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/models/user_models/popular_topic_model.dart';
import 'package:flutter/material.dart';

class TopicDetailScreen extends StatefulWidget {
  /// The interest's normalized_name - the same string a hashtag normalises to,
  /// which is what the endpoint resolves on.
  final String slug;

  const TopicDetailScreen({super.key, required this.slug});

  @override
  State<TopicDetailScreen> createState() => _TopicDetailScreenState();
}

class _TopicDetailScreenState extends State<TopicDetailScreen>
    with PaginatedScrollMixin<TopicDetailScreen> {
  final _api = InterestsApi();

  final List<PostPreview> _posts = [];
  PopularTopic? _topic;

  int _page = 1;

  /// Bumped by every refresh. A load-more started before a refresh finishes
  /// would otherwise append its page onto the list the refresh just reset -
  /// page 3's rows on top of a fresh page 1, with page 2 missing. Comparing
  /// the generation on return is what discards that result instead.
  int _generation = 0;

  bool _hasNext = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  @override
  bool get canLoadMore => _hasNext && !_isLoadingMore && !_isLoading;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final (page, topic) = await _api.topicPosts(slug: widget.slug, page: 1);
    // A second refresh started while this one was in flight owns the list now.
    if (!mounted || generation != _generation) return;
    setState(() {
      _posts
        ..clear()
        ..addAll(page.results);
      // Kept if a later page somehow omits it - the header should not blank
      // out mid-scroll.
      _topic = topic ?? _topic;
      _hasNext = page.hasNext;
      _page = 1;
      _isLoading = false;
    });
    ensureFilled();
  }

  @override
  Future<void> loadNextPage() async {
    if (!canLoadMore) return;
    setState(() => _isLoadingMore = true);

    final generation = _generation;
    final next = _page + 1;
    final (page, _) = await _api.topicPosts(slug: widget.slug, page: next);
    if (!mounted) return;
    if (generation != _generation) {
      // Refreshed underneath us. The list is page 1 again, so these rows no
      // longer follow anything - drop them and let the scroll re-request.
      setState(() => _isLoadingMore = false);
      return;
    }

    setState(() {
      // Deduplicated by id: two pages fetched either side of a new post
      // arriving overlap by one row otherwise.
      final seen = _posts.map((post) => post.postId).toSet();
      _posts.addAll(page.results.where((post) => !seen.contains(post.postId)));
      _hasNext = page.hasNext;
      _page = next;
      _isLoadingMore = false;
    });
    ensureFilled();
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final topic = _topic;

    return CLScreen(
      backgroundColor: p.bg,
      appBar: AppBar(
        // The slug, with its "#". The redundancy rule that stripped the hash
        // off the row and card names does not reach up here: those sit beside a
        // "#" tile that already carries the mark, and this does not. Written
        // bare, a title would just be a word.
        //
        // The slug rather than the readable name, because it is what the URL
        // and the hashtag both say - so the title matches what was tapped.
        title: Text('#${topic?.slug ?? widget.slug}'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: paginationController,
          // Without this a topic with one post - or none - has nothing to
          // scroll, and a list that cannot scroll cannot be pulled. The empty
          // state is exactly where a refresh is most likely to be tried.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            CLSpacing.contentGutter,
            14,
            CLSpacing.contentGutter,
            24,
          ),
          children: [
            if (topic != null) ...[
              CLTopicHeaderCard(topic: topic),
              const SizedBox(height: 10),
            ],
            if (_isLoading) ...[
              const PostItemSkeleton(),
              const PostItemSkeleton(),
            ] else if (_posts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: CLEmptyState(
                  icon: Icons.tag,
                  iconBg: p.surface2,
                  iconColor: p.text2,
                  iconBorderColor: p.border,
                  title: "Nothing here yet",
                  subtitle: "Posts tagged with this topic will show up here.\n"
                      "Use the hashtag in a post to start it off.",
                ),
              )
            else
              // No separators - PostItem carries its own card margin, and adding
              // spacing here would double it.
              ..._posts.map((post) => PostItem(
                    post: post,
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
