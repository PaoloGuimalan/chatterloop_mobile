// The Servers tab - webapp's Servers.tsx, in its mobile layout.
//
// Three pieces, in the order you meet them:
//
//   ServersScreen           the TAB - a welcome and one button. Servers are a
//                           place you go, not a feed you glance at.
//   ServersDirectoryScreen  pushed: Top Servers, search, Create Server.
//   ServerScreen            pushed: the rail plus a server's channels
//                           (server_channels_view.dart).
//
// Pushing the last two is what keeps them clear of the tab's header and bottom
// nav, so the rail owns the full height exactly as web's does.
//
// Web's welcome block (badge, heading, tagline) is deliberately dropped: it is
// desktop furniture, and on a phone it pushed the actual content below the fold.
// The Create Server button it sat under is kept, since that is the one action
// the directory offers.
//
// NOT built: voice channels, which need the media stack - they are listed but
// not enterable, and say so when tapped rather than failing quietly. Creating
// servers and channels IS built, in create_realm_view.dart.

import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/paginated_scroll.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/views/servers/create_realm_view.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const int _kPageSize = 20;

/// The tab itself: a way in, and nothing else.
///
/// Servers are a place you go rather than a feed you glance at, so the tab is a
/// door. Everything else - the directory, the rail, a server's channels - is
/// pushed full-screen from here, which is also what keeps the rail out of the
/// tab chrome's way.
class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    // CLEmptyState, not a hand-rolled block: it owns the icon badge, the
    // screenTitle heading and the body subtitle that every other empty screen
    // in the app uses, so this cannot drift a step larger than the rest.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CLEmptyState(
              icon: Icons.dns_outlined,
              iconBg: p.surface2,
              iconColor: p.text2,
              iconBorderColor: p.border,
              // compact: the same one step down the Explore panel uses, which
              // takes the heading from screenTitle to sectionTitle and the
              // subtitle from body to caption.
              compact: true,
              title: 'Chatterloop Servers',
              subtitle:
                  'Discover something new, explore the Realms of Chatterloop.',
            ),
            const SizedBox(height: 18),
            CLBtn(
              label: 'Open Servers',
              iconR: Icons.arrow_forward,
              variant: CLBtnVariant.gold,
              size: CLBtnSize.md,
              onPressed: () => context.push('/server-browser'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The directory - webapp Default.tsx.
///
/// Rendered as a PANE inside the rail shell (see ServerScreen), so it has no
/// Scaffold or AppBar of its own: the shell owns those, and the rail has to sit
/// beside this rather than under it.
class ServersDirectoryPane extends StatefulWidget {
  /// Called instead of pushing, so the shell can swap its own pane and keep the
  /// rail in place - which is the entire reason the rail is there.
  final void Function(RealmProfile server) onOpenServer;

  /// Fired after a server is CREATED, so the shell can refetch the rail: the
  /// new server has to appear down the side, and only the shell owns that list.
  final VoidCallback? onServersChanged;

  const ServersDirectoryPane(
      {super.key, required this.onOpenServer, this.onServersChanged});

  @override
  State<ServersDirectoryPane> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersDirectoryPane> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final List<RealmProfile> _servers = [];

  /// Servers joined in THIS session - see _join. Merged with the payload's
  /// is_member so a card flips without the list reordering under the finger.
  final Set<String> _joined = {};

  Timer? _searchDebounce;
  int _page = 1;
  int _count = 0;
  bool _hasNext = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _fetch(1);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 300 &&
        _hasNext &&
        !_loadingMore &&
        !_loading) {
      _fetch(_page + 1);
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () => _fetch(1));
  }

  Future<void> _fetch(int page) async {
    if (page == 1) {
      setState(() => _loading = true);
    } else {
      if (_loadingMore || !_hasNext) return;
      setState(() => _loadingMore = true);
    }

    final result = await ProfileApi().getTopRealmsRequest(
      type: 'server',
      page: page,
      pageSize: _kPageSize,
      search: _search.text,
    );
    if (!mounted) return;

    setState(() {
      if (page == 1) _servers.clear();
      // Web de-dupes across pages with a Set of ids, because the directory is
      // ranked and reshuffles between requests.
      final seen = _servers.map((server) => server.id).toSet();
      for (final server in result.results) {
        if (server.id.isEmpty || seen.add(server.id)) _servers.add(server);
      }
      _page = page;
      _count = result.count;
      _hasNext = result.hasNext;
      _loading = false;
      _loadingMore = false;
    });
  }

  /// JOIN only - the card no longer offers to leave, so this no longer has to
  /// branch on membership.
  ///
  /// joinServerRequest, not the group join: a server has no join route, and the
  /// group one silently no-ops on a server. See joinServerRequest.
  Future<void> _join(RealmProfile server) async {
    if (_busyId != null) return;
    setState(() => _busyId = server.id);

    final joined = await ProfileApi().joinServerRequest(server.id);
    if (!mounted) return;
    setState(() {
      _busyId = null;
      // Flip THIS card, rather than re-reading the directory. The list is
      // ranked and reshuffles between requests, so a refetch moved the card you
      // just acted on somewhere else on screen - web keeps its own isJoined
      // flag for the same reason.
      if (joined) _joined.add(server.id);
    });
    // The server is yours now, so it belongs in the rail beside this pane.
    if (joined) widget.onServersChanged?.call();

    if (!joined) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not join. Please try again.')));
    }
  }

  /// Pushes the create form and, if something was created, re-reads both lists:
  /// the directory (a public server belongs in it) and the rail, via the shell.
  Future<void> _create() async {
    final created = await Navigator.of(context).push<CreatedRealmKind>(
      MaterialPageRoute(builder: (_) => const CreateRealmScreen.server()),
    );
    if (created == null || !mounted) return;
    await _fetch(1);
    widget.onServersChanged?.call();
  }

  @override
  Widget build(BuildContext context) => _directory(cl(context));

  Widget _directory(CLPalette p) {
    final searching = _search.text.trim().isNotEmpty;

    return RefreshIndicator(
      onRefresh: () => _fetch(1),
      child: ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            CLSpacing.contentGutter, 14, CLSpacing.contentGutter, 24),
        children: [
          CLField(
            controller: _search,
            placeholder: 'Search something...',
            icon: Icons.search,
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 12),
          CLBtn(
            label: 'Create Server',
            iconL: Icons.add,
            variant: CLBtnVariant.gold,
            size: CLBtnSize.md,
            block: true,
            onPressed: _create,
          ),
          const SizedBox(height: 18),

          // Section header with the result count on the right, as web has it.
          Row(
            children: [
              Expanded(
                child: Text(searching ? 'Results' : 'Top Servers',
                    style: TextStyle(
                        fontSize: CLType.bodySm,
                        fontWeight: FontWeight.w700,
                        color: p.text)),
              ),
              if (!_loading)
                Text('$_count result${_count == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: CLType.meta, color: p.text2)),
            ],
          ),
          const SizedBox(height: 10),

          if (_loading)
            // Card-shaped, in the same grid: a list-row skeleton here promised a
            // layout the loaded state does not have, so the content jumped as
            // it arrived.
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.82,
              ),
              itemCount: 4,
              itemBuilder: (context, index) => const _ServerCardSkeleton(),
            )
          else if (_servers.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: CLEmptyState(
                icon: searching ? Icons.search_off : Icons.dns_outlined,
                iconBg: p.surface2,
                iconColor: p.text2,
                iconBorderColor: p.border,
                // compact: this sits under a heading and a button rather than
                // owning the screen.
                compact: true,
                title: searching ? 'No matches' : 'No servers yet',
                subtitle: searching
                    ? 'No server matching that name turned up.'
                        ' Try a different name.'
                    : 'Public servers show up here as they are created.'
                        ' Create one to get started.',
              ),
            )
          else
            // Two up. Full-width cards read as banners on a phone and only fit
            // one server per screenful; at this size the directory is
            // browsable, which is what a directory is for.
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                // Slightly taller than wide. 0.66 made each card half again as
                // tall as its width, which read as a column rather than a card.
                // Tuned WITH the content below - banner height and description
                // lines - because a Spacer absorbs slack but overflows if the
                // content is taller than the cell.
                childAspectRatio: 0.82,
              ),
              itemCount: _servers.length,
              itemBuilder: (context, index) {
                final server = _servers[index];
                return _ServerCard(
                  server: server,
                  isMember: server.isMember || _joined.contains(server.id),
                  busy: _busyId == server.id,
                  onOpen: () => widget.onOpenServer(server),
                  onJoin: () => _join(server),
                );
              },
            ),

          if (_loadingMore) const CLLoadMoreIndicator(),
        ],
      ),
    );
  }
}

