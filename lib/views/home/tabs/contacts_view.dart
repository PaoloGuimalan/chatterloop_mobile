// Contacts - the redesigned network screen. Ported from webapp's
// src/app/tabs/feed/Contacts.tsx at the mobile layout from
// "ChatterLoop Mobile.dc.html".
//
// Four sections: a rail of group-chat shortcuts plus Connections / Followers /
// Following, each with a preview and its own paginated "See all"
// (contacts_detail_view.dart). Two services feed it and they load
// independently, so a slow query on one never holds up the other: the three
// graph sections come from Django (/api/entity/network/*), ranked by
// interaction score so the people you actually deal with sit on top, while
// group chats come from Node (/m/v2/group-shortcuts) - shortcuts into
// conversations you're really in, newest activity first, NOT a realm directory.
//
// This replaced a flat /api/user/contacts list. That endpoint is untouched and
// still fetched by the tab shell.

import 'package:chatterloop_app/core/design/rails.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/requests/network_api.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/entity_row.dart';
import 'package:chatterloop_app/core/reusables/widgets/group_tile.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/models/user_models/network_models.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';
import 'package:chatterloop_app/views/home/tabs/contacts_detail_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

/// The server previews 6 rows per graph section. Three is what fits on a phone
/// without any one section pushing the others off screen - "See all" covers
/// the rest.
const int _kSectionPreview = 3;

/// Enough tiles that the rail is worth scrolling, without over-fetching for a
/// preview.
const int _kGroupsPreview = 10;

/// Subtitle line + online dot for a row, from the presence state (keyed on
/// ENTITY id, contacts-scoped, kept live by the "active_users" SSE events).
/// Pages are skipped entirely - a page is never "active now".
({bool online, String? label}) _presenceFor(
  NetworkEntityResult item,
  Map<String, PresenceInfo> presence,
) {
  if (item.isRealm) return (online: false, label: null);
  final info = presence[item.entityId];
  if (info == null) return (online: false, label: null);
  if (info.online) return (online: true, label: "Active now");
  return (
    online: false,
    label: info.lastSeen != null ? timeSince(info.lastSeen!) : null
  );
}

/// Connections show mutuals - the metric that makes a person recognisable.
/// Follow rows show the handle instead, since a mutual count isn't what you're
/// scanning for there. Presence is appended when known, so a row reads
/// "214 mutual · Active now".
String networkRowSubtitle(
  NetworkEntityResult item,
  NetworkSection section,
  String? presenceLabel,
) {
  final base = section == NetworkSection.connections
      ? "${item.mutualCount ?? 0} mutual"
      : "@${item.handle}";
  return presenceLabel == null ? base : "$base · $presenceLabel";
}

class ContactsView extends StatefulWidget {
  const ContactsView({super.key});

  @override
  State<ContactsView> createState() => _ContactsViewState();
}

class _ContactsViewState extends State<ContactsView> {
  NetworkOverview? _overview;
  bool _isLoading = true;

  GroupShortcutsPage _groups = GroupShortcutsPage.empty;
  bool _isGroupsLoading = true;

  final Set<String> _followBusy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = NetworkApi();

    setState(() {
      _isLoading = true;
      _isGroupsLoading = true;
    });

    // Each section applies its own result the moment its service answers, so a
    // slow Mongo query never holds up the graph sections (or vice versa). The
    // two are only joined at the end so pull-to-refresh's spinner runs until
    // BOTH have actually landed rather than stopping on the first one.
    final graph = api.networkOverviewRequest().then((result) {
      if (!mounted) return;
      setState(() {
        _overview = result;
        _isLoading = false;
      });
    });

    final groups =
        api.groupShortcutsRequest(page: 1, range: _kGroupsPreview).then((result) {
      if (!mounted) return;
      setState(() {
        _groups = result;
        _isGroupsLoading = false;
      });
    });

