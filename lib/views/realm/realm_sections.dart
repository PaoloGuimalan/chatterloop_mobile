// The manage screen's sections that are lists or uploads rather than a form:
// Members, Followers and Media. Split from realm_manage_view.dart only for
// size - the per-kind rules all still live there.

import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/paginated_scroll.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/views/realm/realm_add_members_view.dart';
import 'package:chatterloop_app/views/realm/realm_manage_view.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Whether [person] is the signed-in account.
///
/// Checked on BOTH ids because the two lists key on different ones: a member
/// carries the account id (what remove-user takes), a follower's row is keyed
/// by follow_id with the account id alongside. Either matching means this row
/// is you.
bool isSelf(RealmPerson person) {
  final user = appStore.state.userAuth.user;
  return (person.accountId.isNotEmpty && person.accountId == user.id) ||
      (person.entityId.isNotEmpty && person.entityId == user.entityId);
}

/// Members and Followers. One widget: the two differ only in which endpoint
/// they page and what removing someone means, and forking them would be two
/// copies of the same search box, pager and confirm dialog.
class RealmRosterScreen extends StatefulWidget {
  final RealmProfile realm;

  /// False = followers.
  final bool members;

  /// Whether the remove action is offered at all - see
  /// realmAllowsMemberRemoval. Roles are unaffected: a public channel's
  /// membership is the server's business, but its admins are its own.
  final bool allowRemoval;

  const RealmRosterScreen({
    super.key,
    required this.realm,
    required this.members,
    this.allowRemoval = true,
  });

  @override
  State<RealmRosterScreen> createState() => _RealmRosterScreenState();
}