/// A directory card - webapp's PublicServerItem: cover banner, avatar
/// overlapping it, name, member count and Join/Leave.
class _ServerCard extends StatelessWidget {
  final RealmProfile server;

  /// Passed in rather than read off `server`, so a join can flip one card
  /// without refetching the whole ranked list - see _join.
  final bool isMember;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onJoin;

  const _ServerCard({
    required this.server,
    required this.isMember,
    required this.busy,
    required this.onOpen,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    // cleanMediaSrc, not an inline check: the API says "no photo" as null, "",
    // "N/A" or "none" depending on the payload, and any of the strings handed to
    // an image widget renders a broken image where null gives CLAvatar its
    // gradient and the server initials.
    final cover = clCleanMediaSrc(server.coverPhoto);

    return Container(
      // Inset, not edge to edge: with the rail taking 76px a full-bleed card
      // leaves the content squeezed against both edges. This is what makes it
      // read as a card on a phone rather than a full-width band.
      // No margin - the grid spaces these now.
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner. A gradient stands in when there's no cover, keyed off the
            // id so a given server always looks the same - the same trick
            // CLAvatar uses for a missing photo.
            SizedBox(
              height: 44,
              width: double.infinity,
              child: cover != null
                  ? CLNetworkImage(src: cover, fit: BoxFit.cover)
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: clEntityGradient(server.id),
                        ),
                      ),
                    ),
            ),
            // Avatar straddling the banner's bottom edge.
            Transform.translate(
              offset: const Offset(0, -12),
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration:
                      BoxDecoration(color: p.surface, shape: BoxShape.circle),
                  child: CLAvatar(
                      id: server.id,
                      name: server.name,
                      src: clCleanMediaSrc(server.profile),
                      size: 32),
                ),
              ),
            ),
            // Expanded, because the Column below uses a Spacer to push the
            // member row to the bottom of the card - and a Spacer needs a
            // bounded height. In a plain Padding the Column is unbounded, which
            // throws during layout and leaves the whole card blank.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(server.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: CLType.bodySm,
                                  fontWeight: FontWeight.w700,
                                  color: p.text)),
                        ),
                        if (server.isVerified) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.verified, size: 14, color: p.brand),
                        ],
                      ],
                    ),
                    // No description on the small card. Banner + avatar + name
                    // + count + button already fills the cell, and one more
                    // line overflowed it - which is what the render errors
                    // were. The description is on the server itself.
                    const Spacer(),
                    // Stacked, not side by side: at half width the count and the
                    // button fight for the same room and the label truncates.
                    Text(
                      '${clCompactCount(server.membersCount)} member/s',
                      style:
                          TextStyle(fontSize: CLType.caption, color: p.text2),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: CLMiniBtn(
                        // Open, not Leave. A directory is where you go to FIND
                        // servers, so the action on one you are already in is to
                        // go there - offering to leave is answering a question
                        // nobody browsing has asked, one destructive tap away
                        // from Join on the card beside it. Leaving lives inside
                        // the server, in its header menu, where you are by
                        // definition looking at what you would be giving up.
                        label: busy
                            ? '…'
                            : isMember
                                ? 'Open'
                                : 'Join',
                        // Deliberately NOT the same button twice. Two cards side
                        // by side, one joined and one not, were identical gold
                        // blocks you had to READ to tell apart - which is the
                        // one thing a directory should convey at a glance.
                        //
                        // Join is the offer, so it stays filled gold and reads
                        // as the thing to do. Open is quiet: you are already in,
                        // and the whole card opens it anyway. No icons - fill
                        // and border already carry that difference, and at this
                        // card width a glyph only steals room from the label.
                        variant:
                            isMember ? CLBtnVariant.outline : CLBtnVariant.gold,
                        onPressed: busy ? null : (isMember ? onOpen : onJoin),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A card-shaped placeholder, matching _ServerCard so the grid does not reflow
/// when the real thing arrives.
class _ServerCardSkeleton extends StatelessWidget {
  const _ServerCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CLSkeleton(
              width: double.infinity,
              height: 44,
              borderRadius: BorderRadius.zero),
          Transform.translate(
            offset: const Offset(0, -12),
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: CLSkeleton(
                  width: 34,
                  height: 34,
                  borderRadius: BorderRadius.all(Radius.circular(17))),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  CLSkeleton(width: 88, height: 11),
                  SizedBox(height: 6),
                  CLSkeleton(width: double.infinity, height: 9),
                  Spacer(),
                  CLSkeleton(width: 56, height: 9),
                  SizedBox(height: 6),
                  CLSkeleton(width: double.infinity, height: 26),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
