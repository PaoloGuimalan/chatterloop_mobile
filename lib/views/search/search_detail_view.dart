// One Explore section, in full - the "See all" screen. Ported from the detail
// half of webapp's Search.tsx, at the mobile layouts from the mockup: People
// becomes ROWS here (the 150px cards belong to the rail, not a full-width
// list), Realms becomes full-width cards, Content keeps its cards.
//
// Pushed above the tab shell, so it gets its own header with a back button and
// the total-count pill - the count comes from the paginated endpoint's own
// `count`, which the overview call deliberately never computes.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/requests/search_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/entity_row.dart';
import 'package:chatterloop_app/core/reusables/widgets/paginated_scroll.dart';
import 'package:chatterloop_app/core/reusables/widgets/search_cards.dart';
import 'package:chatterloop_app/models/user_models/search_v2_models.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

enum SearchDetailKind { people, realms, posts }

extension SearchDetailKindMeta on SearchDetailKind {
  /// Route segment. "posts" is the endpoint's name; the section is titled
  /// "Content" in the UI, matching web.
  String get slug => switch (this) {
        SearchDetailKind.people => "people",
        SearchDetailKind.realms => "realms",
        SearchDetailKind.posts => "posts",
      };

  String get title => switch (this) {
        SearchDetailKind.people => "People",
        SearchDetailKind.realms => "Realms",
        SearchDetailKind.posts => "Content",
      };

  static SearchDetailKind? fromSlug(String slug) {
    for (final kind in SearchDetailKind.values) {
      if (kind.slug == slug) return kind;
    }
    return null;
  }
}

const int _kPageSize = 12;

class SearchDetailScreen extends StatefulWidget {
  final SearchDetailKind kind;
  final String query;

  const SearchDetailScreen({
    super.key,
    required this.kind,
    required this.query,
  });

  @override
  State<SearchDetailScreen> createState() => _SearchDetailScreenState();
}

