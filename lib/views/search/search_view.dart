// Explore - the redesigned search screen. Ported from webapp's
// src/app/tabs/search/Search.tsx at the mobile sizes in
// "ChatterLoop Mobile.dc.html".
//
// One overview call settles all three section previews per query; each
// "See all" pushes a detail screen that infinite-scrolls its OWN paginated v2
// endpoint (see search_detail_view.dart). The previous implementation called
// the flat v1/v2 entity search and rendered a single people-and-pages list -
// that endpoint is untouched and still used elsewhere.

import 'dart:async';

import 'package:chatterloop_app/core/design/rails.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/requests/search_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/search_cards.dart';
import 'package:chatterloop_app/models/user_models/search_v2_models.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';
import 'package:chatterloop_app/views/search/search_detail_view.dart';
import 'package:chatterloop_app/core/reusables/widgets/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

/// Client-side section filter - no refetch, the overview already holds all
/// three sections.
enum _ExploreFilter { all, people, realms, posts }

const _filterDefs = <(_ExploreFilter, String, IconData)>[
  (_ExploreFilter.all, "All", Icons.apps),
  (_ExploreFilter.people, "People", Icons.group),
  (_ExploreFilter.realms, "Realms", Icons.public),
  (_ExploreFilter.posts, "Posts", Icons.article),
];