    await Future.wait([graph, groups]);
  }

  // -------- follow -----------------------------------------------------------

  /// Optimistic: the button flips immediately and only reverts if the request
  /// fails. Follow back / Unfollow reuse the entity-generic follow endpoint -
  /// there is no network-specific write route.
  Future<void> _toggleFollow(NetworkEntityResult item) async {
    if (_followBusy.contains(item.entityId)) return;
    final isFollowing = item.followsRightNow;

    setState(() {
      _followBusy.add(item.entityId);
      _overview = _overview?.patchFollow(item.entityId, !isFollowing);
    });

    // .ok only: this surface has no pending state yet. Following a private
    // profile here still lands as a REQUEST, so the button will read
    // "Following" until a refetch - see PLAN-mobile-parity.md 1.3.
    final ok = (await ProfileApi().setEntityFollowRequest(
      entityId: item.entityId,
      follow: !isFollowing,
    ))
        .ok;
    if (!mounted) return;
    setState(() {
      _followBusy.remove(item.entityId);
      if (!ok) _overview = _overview?.patchFollow(item.entityId, isFollowing);
    });
  }

  // -------- navigation -------------------------------------------------------

  void _openEntity(NetworkEntityResult item) {
    if (item.handle.isEmpty) return;
    context.push(item.isRealm ? '/realm/${item.handle}' : '/user/${item.handle}');
  }

  void _openConversation(String? conversationId) {
    if (conversationId == null || conversationId.isEmpty) return;
    context.push('/conversation/$conversationId');
  }

  /// A group's conversationID IS its realm id, so this opens the thread.
  void _openGroup(GroupShortcut group) =>
      context.push('/conversation/${group.targetId}');

  void _openDetail(ContactsDetailSection section) =>
      context.push('/contacts/${section.slug}');

  // -------- rows -------------------------------------------------------------

  Widget _row(
    NetworkEntityResult item,
    NetworkSection section,
    Map<String, PresenceInfo> presence,
  ) {
    final status = _presenceFor(item, presence);
    final busy = _followBusy.contains(item.entityId);

    final action = switch (section) {
      NetworkSection.connections => CLRowIconAction(
          icon: Icons.forum,
          tooltip: "Message",
          onPressed: item.connectionId == null
              ? null
              : () => _openConversation(item.connectionId),
        ),
      NetworkSection.followers => CLMiniBtn(
          label: item.isFollowedBack == true ? "Following" : "Follow back",
          variant: item.isFollowedBack == true
              ? CLBtnVariant.soft
              : CLBtnVariant.primary,
          onPressed: busy ? null : () => _toggleFollow(item),
        ),
      NetworkSection.following => CLMiniBtn(
          label: "Unfollow",
          variant: CLBtnVariant.outline,
          onPressed: busy ? null : () => _toggleFollow(item),
        ),
    };

    return CLEntityRow(
      entityId: item.entityId,
      displayName: item.displayName,
      subtitle: networkRowSubtitle(item, section, status.label),
      profile: item.profile,
      isVerified: item.isVerified,
      isRealm: item.isRealm,
      online: status.online,
      onOpen: () => _openEntity(item),
      action: action,
    );
  }

  ({IconData icon, String title, String subtitle}) _emptyFor(
      NetworkSection section) {
    return switch (section) {
      NetworkSection.connections => (
          icon: Icons.group,
          title: "No connections yet",
          subtitle: "People you connect with land here."
        ),
      NetworkSection.followers => (
          icon: Icons.person_add,
          title: "No followers yet",
          subtitle: "When someone follows you, they'll show here."
        ),
      NetworkSection.following => (
          icon: Icons.how_to_reg,
          title: "Not following anyone yet",
          subtitle: "Follow people to see them here."
        ),
    };
  }

  Widget _peopleSection(
    NetworkSection section,
    NetworkOverviewSection? data,
    Map<String, PresenceInfo> presence,
  ) {
    final results = (data?.results ?? const <NetworkEntityResult>[])
        .take(_kSectionPreview)
        .toList();
    final total = data?.total ?? 0;
    final empty = _emptyFor(section);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CLSectionHeader(
          title: section.title,
          actionLabel: total > results.length ? "See all $total" : null,
          onAction: total > results.length
              ? () => _openDetail(ContactsDetailSection.values
                  .firstWhere((value) => value.slug == section.slug))
              : null,
        ),
        if (_isLoading)
          ...List.generate(
            _kSectionPreview,
            (index) => Padding(
              padding: EdgeInsets.only(
                  bottom: index == _kSectionPreview - 1 ? 0 : 10),
              child: const CLEntityRowSkeleton(),
            ),
          )
        else if (results.isEmpty)
          CLSectionEmpty(
            icon: empty.icon,
            title: empty.title,
            subtitle: empty.subtitle,
          )
        else
          ...results.map((item) => Padding(
                padding:
                    EdgeInsets.only(bottom: item == results.last ? 0 : 10),
                child: _row(item, section, presence),
              )),
      ],
    );
  }

  Widget _groupsSection() {
    return CLRailSection(
      title: "Group chats",
      // Tighter than the 12 the card rails use - these tiles are small, so a
      // wide gap between them reads as a hole rather than as separation.
      gap: 8,
      actionLabel: _groups.total > _groups.items.length
          ? "See all ${_groups.total}"
          : null,
      onAction: _groups.total > _groups.items.length
          ? () => _openDetail(ContactsDetailSection.groups)
          : null,
      empty: _isGroupsLoading
          ? null
          : const CLSectionEmpty(
              icon: Icons.groups,
              title: "No group chats yet",
              subtitle: "Group conversations you join show up here.",
            ),
      children: _isGroupsLoading
          ? List.generate(4, (_) => const CLGroupTileSkeleton())
          : _groups.items
              .map((group) => CLGroupTile(group: group, onOpen: _openGroup))
              .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final overview = _overview;

    final chips = <(ContactsDetailSection, IconData, String, int)>[
      (
        ContactsDetailSection.groups,
        Icons.groups,
        "Group chats",
        _groups.total
      ),
      (
        ContactsDetailSection.connections,
        Icons.group,
        "Connections",
        overview?.connections.total ?? 0
      ),
      (
        ContactsDetailSection.followers,
        Icons.person_add,
        "Followers",
        overview?.followers.total ?? 0
      ),
      (
        ContactsDetailSection.following,
        Icons.how_to_reg,
        "Following",
        overview?.following.total ?? 0
      ),
    ];

    // Bare Scaffold with NO SafeArea, deliberately - see the same note in
    // search_view.dart. This is a tab: HomeTabScaffold's header and bottom nav
    // already consume both insets, and insetting again left a dead strip the
    // height of the Android nav buttons above the nav bar.
    return Scaffold(
      backgroundColor: p.bg,
      body: StoreConnector<AppState, Map<String, PresenceInfo>>(
        distinct: true,
        converter: (store) => store.state.presence,
        builder: (context, presence) => RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
            children: [
              CLChipsRail(
                children: chips
                    .map((chip) => CLChip(
                          label: "${chip.$3} · ${chip.$4}",
                          icon: chip.$2,
                          onTap: () => _openDetail(chip.$1),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 24),
              _groupsSection(),
              const SizedBox(height: 26),
              _peopleSection(
                  NetworkSection.connections, overview?.connections, presence),
              const SizedBox(height: 26),
              _peopleSection(
                  NetworkSection.followers, overview?.followers, presence),
              const SizedBox(height: 26),
              _peopleSection(
                  NetworkSection.following, overview?.following, presence),
            ],
          ),
        ),
      ),
    );
  }
}
