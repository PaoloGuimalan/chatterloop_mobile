// One Contacts section, in full - the "See all" screen. Ported from the detail
// half of webapp's Contacts.tsx, at the mobile layouts from the mockup: the
// three graph sections are row lists, group chats are a 3-column grid of tiles.
//
// Group chats page a different service (Node/Mongo) from the graph sections
// (Django), so the two fetch paths stay separate here exactly as they do on
// the main screen.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/requests/network_api.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/entity_row.dart';
import 'package:chatterloop_app/core/reusables/widgets/group_tile.dart';
import 'package:chatterloop_app/core/reusables/widgets/paginated_scroll.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/models/user_models/network_models.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';
import 'package:chatterloop_app/views/home/tabs/contacts_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

/// The three graph sections plus the group rail, which is the one section that
/// isn't part of the connection/follow graph.
enum ContactsDetailSection { groups, connections, followers, following }

extension ContactsDetailSectionMeta on ContactsDetailSection {
  String get slug => switch (this) {
        ContactsDetailSection.groups => "groups",
        ContactsDetailSection.connections => "connections",
        ContactsDetailSection.followers => "followers",
        ContactsDetailSection.following => "following",
      };

  String get title => switch (this) {
        ContactsDetailSection.groups => "Group chats",
        ContactsDetailSection.connections => "Connections",
        ContactsDetailSection.followers => "Followers",
        ContactsDetailSection.following => "Following",
      };

  /// null for groups - they aren't served by the network endpoints.
  NetworkSection? get networkSection => switch (this) {
        ContactsDetailSection.groups => null,
        ContactsDetailSection.connections => NetworkSection.connections,
        ContactsDetailSection.followers => NetworkSection.followers,
        ContactsDetailSection.following => NetworkSection.following,
      };

  static ContactsDetailSection? fromSlug(String slug) {
    for (final section in ContactsDetailSection.values) {
      if (section.slug == slug) return section;
    }
    return null;
  }
}

const int _kPageSize = 12;

class ContactsDetailScreen extends StatefulWidget {
  final ContactsDetailSection section;

  const ContactsDetailScreen({super.key, required this.section});

  @override
  State<ContactsDetailScreen> createState() => _ContactsDetailScreenState();
}