class _RealmRosterScreenState extends State<RealmRosterScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final List<RealmPerson> _people = [];

  Timer? _searchDebounce;
  int _page = 1;
  bool _hasNext = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _busyId;

  /// Kept locally because a transfer changes MY OWN role here, and every
  /// "may I act on this person" answer below reads it. Without refetching it,
  /// a former owner keeps seeing owner-only actions on the person they just
  /// handed the realm to until the screen is reopened.
  late RealmProfile _realm = widget.realm;

  String get _title => widget.members ? 'Members' : 'Followers';

  /// Only an owner may remove or re-role a fellow admin/owner - the rule both
  /// /realms/remove-user and /s/update-member-realm-role enforce with a 401
  /// (see the NOTE in entity/permissions.py). Followers have no roles, so it
  /// only applies to the members list.
  bool get _viewerIsOwner => _realm.myRole == 'owner';

  bool _canActOn(RealmPerson person) {
    if (!widget.members) return true;
    if (_viewerIsOwner) return true;
    return person.role != 'admin' && person.role != 'owner';
  }

  /// One dialog shape for every confirm on this screen. A null [confirmLabel]
  /// makes it informational - a single dismiss button, for the case where the
  /// action is refused outright and there is nothing to confirm.
  Future<bool> _confirm({
    required String title,
    required String message,
    String? confirmLabel,
  }) async {
    final p = cl(context);
    final answer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surface,
        title: Text(title,
            style: TextStyle(color: p.text, fontSize: CLType.screenTitle)),
        content: Text(message,
            style: TextStyle(color: p.text2, fontSize: CLType.body)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, confirmLabel == null),
              child: Text(confirmLabel == null ? 'Got it' : 'Cancel',
                  style: TextStyle(color: p.text2))),
          if (confirmLabel != null)
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: p.pink),
                child: Text(confirmLabel)),
        ],
      ),
    );
    return answer == true;
  }

  /// After a transfer MY role has changed too, so the realm payload is
  /// refetched alongside the roster.
  Future<void> _refreshRealm() async {
    final fresh =
        await ProfileApi().getRealmProfileRequest(_realm.id, forManage: true);
    if (!mounted || fresh == null) return;
    setState(() => _realm = fresh);
  }

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

  /// Typing re-queries the server, so it waits for a pause rather than firing
  /// a request per keystroke.
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

    final api = ProfileApi();
    final result = widget.members
        ? await api.getRealmMembersRequest(widget.realm.id,
            page: page, search: _search.text)
        : await api.getRealmFollowersRequest(widget.realm.id,
            page: page, search: _search.text);
    if (!mounted) return;

    setState(() {
      if (page == 1) _people.clear();
      // Same de-dupe the feeds use, for the same reason: a roster being added
      // to while you page it can hand you the same row twice.
      final seen = _people.map((person) => person.removalId).toSet();
      for (final person in result.results) {
        if (person.removalId.isEmpty || seen.add(person.removalId)) {
          _people.add(person);
        }
      }
      _page = page;
      _hasNext = result.hasNext;
      _loading = false;
      _loadingMore = false;
    });
  }

  Future<void> _remove(RealmPerson person) async {
    final confirmed = await _confirm(
      title: 'Remove ${person.displayName}?',
      message: widget.members
          ? "They'll lose access to this ${realmKindNoun(_realm)}."
          : "They'll stop following this page, and can follow again "
              "themselves.",
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = person.removalId);
    // The realm id from the ROW, falling back to the screen's - webapp passes
    // member.realm here, not the realm it was opened with.
    final realmId = person.realmId.isNotEmpty ? person.realmId : _realm.id;
    // The members call carries a reason on refusal; the followers one is a
    // plain bool, so 'unknown' stands in for "no message, use the generic".
    final String? failure;
    if (widget.members) {
      final result = await ProfileApi()
          .removeRealmMembersRequest(realmId, [person.removalId]);
      failure = result.ok ? null : (result.message ?? 'unknown');
    } else {
      final ok = await ProfileApi()
          .removeRealmFollowerRequest(_realm.id, person.removalId);
      failure = ok ? null : 'unknown';
    }
    if (!mounted) return;
    setState(() {
      _busyId = null;
      if (failure == null) {
        _people.removeWhere((entry) => entry.removalId == person.removalId);
      }
    });
    if (failure != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(failure == 'unknown'
              ? 'Could not remove them. Please try again.'
              : failure)));
    }
  }

  /// Hand the realm over. Owner-only, and the one action here that changes
  /// what the viewer may do next - hence the realm refetch afterwards.
  Future<void> _transferOwnership(RealmPerson person) async {
    final noun = realmKindNoun(_realm);
    final confirmed = await _confirm(
      title: 'Make ${person.displayName} the owner?',
      message: "They'll get full control of this $noun, including deleting it "
          "and removing admins. You'll stay on as an admin, and only they can "
          "transfer it back.",
      confirmLabel: 'Transfer',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = person.removalId);
    final result = await ProfileApi().transferRealmOwnershipRequest(
      realmId: person.realmId.isNotEmpty ? person.realmId : _realm.id,
      memberId: person.memberId,
    );
    if (!mounted) return;
    setState(() => _busyId = null);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.message ??
            (result.ok
                ? 'Ownership transferred'
                : 'Could not transfer ownership'))));
    if (!result.ok) return;

    // Both halves: the roster so their role reads "owner", and the realm so
    // mine stops reading "owner".
    await Future.wait([_refreshRealm(), _fetch(1)]);
  }

  /// Your own row. Leaving IS removing yourself, so it is the same call - but
  /// the sole owner is refused, and there is nothing to offer them here
  /// beyond the reason, since they are already looking at the list they would
  /// transfer from.
  Future<void> _leaveSelf(RealmPerson person) async {
    final noun = realmKindNoun(_realm);

    if (_viewerIsOwner) {
      await _confirm(
        title: 'You own this $noun',
        message: "A $noun can't be left without an owner. Transfer ownership "
            "to someone in this list first, then you can leave.",
      );
      return;
    }

    final confirmed = await _confirm(
      title: 'Leave $noun?',
      message: "You'll lose access to this $noun, and you'll need to be added "
          "back to return.",
      confirmLabel: 'Leave',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyId = person.removalId);
    final realmId = person.realmId.isNotEmpty ? person.realmId : _realm.id;
    final result = await ProfileApi()
        .removeRealmMembersRequest(realmId, [person.removalId]);
    if (!mounted) return;
    setState(() => _busyId = null);

    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(result.message ?? 'Could not leave. Please try again.')));
      return;
    }
    // Nothing to stay for: this screen is reached through the manage shell,
    // which is admin-only and no longer ours.
    if (mounted) Navigator.of(context).pop();
  }

  /// Promote to admin / demote to member. Webapp offers exactly these two,
  /// toggled on the member's current role.
  Future<void> _setRole(RealmPerson person, String role) async {
    setState(() => _busyId = person.removalId);
    final realmId =
        person.realmId.isNotEmpty ? person.realmId : widget.realm.id;
    final ok = await ProfileApi().updateRealmMemberRoleRequest(
      realmId: realmId,
      memberId: person.memberId,
      role: role,
    );
    if (!mounted) return;
    setState(() => _busyId = null);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not change their role. Please try again.')));
      return;
    }
    // Re-read rather than patching the row: a role change can reorder the
    // list server-side, and the row also carries a member_id the next action
    // depends on.
    _fetch(1);
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final searching = _search.text.trim().isNotEmpty;

    return CLScreen(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: Text(_title),
        actions: [
          // Members only, and not on a public channel or voice room, whose
          // membership follows the parent server (web's `addableMember`).
          if (widget.members && realmAcceptsNewMembers(widget.realm))
            IconButton(
              tooltip: 'Add members',
              icon: const Icon(Icons.person_add_alt),
              onPressed: () async {
                final added = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => RealmAddMembersScreen(
                      realm: widget.realm,
                      // So the picker can mark people who are already in
                      // rather than appearing to not find them.
                      existingEntityIds:
                          _people.map((person) => person.entityId).toSet(),
                      // For a channel or voice room, candidates come from the
                      // parent SERVER's members - you cannot add someone to a
                      // channel who is not in the server that owns it. Null for
                      // anything else, which leaves the global search.
                      parentRealmId: realmAddsFromParent(widget.realm)
                          ? widget.realm.parent
                          : null,
                    ),
                  ),
                );
                if (added == true) _fetch(1);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                CLSpacing.contentGutter, 12, CLSpacing.contentGutter, 8),
            child: CLField(
              controller: _search,
              placeholder:
                  widget.members ? 'Search members' : 'Search followers',
              icon: Icons.search,
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: _loading
                // Row-shaped, in the list's own gutters. A bare CLListSkeleton
                // sits 6px from the screen edge with a 46px avatar, where these
                // rows are bordered cards whose avatar starts at 27 - so the
                // whole list appeared to shift right as it loaded.
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(CLSpacing.contentGutter,
                        4, CLSpacing.contentGutter, 24),
                    children: [
                      for (var i = 0; i < 6; i++) const _RosterRowSkeleton(),
                    ],
                  )
                : _people.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: CLSectionEmpty(
                            icon: widget.members
                                ? Icons.group_outlined
                                : Icons.favorite_outline,
                            title: searching
                                ? 'No matches'
                                : (widget.members
                                    ? 'No members yet'
                                    : 'No followers yet'),
                            subtitle: searching
                                ? 'Nobody here matches that search.'
                                : (widget.members
                                    ? 'Anyone added to this ${realmKindNoun(widget.realm)} shows up here.'
                                    : 'People who follow this page show up here.'),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _fetch(1),
                        child: ListView.builder(
                          controller: _scroll,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(
                              CLSpacing.contentGutter,
                              4,
                              CLSpacing.contentGutter,
                              24),
                          itemCount: _people.length + (_loadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= _people.length) {
                              return const CLLoadMoreIndicator();
                            }
                            final person = _people[index];
                            // Your own row offers exactly one thing: Leave.
                            // Promote/demote, Remove and Transfer all target
                            // someone else by definition.
                            final self = isSelf(person);
                            final actionable = !self && _canActOn(person);
                            return _RosterRow(
                              person: person,
                              busy: _busyId == person.removalId,
                              onRemove: actionable &&
                                      widget.allowRemoval &&
                                      person.removalId.isNotEmpty
                                  ? () => _remove(person)
                                  : null,
                              // Followers have no role to change.
                              onSetRole: widget.members &&
                                      actionable &&
                                      person.memberId.isNotEmpty
                                  ? (role) => _setRole(person, role)
                                  : null,
                              // Owner-exclusive, and pointless on whoever
                              // already owns it.
                              onTransfer: widget.members &&
                                      !self &&
                                      _viewerIsOwner &&
                                      person.role != 'owner' &&
                                      person.memberId.isNotEmpty
                                  ? () => _transferOwnership(person)
                                  : null,
                              // Leaving is the same endpoint as removal, so
                              // it is offered on the same terms.
                              onLeave: widget.members &&
                                      self &&
                                      widget.allowRemoval &&
                                      person.removalId.isNotEmpty
                                  ? () => _leaveSelf(person)
                                  : null,
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

/// A roster row placeholder, shaped like the row itself - the same bordered
/// card, the same 40px avatar, the same two text lines in the same places.
///
/// Every dimension here is copied from the row below rather than approximated,
/// because the only job a skeleton has is to occupy exactly the space its
/// content will.
class _RosterRowSkeleton extends StatelessWidget {
  const _RosterRowSkeleton();

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      child: Row(
        children: const [
          CLSkeleton(
              width: 40,
              height: 40,
              borderRadius: BorderRadius.all(Radius.circular(20))),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CLSkeleton(width: 130, height: 11),
                SizedBox(height: 7),
                CLSkeleton(width: 84, height: 9),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RosterRow extends StatelessWidget {
  final RealmPerson person;
  final bool busy;
  final VoidCallback? onRemove;

  /// Takes "admin" or "member". Null for a follower, and for your own row.
  final void Function(String role)? onSetRole;

  /// Hand the realm to this person. Null unless the viewer owns it.
  final VoidCallback? onTransfer;

  /// Your own row only - the sole action a member has over themselves.
  final VoidCallback? onLeave;

  const _RosterRow({
    required this.person,
    required this.busy,
    this.onRemove,
    this.onSetRole,
    this.onTransfer,
    this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final role = person.role;
    final self = isSelf(person);
    final meta = [
      if (person.handle.isNotEmpty) '@${person.handle}',
      if (role != null && role.isNotEmpty) role,
      if (self) 'You',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      child: Row(
        children: [
          CLAvatar(
              id: person.entityId,
              name: person.displayName,
              src: person.profile,
              size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        person.displayName.isEmpty
                            ? 'Unknown'
                            : person.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: CLType.body,
                            fontWeight: FontWeight.w700,
                            color: p.text),
                      ),
                    ),
                    if (person.isVerified) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.verified, size: 14, color: p.brand),
                    ],
                  ],
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: CLType.caption, color: p.text2),
                  ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
          else if (onRemove != null ||
              onSetRole != null ||
              onTransfer != null ||
              onLeave != null)
            // One menu rather than a row of icons, matching webapp's
            // three-dots options popover - and it keeps promote/demote and
            // remove one deliberate tap apart from each other.
            PopupMenuButton<String>(
              tooltip: 'Options',
              color: p.surface,
              icon: Icon(Icons.more_horiz, size: 18, color: p.text2),
              onSelected: (value) {
                if (value == 'remove') {
                  onRemove?.call();
                } else if (value == 'transfer') {
                  onTransfer?.call();
                } else if (value == 'leave') {
                  onLeave?.call();
                } else {
                  onSetRole?.call(value);
                }
              },
              itemBuilder: (context) => [
                if (onLeave != null)
                  PopupMenuItem(
                    value: 'leave',
                    child: Row(children: [
                      Icon(Icons.logout, size: 18, color: p.pink),
                      const SizedBox(width: 10),
                      Text('Leave',
                          style:
                              TextStyle(color: p.pink, fontSize: CLType.body)),
                    ]),
                  ),
                if (onSetRole != null)
                  PopupMenuItem(
                    // Toggled on their CURRENT role, exactly as web does it:
                    // an admin can only be demoted, anyone else promoted.
                    value: person.isRealmAdmin ? 'member' : 'admin',
                    child: Row(children: [
                      Icon(
                          person.isRealmAdmin
                              ? Icons.arrow_circle_down
                              : Icons.arrow_circle_up,
                          size: 18,
                          color: p.text2),
                      const SizedBox(width: 10),
                      Text(
                          person.isRealmAdmin
                              ? 'Demote to Member'
                              : 'Promote to Admin',
                          style:
                              TextStyle(color: p.text, fontSize: CLType.body)),
                    ]),
                  ),
                if (onTransfer != null)
                  PopupMenuItem(
                    value: 'transfer',
                    child: Row(children: [
                      Icon(Icons.workspace_premium_outlined,
                          size: 18, color: p.text2),
                      const SizedBox(width: 10),
                      Text('Transfer ownership',
                          style:
                              TextStyle(color: p.text, fontSize: CLType.body)),
                    ]),
                  ),
                if (onRemove != null)
                  PopupMenuItem(
                    value: 'remove',
                    child: Row(children: [
                      Icon(Icons.person_remove_outlined,
                          size: 18, color: p.pink),
                      const SizedBox(width: 10),
                      Text('Remove',
                          style:
                              TextStyle(color: p.pink, fontSize: CLType.body)),
                    ]),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Webapp's Media tab - replace the realm's avatar or cover.
///
/// One multipart POST each, unlike a personal account's avatar which goes
/// through the composer and files a feed post: a realm has no feed post to
/// file, so /realms/upload-media does the whole job.
class RealmMediaScreen extends StatefulWidget {
  final RealmProfile realm;
  const RealmMediaScreen({super.key, required this.realm});

  @override
  State<RealmMediaScreen> createState() => _RealmMediaScreenState();
}

class _RealmMediaScreenState extends State<RealmMediaScreen> {
  String? _busy;
  bool _changed = false;

  Future<void> _pickAndUpload(String mediaType) async {
    final picked =
        await FilePicker.pickFiles(type: FileType.image, allowMultiple: false);
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;

    setState(() => _busy = mediaType);
    final ok = await ProfileApi().updateRealmMediaRequest(
      realmId: widget.realm.id,
      // The DERIVED kind, not the raw type - web sends "channel" here for a
      // group with a parent, so a channel's upload was being filed as a
      // group's.
      realmType: realmFormKind(widget.realm),
      mediaType: mediaType,
      filePath: path,
    );
    if (!mounted) return;
    setState(() {
      _busy = null;
      _changed = _changed || ok;
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Updated. It may take a moment to appear everywhere.'
          : 'Could not upload that image. Please try again.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return PopScope(
      canPop: true,
      // Tells the manage screen to re-read, so its header shows the new photo.
      onPopInvokedWithResult: (didPop, _) {},
      child: CLScreen(
        backgroundColor: p.bg,
        appBar: AppBar(
          title: const Text('Media'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
              CLSpacing.contentGutter, 16, CLSpacing.contentGutter, 24),
          children: [
            _MediaTile(
              title: 'Profile picture',
              subtitle: 'Shown beside this ${realmKindNoun(widget.realm)} '
                  'everywhere it appears.',
              preview: widget.realm.profile,
              rounded: true,
              busy: _busy == 'profile',
              onPick: _busy == null ? () => _pickAndUpload('profile') : null,
            ),
            // Pages and servers only - see realmHasCoverPhoto. Nothing else
            // has a surface that renders a banner, so an upload there is a
            // file that goes nowhere.
            if (realmHasCoverPhoto(widget.realm)) ...[
              const SizedBox(height: 12),
              _MediaTile(
                title: 'Cover photo',
                subtitle: 'The banner across the top of its profile.',
                preview: widget.realm.coverPhoto,
                rounded: false,
                busy: _busy == 'cover_photo',
                onPick:
                    _busy == null ? () => _pickAndUpload('cover_photo') : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? preview;
  final bool rounded;
  final bool busy;
  final VoidCallback? onPick;

  const _MediaTile({
    required this.title,
    required this.subtitle,
    required this.preview,
    required this.rounded,
    required this.busy,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final src = preview;
    final hasPreview = src != null && src.isNotEmpty && src != 'N/A';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: CLType.body,
                  fontWeight: FontWeight.w700,
                  color: p.text)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: TextStyle(fontSize: CLType.caption, color: p.text2)),
          const SizedBox(height: 12),
          // Centred: the avatar is a fixed 88 square, and left-aligned in a
          // full-width card it read as though it had drifted. The cover is
          // full-width so this is a no-op for it, but the two tiles are
          // otherwise identical and should stay that way.
          Center(
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(rounded ? CLRadii.pill : CLRadii.sm),
              child: Container(
                height: rounded ? 88 : 120,
                width: rounded ? 88 : double.infinity,
                color: p.surface2,
                child: hasPreview
                    ? CLNetworkImage(src: src, fit: BoxFit.cover)
                    : Icon(Icons.image_outlined, color: p.text3),
              ),
            ),
          ),
          const SizedBox(height: 12),
          CLBtn(
            label: busy ? 'Uploading…' : 'Choose a photo',
            iconL: Icons.photo_library_outlined,
            variant: CLBtnVariant.outline,
            block: true,
            onPressed: busy ? null : onPick,
          ),
        ],
      ),
    );
  }
}