/// The server's own preview caps are 8 people / 6 realms / 5 posts. People and
/// realms are rails, so their full preview fits regardless of screen width;
/// content is a vertical list, and five full-width cards push everything below
/// them off a phone screen - so it's trimmed here and "See all" covers the
/// rest.
const int _kPostsPreview = 3;

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  String _query = "";
  _ExploreFilter _filter = _ExploreFilter.all;

  SearchOverview? _overview;
  bool _isLoading = false;

  /// Keyed per entity so acting on one card never freezes the others.
  final Set<String> _followBusy = <String>{};
  final Set<String> _joinBusy = <String>{};

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    // Same 450ms as web - long enough that typing a handle doesn't fire a
    // request per keystroke.
    _debounce = Timer(const Duration(milliseconds: 450), () => _load(value));
    setState(() => _query = value);
  }

  Future<void> _load(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) {
      if (!mounted) return;
      setState(() {
        _overview = null;
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);
    final result = await SearchApi().searchOverviewV2Request(query);
    if (!mounted) return;
    // A slower earlier request must not overwrite a newer query's results.
    if (_query.trim() != query) return;
    setState(() {
      _overview = result;
      _isLoading = false;
    });
  }

  void _clearQuery() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _query = "";
      _overview = null;
      _isLoading = false;
    });
  }

  // -------- follow / join ----------------------------------------------------

  /// A follow flip has to land in BOTH overview sections - the same entity can
  /// be a person hit and (as a page) a realm hit.
  /// People carry TWO flags because a follow can land pending; realms only
  /// ever have one, since a realm is never private.
  void _applyFollow(String entityId,
      {required bool followed, required bool pending}) {
    final overview = _overview;
    if (overview == null) return;
    setState(() {
      _overview = overview.copyWith(
        people: SearchOverviewSection(
          hasMore: overview.people.hasMore,
          results: overview.people.results
              .map((person) => person.entityId == entityId
                  ? person.copyWith(
                      isFollowed: followed, isFollowPending: pending)
                  : person)
              .toList(),
        ),
        realms: SearchOverviewSection(
          hasMore: overview.realms.hasMore,
          results: overview.realms.results
              .map((realm) => realm.entityId == entityId
                  ? realm.copyWith(isFollower: followed)
                  : realm)
              .toList(),
        ),
      );
    });
  }

  /// Optimistic: the button flips immediately and only reverts if the request
  /// fails. The follow endpoint is entity-generic, so one path covers people
  /// and pages alike.
  ///
  /// Pending counts as "on" - cancelling a follow request is the same DELETE
  /// as unfollowing, since it drops the row whatever its status. Following a
  /// PRIVATE profile does not take effect immediately, so the optimistic
  /// "Following" is corrected to "Requested" from the response. Reverting
  /// restores BOTH flags; assuming `!current` would lose the pending state.
  Future<void> _toggleFollow(String entityId, bool currentlyFollowing,
      {bool currentlyPending = false,
      String name = '',
      bool isRealm = false,
      String realmNoun = 'page'}) async {
    if (_followBusy.contains(entityId)) return;

    // Dropping a follow (or withdrawing a pending request) confirms first -
    // the name has to come from the card, since this only ever had the id.
    if (currentlyFollowing || currentlyPending) {
      final confirmed = await confirmUnfollow(
        context,
        name: name,
        isRealm: isRealm,
        isPending: currentlyPending,
        realmNoun: realmNoun,
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _followBusy.add(entityId));

    final isActive = currentlyFollowing || currentlyPending;
    _applyFollow(entityId, followed: !isActive, pending: false);

    final result = await ProfileApi().setEntityFollowRequest(
      entityId: entityId,
      follow: !isActive,
    );
    if (!mounted) return;
    setState(() => _followBusy.remove(entityId));

    if (!result.ok) {
      _applyFollow(entityId,
          followed: currentlyFollowing, pending: currentlyPending);
    } else if (!isActive && result.isPending) {
      _applyFollow(entityId, followed: false, pending: true);
    }
  }

  void _applyMember(String entityId, bool next) {
    final overview = _overview;
    if (overview == null) return;
    setState(() {
      _overview = overview.copyWith(
        realms: SearchOverviewSection(
          hasMore: overview.realms.hasMore,
          results: overview.realms.results
              .map((realm) => realm.entityId == entityId
                  ? realm.copyWith(isMember: next)
                  : realm)
              .toList(),
        ),
      );
    });
  }

  /// One-click join, PUBLIC groups only (the server enforces that too).
  /// Per the design, joining does NOT navigate - the card flips to "Open chat"
  /// and THAT opens the thread.
  Future<void> _joinGroup(SearchRealmResult realm) async {
    if (_joinBusy.contains(realm.entityId)) return;
    setState(() => _joinBusy.add(realm.entityId));
    final conversationId = await SearchApi().joinGroupRealmRequest(realm.id);
    if (!mounted) return;
    setState(() => _joinBusy.remove(realm.entityId));
    if (conversationId != null) _applyMember(realm.entityId, true);
  }

  // -------- navigation -------------------------------------------------------

  void _openPerson(SearchPersonResult person) {
    if (person.handle.isEmpty) return;
    context.push('/user/${person.handle}');
  }

  /// Destination depends on the realm kind: a page has a profile screen, a
  /// server opens its own shell, and a group IS a conversation (its
  /// conversationID is its realm id) so members go straight to the thread,
  /// while a non-member has no destination at all - Join is the only
  /// affordance.
  void _openRealm(SearchRealmResult realm) => openSearchRealm(context, realm);

  void _openPost(SearchPostResult post) => context.push('/post/${post.postId}');

  void _openDetail(SearchDetailKind kind) {
    final query = _query.trim();
    if (query.isEmpty) return;
    context.push('/search/${kind.slug}?q=${Uri.encodeQueryComponent(query)}');
  }

  // -------- sections ---------------------------------------------------------

  Widget _searchField(CLPalette p) {
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.md),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 3,
              offset: const Offset(0, 1)),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 19, color: p.text3),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (value) {
                _debounce?.cancel();
                _load(value);
              },
              style: TextStyle(color: p.text, fontSize: CLType.title),
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: "Search people, realms, posts…",
                hintStyle: TextStyle(color: p.text3),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            CLIconBtn(
              icon: Icons.close,
              iconSize: 18,
              size: 32,
              tooltip: "Clear",
              color: p.text2,
              onPressed: _clearQuery,
            ),
        ],
      ),
    );
  }

  Widget _initialState(CLPalette p) {
    return Container(
      // Sized to the panel's own contents rather than to a share of the screen:
      // this sits under a search field and a chip row, so a tall block here
      // reads as the point of the screen instead of a placeholder waiting for a
      // query. The mockup's 260 was drawn in a 428px frame.
      constraints: const BoxConstraints(minHeight: 168),
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      alignment: Alignment.center,
      child: CLEmptyState(
        compact: true,
        icon: Icons.manage_search,
        iconBg: p.brandSoft,
        iconColor: p.brand,
        title: "Search people, realms and posts",
        subtitle: "Start typing a name, handle or keyword.",
      ),
    );
  }

  Widget _peopleSection(Map<String, PresenceInfo> presence) {
    final people = _overview?.people.results ?? const <SearchPersonResult>[];
    return CLRailSection(
      title: "People",
      actionLabel: people.isEmpty ? null : "See all",
      onAction:
          people.isEmpty ? null : () => _openDetail(SearchDetailKind.people),
      empty: _isLoading
          ? null
          : const CLSectionEmpty(
              icon: Icons.group,
              title: "No people found",
              subtitle: "Try a different name or keyword.",
            ),
      children: _isLoading
          ? List.generate(3, (_) => const SearchPersonCardSkeleton())
          : people
              .map((person) => SearchPersonCard(
                    person: person,
                    online: presence[person.entityId]?.online ?? false,
                    busy: _followBusy.contains(person.entityId),
                    onToggleFollow: (target) => _toggleFollow(
                        target.entityId, target.isFollowed,
                        currentlyPending: target.isFollowPending,
                        name: '@${target.handle}'),
                    onOpen: _openPerson,
                  ))
              .toList(),
    );
  }

  Widget _realmsSection() {
    final realms = _overview?.realms.results ?? const <SearchRealmResult>[];
    return CLRailSection(
      title: "Realms",
      actionLabel: realms.isEmpty ? null : "See all",
      onAction:
          realms.isEmpty ? null : () => _openDetail(SearchDetailKind.realms),
      empty: _isLoading
          ? null
          : const CLSectionEmpty(
              icon: Icons.public,
              title: "No realms found",
              subtitle: "Servers, groups and pages show up here.",
            ),
      children: _isLoading
          ? List.generate(3, (_) => const SearchRealmCardSkeleton())
          : realms
              .map((realm) => SearchRealmCard(
                    realm: realm,
                    followBusy: _followBusy.contains(realm.entityId),
                    joinBusy: _joinBusy.contains(realm.entityId),
                    onToggleFollow: (target) =>
                        // Realms are never private - no pending state.
                        _toggleFollow(target.entityId, target.isFollower,
                            name: target.displayName,
                            isRealm: true,
                            realmNoun: target.realmType),
                    onJoinGroup: _joinGroup,
                    onOpen: _openRealm,
                  ))
              .toList(),
    );
  }

  Widget _contentSection() {
    final posts = _overview?.posts.results ?? const <SearchPostResult>[];
    final visible = posts.take(_kPostsPreview).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CLSectionHeader(
          title: "Content",
          actionLabel: posts.isEmpty ? null : "See all",
          onAction:
              posts.isEmpty ? null : () => _openDetail(SearchDetailKind.posts),
        ),
        if (_isLoading)
          ...List.generate(
            2,
            (index) => Padding(
              padding: EdgeInsets.only(bottom: index == 1 ? 0 : 10),
              child: const SearchContentCardSkeleton(),
            ),
          )
        else if (visible.isEmpty)
          const CLSectionEmpty(
            icon: Icons.article,
            title: "No posts found",
            subtitle: "Try a different keyword.",
          )
        else
          ...visible.map((post) => Padding(
                padding: EdgeInsets.only(bottom: post == visible.last ? 0 : 10),
                child: SearchContentCard(
                    post: post, onOpen: _openPost, compact: true),
              )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final hasQuery = _query.trim().isNotEmpty;
    final showPeople =
        _filter == _ExploreFilter.all || _filter == _ExploreFilter.people;
    final showRealms =
        _filter == _ExploreFilter.all || _filter == _ExploreFilter.realms;
    final showPosts =
        _filter == _ExploreFilter.all || _filter == _ExploreFilter.posts;

    // Deliberately a bare Scaffold with NO SafeArea - this is a tab, and the
    // shell owns both insets: its header reserves the status bar and its bottom
    // nav reserves the Android nav bar. Wrapping the body in a SafeArea here
    // applied the bottom inset a SECOND time, leaving a dead strip the height
    // of the nav buttons between the content and the nav bar. Pushed screens
    // are the opposite case - they use CLScreen, which does inset the bottom.
    return Scaffold(
      backgroundColor: p.bg,
      body: StoreConnector<AppState, Map<String, PresenceInfo>>(
        distinct: true,
        converter: (store) => store.state.presence,
        builder: (context, presence) => ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          children: [
            _searchField(p),
            const SizedBox(height: 16),
            CLChipsRail(
              children: _filterDefs
                  .map((def) => CLChip(
                        label: def.$2,
                        icon: def.$3,
                        active: _filter == def.$1,
                        onTap: () => setState(() => _filter = def.$1),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 22),
            if (!hasQuery)
              _initialState(p)
            else ...[
              if (showPeople) _peopleSection(presence),
              if (showPeople && (showRealms || showPosts))
                const SizedBox(height: 26),
              if (showRealms) _realmsSection(),
              if (showRealms && showPosts) const SizedBox(height: 26),
              if (showPosts) _contentSection(),
            ],
          ],
        ),
      ),
    );
  }
}
