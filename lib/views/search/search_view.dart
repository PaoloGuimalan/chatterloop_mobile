// Explore - the redesigned search screen. Ported from webapp's
// src/app/tabs/search/Search.tsx at the mobile sizes in
// "ChatterLoop Mobile.dc.html", then reworked to design 2a.
//
// One overview call settles every section preview per query; each "See all"
// pushes a detail screen that infinite-scrolls its OWN paginated v2 endpoint
// (see search_detail_view.dart). The previous implementation called the flat
// v1/v2 entity search and rendered a single people-and-pages list - that
// endpoint is untouched and still used elsewhere.
//
// WHAT 2a CHANGED, AND WHY
// ------------------------
// The magnifier "start typing" panel is gone, and so is the topics card that
// used to sit above it. Explore IS a search screen, so before you type it
// offers things to search - your recent queries, then the popular topics -
// rather than a placeholder telling you to type. Tapping one of those rows
// FILLS THE FIELD instead of pushing a screen, which is what makes the list
// belong to the search box rather than float above it.
//
// The filter chips moved below the field and appear only once a search has
// RUN: they scope results. Over the idle list they scoped nothing, and the
// Topics chip in particular turned the whole screen into a second, differently
// shaped copy of the list already on it.
//
// SEARCHING IS AN ACT, NOT A SIDE EFFECT OF TYPING
// ------------------------------------------------
// There is no debounce here any more. Typing used to fire the query on its own
// after 450ms, which meant results arrived before anybody asked for them and -
// worse - the search was never "made", so it never reached Recent. The list of
// recent searches was therefore empty for exactly the searches somebody had
// actually run. Now the request goes out when the search is submitted (the
// keyboard's Search key) or when a suggestion is tapped, and those are the same
// two moments that record it. Typing alone changes nothing but the field.

import 'package:chatterloop_app/core/design/rails.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/requests/search_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/search_cards.dart';
import 'package:chatterloop_app/core/utils/recent_searches.dart';
import 'package:chatterloop_app/models/user_models/search_v2_models.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';
import 'package:chatterloop_app/views/search/search_detail_view.dart';
import 'package:chatterloop_app/core/reusables/widgets/confirm_dialog.dart';
import 'package:chatterloop_app/core/reusables/widgets/popular_topics.dart';
import 'package:chatterloop_app/models/user_models/popular_topic_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

/// Client-side section filter - no refetch, the overview already holds every
/// section.
enum _ExploreFilter { all, topics, people, realms, posts }

const _filterDefs = <(_ExploreFilter, String, IconData)>[
  (_ExploreFilter.all, "All", Icons.apps),
  (_ExploreFilter.topics, "Topics", Icons.tag),
  (_ExploreFilter.people, "People", Icons.group),
  (_ExploreFilter.realms, "Realms", Icons.public),
  (_ExploreFilter.posts, "Posts", Icons.article),
];

/// The server's own preview caps are 5 topics / 8 people / 6 realms / 5 posts.
/// People and realms are rails, so their full preview fits regardless of screen
/// width; content is a vertical list, and five full-width cards push everything
/// below them off a phone screen - so it's trimmed here and "See all" covers
/// the rest.
const int _kPostsPreview = 3;

class SearchScreen extends StatefulWidget {
  /// Seeds the field and runs the search on open. Used when Explore is entered
  /// FOR something - tapping a #hashtag in a post or comment - rather than to
  /// start a search from scratch.
  final String initialQuery;

  const SearchScreen({super.key, this.initialQuery = ''});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();

  /// What is in the FIELD - drives the clear button and nothing else.
  String _query = "";

  /// What was actually SEARCHED FOR. This is what decides whether the screen
  /// shows suggestions or results, and what the tag highlight marks against;
  /// keeping it apart from _query is what stops a half-typed word from
  /// replacing the idle list with the previous query's results.
  String _searched = "";

  _ExploreFilter _filter = _ExploreFilter.all;

  SearchOverview? _overview;
  bool _isLoading = false;

  /// Local only - there is no search-history endpoint. See RecentSearches.
  List<String> _recent = const [];