class _ContactsDetailScreenState extends State<ContactsDetailScreen>
    with PaginatedScrollMixin<ContactsDetailScreen> {
  final List<NetworkEntityResult> _items = [];
  final List<GroupShortcut> _groups = [];

  int _page = 0;
  int? _total;
  bool _hasNext = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  final Set<String> _followBusy = <String>{};

  bool get _isGroups => widget.section == ContactsDetailSection.groups;

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

    final api = NetworkApi();
    int total = 0;
    bool hasNext = false;

    if (_isGroups) {
      final result = await api.groupShortcutsRequest(page: page, range: _kPageSize);
      if (!mounted) return;
      if (page == 1) _groups.clear();
      _groups.addAll(result.items);
      total = result.total;
      hasNext = result.hasNext;
    } else {
      final result = await api.networkSectionRequest(
        widget.section.networkSection!,
        page: page,
        pageSize: _kPageSize,
      );
      if (!mounted) return;
      if (page == 1) _items.clear();
      _items.addAll(result.results);
      total = result.count;
      hasNext = result.hasNext;
    }

    setState(() {
      _page = page;
      _total = total;
      _hasNext = hasNext;
      _isLoading = false;
      _isLoadingMore = false;
    });
    ensureFilled();
  }

  Future<void> _toggleFollow(NetworkEntityResult item) async {
    if (_followBusy.contains(item.entityId)) return;
    final isFollowing = item.followsRightNow;

    void patch(bool next) {
      for (var i = 0; i < _items.length; i++) {
        if (_items[i].entityId == item.entityId) {
          _items[i] = _items[i].copyWithFollow(next);
        }
      }
    }

    setState(() {
      _followBusy.add(item.entityId);
      patch(!isFollowing);
    });

    final ok = await ProfileApi().setEntityFollowRequest(
      entityId: item.entityId,
      follow: !isFollowing,
    );
    if (!mounted) return;
    setState(() {
      _followBusy.remove(item.entityId);
      if (!ok) patch(isFollowing);
    });
  }

  void _openEntity(NetworkEntityResult item) {
    if (item.handle.isEmpty) return;
    context.push(item.isRealm ? '/realm/${item.handle}' : '/user/${item.handle}');
  }

  Widget _row(NetworkEntityResult item, Map<String, PresenceInfo> presence) {
    final section = widget.section.networkSection!;
    final info = item.isRealm ? null : presence[item.entityId];
    final online = info?.online ?? false;
    final label = info == null
        ? null
        : (info.online
            ? "Active now"
            : (info.lastSeen != null ? timeSince(info.lastSeen!) : null));
    final busy = _followBusy.contains(item.entityId);

    final action = switch (section) {
      NetworkSection.connections => CLRowIconAction(
          icon: Icons.forum,
          tooltip: "Message",
          onPressed: item.connectionId == null || item.connectionId!.isEmpty
              ? null
              : () => context.push('/conversation/${item.connectionId}'),
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
      subtitle: networkRowSubtitle(item, section, label),
      profile: item.profile,
      isVerified: item.isVerified,
      isRealm: item.isRealm,
      online: online,
      onOpen: () => _openEntity(item),
      action: action,
    );
  }

  ({IconData icon, String title, String subtitle}) get _emptyState =>
      switch (widget.section) {
        ContactsDetailSection.groups => (
            icon: Icons.groups,
            title: "No group chats yet",
            subtitle: "Group conversations you join show up here."
          ),
        ContactsDetailSection.connections => (
            icon: Icons.group,
            title: "No connections yet",
            subtitle: "People you connect with land here."
          ),
        ContactsDetailSection.followers => (
            icon: Icons.person_add,
            title: "No followers yet",
            subtitle: "When someone follows you, they'll show here."
          ),
        ContactsDetailSection.following => (
            icon: Icons.how_to_reg,
            title: "Not following anyone yet",
            subtitle: "Follow people to see them here."
          ),
      };

  Widget _groupsGrid() {
    return GridView.builder(
      controller: paginationController,
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 14,
        crossAxisSpacing: 8,
        // Badge (54) + gap + two label lines.
        mainAxisExtent: 96,
      ),
      itemCount: _isLoading ? 9 : _groups.length + (_isLoadingMore ? 3 : 0),
      itemBuilder: (context, index) {
        if (_isLoading || index >= _groups.length) {
          return const CLGroupTileSkeleton(fillWidth: true);
        }
        return CLGroupTile(
          group: _groups[index],
          fillWidth: true,
          onOpen: (group) => context.push('/conversation/${group.targetId}'),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final empty = _emptyState;
    final isEmpty = _isGroups ? _groups.isEmpty : _items.isEmpty;

    return CLScreen(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: Text(widget.section.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child:
                Center(child: CLCountPill(count: _isLoading ? null : _total)),
          ),
        ],
      ),
      body: StoreConnector<AppState, Map<String, PresenceInfo>>(
        distinct: true,
        converter: (store) => store.state.presence,
        builder: (context, presence) {
          if (_isGroups) {
            if (!_isLoading && isEmpty) return _emptyView(p, empty);
            return _groupsGrid();
          }
          if (_isLoading) {
            return ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: 8,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, __) => const CLEntityRowSkeleton(),
            );
          }
          if (isEmpty) return _emptyView(p, empty);
          return ListView.separated(
            controller: paginationController,
            padding: const EdgeInsets.all(14),
            itemCount: _items.length + (_isLoadingMore ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) => index >= _items.length
                ? const CLLoadMoreIndicator()
                : _row(_items[index], presence),
          );
        },
      ),
    );
  }

  Widget _emptyView(
      CLPalette p, ({IconData icon, String title, String subtitle}) empty) {
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
}