class _SearchDetailScreenState extends State<SearchDetailScreen>
    with PaginatedScrollMixin<SearchDetailScreen> {
  final List<SearchPersonResult> _people = [];
  final List<SearchRealmResult> _realms = [];
  final List<SearchPostResult> _posts = [];

  int _page = 0;
  int? _total;
  bool _hasNext = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  final Set<String> _followBusy = <String>{};
  final Set<String> _joinBusy = <String>{};

  @override
  bool get canLoadMore => _hasNext && !_isLoading && !_isLoadingMore;

  @override
  void initState() {
    super.initState();
    _fetch(1);
  }

  @override
  void loadNextPage() => _fetch(_page + 1);

  Future<void> _fetch(int page) async {
    if (page == 1) {
      setState(() => _isLoading = true);
    } else {
      if (_isLoadingMore) return;
      setState(() => _isLoadingMore = true);
    }

    final api = SearchApi();
    int count = 0;
    bool hasNext = false;

    switch (widget.kind) {
      case SearchDetailKind.people:
        final result = await api.searchPeopleV2Request(widget.query,
            page: page, pageSize: _kPageSize);
        if (!mounted) return;
        if (page == 1) _people.clear();
        _people.addAll(result.results);
        count = result.count;
        hasNext = result.hasNext;
        break;
      case SearchDetailKind.realms:
        final result = await api.searchRealmsV2Request(widget.query,
            page: page, pageSize: _kPageSize);
        if (!mounted) return;
        if (page == 1) _realms.clear();
        _realms.addAll(result.results);
        count = result.count;
        hasNext = result.hasNext;
        break;
      case SearchDetailKind.posts:
        final result = await api.searchPostsV2Request(widget.query,
            page: page, pageSize: _kPageSize);
        if (!mounted) return;
        if (page == 1) _posts.clear();
        _posts.addAll(result.results);
        count = result.count;
        hasNext = result.hasNext;
        break;
    }

    setState(() {
      _page = page;
      _total = count;
      _hasNext = hasNext;
      _isLoading = false;
      _isLoadingMore = false;
    });
    ensureFilled();
  }

  // -------- actions ----------------------------------------------------------

  void _applyFollow(String entityId, bool next) {
    setState(() {
      for (var i = 0; i < _people.length; i++) {
        if (_people[i].entityId == entityId) {
          _people[i] = _people[i].copyWith(isFollowed: next);
        }
      }
      for (var i = 0; i < _realms.length; i++) {
        if (_realms[i].entityId == entityId) {
          _realms[i] = _realms[i].copyWith(isFollower: next);
        }
      }
    });
  }

  Future<void> _toggleFollow(String entityId, bool currentlyFollowing) async {
    if (_followBusy.contains(entityId)) return;
    setState(() => _followBusy.add(entityId));
    _applyFollow(entityId, !currentlyFollowing);

    final ok = await ProfileApi().setEntityFollowRequest(
      entityId: entityId,
      follow: !currentlyFollowing,
    );
    if (!mounted) return;
    setState(() => _followBusy.remove(entityId));
    if (!ok) _applyFollow(entityId, currentlyFollowing);
  }

  Future<void> _joinGroup(SearchRealmResult realm) async {
    if (_joinBusy.contains(realm.entityId)) return;
    setState(() => _joinBusy.add(realm.entityId));
    final conversationId = await SearchApi().joinGroupRealmRequest(realm.id);
    if (!mounted) return;
    setState(() {
      _joinBusy.remove(realm.entityId);
      if (conversationId != null) {
        for (var i = 0; i < _realms.length; i++) {
          if (_realms[i].entityId == realm.entityId) {
            _realms[i] = _realms[i].copyWith(isMember: true);
          }
        }
      }
    });
  }

  void _openPerson(SearchPersonResult person) {
    if (person.handle.isEmpty) return;
    context.push('/user/${person.handle}');
  }

  /// Same per-kind routing as the Explore screen - see _openRealm there.
  void _openRealm(SearchRealmResult realm) {
    switch (realm.realmType) {
      case "page":
        if (realm.handle.isNotEmpty) context.push('/realm/${realm.handle}');
        break;
      case "group":
        if (realm.isMember) context.push('/conversation/${realm.id}');
        break;
      default:
        break;
    }
  }

  // -------- body -------------------------------------------------------------

  ({IconData icon, String title, String subtitle}) get _emptyState =>
      switch (widget.kind) {
        SearchDetailKind.people => (
            icon: Icons.group,
            title: "No people found",
            subtitle: "Try a different name or keyword."
          ),
        SearchDetailKind.realms => (
            icon: Icons.public,
            title: "No realms found",
            subtitle: "Servers, groups and pages show up here."
          ),
        SearchDetailKind.posts => (
            icon: Icons.article,
            title: "No posts found",
            subtitle: "Try a different keyword."
          ),
      };

  int get _itemCount => switch (widget.kind) {
        SearchDetailKind.people => _people.length,
        SearchDetailKind.realms => _realms.length,
        SearchDetailKind.posts => _posts.length,
      };

  Widget _item(int index, Map<String, PresenceInfo> presence) {
    switch (widget.kind) {
      case SearchDetailKind.people:
        final person = _people[index];
        return CLEntityRow(
          entityId: person.entityId,
          displayName: person.displayName,
          subtitle: "${person.mutualCount} mutual",
          profile: person.profile,
          isVerified: person.isVerified,
          online: presence[person.entityId]?.online ?? false,
          onOpen: () => _openPerson(person),
          action: CLMiniBtn(
            label: person.isFollowed ? "Following" : "Follow",
            variant:
                person.isFollowed ? CLBtnVariant.soft : CLBtnVariant.primary,
            onPressed: _followBusy.contains(person.entityId)
                ? null
                : () => _toggleFollow(person.entityId, person.isFollowed),
          ),
        );
      case SearchDetailKind.realms:
        final realm = _realms[index];
        return SearchRealmCard(
          realm: realm,
          wide: true,
          followBusy: _followBusy.contains(realm.entityId),
          joinBusy: _joinBusy.contains(realm.entityId),
          onToggleFollow: (target) =>
              _toggleFollow(target.entityId, target.isFollower),
          onJoinGroup: _joinGroup,
          onOpen: _openRealm,
        );
      case SearchDetailKind.posts:
        final post = _posts[index];
        return SearchContentCard(
          post: post,
          onOpen: (target) => context.push('/post/${target.postId}'),
        );
    }
  }

  Widget _skeleton() => switch (widget.kind) {
        SearchDetailKind.people => const CLEntityRowSkeleton(),
        SearchDetailKind.realms => const SearchRealmCardSkeleton(wide: true),
        SearchDetailKind.posts => const SearchContentCardSkeleton(),
      };

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final empty = _emptyState;

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: Text(widget.kind.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(child: CLCountPill(count: _isLoading ? null : _total)),
          ),
        ],
      ),
      body: StoreConnector<AppState, Map<String, PresenceInfo>>(
        distinct: true,
        converter: (store) => store.state.presence,
        builder: (context, presence) {
          if (_isLoading) {
            return ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: 6,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, __) => _skeleton(),
            );
          }
          if (_itemCount == 0) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: CLEmptyState(
                  icon: empty.icon,
                  iconBg: p.surface2,
                  iconColor: p.text2,
                  iconBorderColor: p.border,
                  title: empty.title,
                  subtitle: empty.subtitle,
                ),
              ),
            );
          }
          return ListView.separated(
            controller: paginationController,
            padding: const EdgeInsets.all(14),
            itemCount: _itemCount + (_isLoadingMore ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) => index >= _itemCount
                ? const CLLoadMoreIndicator()
                : _item(index, presence),
          );
        },
      ),
    );
  }
}