  /// Keyed per entity so acting on one card never freezes the others.
  final Set<String> _followBusy = <String>{};
  final Set<String> _joinBusy = <String>{};

  /// Whose recent searches these are. Read once rather than watched: the shell
  /// rebuilds this screen on an entity switch, and a switch mid-search is not a
  /// case worth carrying state for.
  String get _entityId => appStore.state.userAuth.user.entityId;

  @override
  void initState() {
    super.initState();
    _loadRecent();

    final initial = widget.initialQuery.trim();
    if (initial.isEmpty) return;

    _query = initial;
    _searched = initial;
    _controller.text = initial;
    // Fired after the first frame rather than from initState directly: _load
    // calls setState on completion, and the widget has to be mounted and laid
    // out before that is legal.
    //
    // NOT recorded in Recent: arriving here from a tapped #hashtag is
    // navigation, not a search somebody made.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(initial);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // -------- recent searches --------------------------------------------------

  Future<void> _loadRecent() async {
    final recent = await RecentSearches.read(_entityId);
    if (!mounted) return;
    setState(() => _recent = recent);
  }

  /// Recorded on DELIBERATE searches only - submitting the field, or tapping a
  /// suggestion. Recording every debounce tick would fill the list with the
  /// prefixes of one query ("r", "ri", "rin", "rina") and bury the searches
  /// somebody actually made.
  Future<void> _recordRecent(String query) async {
    final recent = await RecentSearches.record(_entityId, query);
    if (!mounted) return;
    setState(() => _recent = recent);
  }

  Future<void> _removeRecent(String query) async {
    final recent = await RecentSearches.remove(_entityId, query);
    if (!mounted) return;
    setState(() => _recent = recent);
  }

  /// A suggestion row - a recent query or a trending tag - fills the field and
  /// searches, rather than navigating. That is the whole point of 2a: the idle
  /// list belongs to the search box, so using it leaves you on the same screen
  /// with the field now holding what you picked.
  void _useSuggestion(String query) {
    _controller.text = query;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    _search(query);
  }

  /// The one path that runs a search. Recording and requesting happen together
  /// here so they cannot drift apart - which is exactly what the debounce used
  /// to do.
  void _search(String raw) {
    final query = raw.trim();
    if (query.isEmpty) return;
    setState(() {
      _query = query;
      _searched = query;
    });
    _recordRecent(query);
    _load(query);
  }

  /// Typing does NOT search - see the file header. Emptying the field does
  /// return to the idle list, though: a cleared box has nothing to show results
  /// for, and leaving the last query's results under an empty field reads as a
  /// screen that has stopped responding.
  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      if (value.trim().isEmpty) {
        _searched = "";
        _overview = null;
        _isLoading = false;
      }
    });
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
    // A slower earlier request must not overwrite a newer one's results.
    // Compared against what was SEARCHED, not what is in the field: typing on
    // after submitting does not invalidate the search you just ran, and
    // discarding on _query would leave that search spinning forever.
    if (_searched != query) return;
    setState(() {
      _overview = result;
      _isLoading = false;
    });
  }

  void _clearQuery() {
    _controller.clear();
    setState(() {
      _query = "";
      _searched = "";
      _overview = null;
      _isLoading = false;
      // Back to the idle list, which the chips do not scope.
      _filter = _ExploreFilter.all;
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

  /// A topic RESULT opens the topic's own feed, unlike a topic SUGGESTION,
  /// which fills the field. The difference is what the row means in each place: in
  /// the idle list it is a query you might want to run, and in the results it
  /// is the thing you were looking for.
  ///
  /// The endpoint behind that screen lists exactly the posts filed under the
  /// interest, which a text search only approximates - searching "north edsa"
  /// also returns posts that merely say the words.
  void _openTopic(PopularTopic topic) {
    context.push('/topics/${Uri.encodeComponent(topic.slug)}');
  }

  void _openDetail(SearchDetailKind kind) {
    final query = _searched;
    // Topics are the one section whose detail screen is meaningful with no
    // query: it is the popularity ranking itself, which is exactly what "See
    // all" means on the idle list. Every other section needs a query.
    if (query.isEmpty && kind != SearchDetailKind.topics) return;
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
              // Submitting is the deliberate act that both runs the search and
              // earns it a place in Recent - see _search.
              onSubmitted: _search,
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

  /// The idle state: what to search, not a note saying to search.
  ///
  /// Both lists render nothing when they are empty - a first-run account with
  /// no history on a platform with no popular topics gets a bare search field,
  /// which is honest, rather than two empty panels.
  Widget _suggestions(CLPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_recent.isNotEmpty) ...[
          CLOverlineHeader(
            title: "Recent",
            actionLabel: "Clear",
            onAction: () async {
              await RecentSearches.clear(_entityId);
              if (mounted) setState(() => _recent = const []);
            },
          ),
          ..._recent.map((query) => _RecentRow(
                query: query,
                onTap: () => _useSuggestion(query),
                onRemove: () => _removeRecent(query),
              )),
          const SizedBox(height: 22),
        ],
        CLPopularTopics(
          limit: kPopularTopicMax,
          // The rows sit on the page here, not in a card, so the avatar rings
          // have to be the page's colour.
          faceRingColor: p.bg,
          // Fills the field. See _useSuggestion.
          onTopicTap: (topic) => _useSuggestion(topic.slug),
          onSeeAll: () => _openDetail(SearchDetailKind.topics),
        ),
      ],
    );
  }

  Widget _topicsSection(CLPalette p) {
    final topics = _overview?.topics.results ?? const <PopularTopic>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CLSectionHeader(
          title: "Topics",
          actionLabel: topics.isEmpty ? null : "See all",
          onAction:
              topics.isEmpty ? null : () => _openDetail(SearchDetailKind.topics),
        ),
        if (_isLoading)
          CLTopicList(
            topics: const [],
            loading: true,
            skeletonRows: 2,
            faceRingColor: p.bg,
            onTopicTap: _openTopic,
          )
        else if (topics.isEmpty)
          const CLSectionEmpty(
            icon: Icons.tag,
            title: "No topics found",
            subtitle: "Hashtags people post with become topics.",
          )
        else
          CLTopicList(
            topics: topics,
            highlight: _searched,
            faceRingColor: p.bg,
            onTopicTap: _openTopic,
          ),
      ],
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
    final hasResults = _searched.isNotEmpty;

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
            // The chips scope RESULTS, so they exist only when there are
            // results to scope - see the file header.
            if (hasResults) ...[
              const SizedBox(height: 14),
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
            ],
            const SizedBox(height: 22),
            if (!hasResults)
              _suggestions(p)
            else
              ..._resultSections(p, presence),
          ],
        ),
      ),
    );
  }

  /// The sections that are on, in render order, with the gaps between them.
  ///
  /// Built as a list rather than inline `if`s so no section has to know which
  /// of its neighbours are showing - under a single-section filter this is a
  /// list of one, and there is no leading or trailing gap to suppress.
  List<Widget> _resultSections(CLPalette p, Map<String, PresenceInfo> presence) {
    final sections = <Widget>[
      if (_filter == _ExploreFilter.all || _filter == _ExploreFilter.topics)
        _topicsSection(p),
      if (_filter == _ExploreFilter.all || _filter == _ExploreFilter.people)
        _peopleSection(presence),
      if (_filter == _ExploreFilter.all || _filter == _ExploreFilter.realms)
        _realmsSection(),
      if (_filter == _ExploreFilter.all || _filter == _ExploreFilter.posts)
        _contentSection(),
    ];

    return [
      for (var i = 0; i < sections.length; i++) ...[
        if (i > 0) const SizedBox(height: 26),
        sections[i],
      ],
    ];
  }
}

/// One remembered query. A history icon rather than a magnifier, so a recent
/// row is distinguishable from the field above it at a glance, and an × that
/// drops just this one.
class _RecentRow extends StatelessWidget {
  final String query;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _RecentRow({
    required this.query,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Icon(Icons.history, size: 19, color: p.text3),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Text(
                    query,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.text, fontSize: CLType.title),
                  ),
                ),
              ),
              CLIconBtn(
                icon: Icons.close,
                iconSize: 18,
                size: 32,
                tooltip: "Remove",
                color: p.text3,
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
