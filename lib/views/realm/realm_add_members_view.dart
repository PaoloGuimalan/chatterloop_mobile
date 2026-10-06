// Adding members to a realm.
//
// Two deliberate differences from webapp's ContactMember, both product
// decisions rather than porting shortcuts:
//
//  - it searches GLOBALLY, not within your contacts. Web offers "people you
//    may want to add from contacts/server", which means you cannot add anyone
//    you haven't already connected with. Here anyone findable can be added.
//  - it searches ENTITIES, not just people. Membership is entity-based, so a
//    page can be a member of another realm exactly as a person can, and a
//    people-only search would silently make that impossible.
//
// The payload it produces is still web's exactly - see RealmMemberInvite,
// which carries both the account id and the entity id because the endpoint
// reads both.
//
// A group, a server or a page INVITES rather than adds (realmInvitesMembers):
// the people picked get an invite they accept or decline (Django
// community/invites.py), an email address can be invited whether or not
// anyone has signed up with it, and the invites still waiting are listed with
// a way to withdraw them. A channel or voice room still adds directly - it
// takes people already in its server, who said yes once.

import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/invites_api.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/requests/search_api.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:chatterloop_app/models/user_models/realm_invite_model.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/models/user_models/search_result_model.dart';
import 'package:chatterloop_app/views/realm/realm_manage_view.dart';
import 'package:flutter/material.dart';

/// Web's `addableMember`: a PUBLIC channel or voice room takes no manual
/// additions, because membership there follows the parent server.
bool realmAcceptsNewMembers(RealmProfile realm) {
  final kind = realmFormKind(realm);
  final followsParent = kind == 'channel' || kind == 'voice';
  return !(followsParent && !realm.isPrivate);
}

/// Whether picking people for this realm sends them an INVITE rather than
/// adding them - every kind the server takes invites for that the app manages
/// (a conference is managed on the web). Matches the webapp's Members tab.
bool realmInvitesMembers(RealmProfile realm) =>
    const {'group', 'server', 'page'}.contains(realmFormKind(realm));

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// "First Middle Last", skipping the literal "N/A" the API uses for an absent
/// middle name. Matches how web builds `fullName` for this payload - and it
/// works for a realm too, whose normalized shape puts its name in first_name
/// with an empty last_name.
String inviteFullName(SearchResultUser entity) => [
      entity.firstName,
      entity.middleName,
      entity.lastName,
    ].where((part) => part.trim().isNotEmpty && part.trim() != 'N/A').join(' ');

class RealmAddMembersScreen extends StatefulWidget {
  final RealmProfile realm;

  /// Entity ids already in the roster. Shown as "Already a member" rather than
  /// hidden - a search that silently omits someone reads as "not found", which
  /// is a different and more alarming answer.
  final Set<String> existingEntityIds;

  /// The PARENT server's id, for a channel or voice room.
  ///
  /// When set, the source changes: candidates come from that server's member
  /// list instead of a global search, because you can only add someone to a
  /// channel who is already in the server that owns it. Web does the same -
  /// ContactMember takes `parentRealmID` and labels the panel "People you may
  /// want to add from server" rather than from contacts.
  ///
  /// Offering global search here would list people who cannot be added, and the
  /// failure would arrive only after selecting them.
  final String? parentRealmId;

  const RealmAddMembersScreen({
    super.key,
    required this.realm,
    this.existingEntityIds = const {},
    this.parentRealmId,
  });

  @override
  State<RealmAddMembersScreen> createState() => _RealmAddMembersScreenState();
}

class _RealmAddMembersScreenState extends State<RealmAddMembersScreen> {
  final TextEditingController _query = TextEditingController();
  final List<SearchResultUser> _results = [];

  /// Keyed by entity id, so a selection survives the result list changing
  /// underneath it as the query is refined.
  final Map<String, SearchResultUser> _selected = {};

  Timer? _debounce;
  bool _searching = false;
  bool _adding = false;
  bool _searched = false;

  final InvitesApi _invitesApi = InvitesApi();

  /// Invites still waiting for an answer - shown before a search, with a way
  /// to withdraw each.
  List<RealmInvite> _pending = const [];
  String? _withdrawing;
  bool _emailing = false;

  /// What a page invites people to do: follow it, or help run it as a
  /// moderator or an admin. Every other realm has one purpose.
  String _pageChoice = 'moderator';

  bool get _invites => realmInvitesMembers(widget.realm);
  bool get _isPage => widget.realm.type == 'page';

  Map<String, String> get _purpose => !_isPage
      ? const {}
      : _pageChoice == 'follow'
          ? const {'purpose': 'follow'}
          : {'purpose': 'manage', 'role': _pageChoice};

  @override
  void initState() {
    super.initState();
    // Nothing to type for a server-sourced list - show it immediately.
    if (_fromParentServer) _search();
    if (_invites) _loadPending();
  }

  Future<void> _loadPending() async {
    final pending = await _invitesApi.pending(widget.realm.id);
    if (!mounted) return;
    setState(() => _pending = pending);
  }

  Future<void> _withdraw(RealmInvite invite) async {
    setState(() => _withdrawing = invite.token);
    final settled = await _invitesApi.answer(invite.token, 'revoked');
    if (!mounted) return;
    setState(() {
      _withdrawing = null;
      if (settled != null) {
        _pending = _pending.where((i) => i.id != invite.id).toList();
      }
    });
  }

  /// The query as an email address, when it is one - offered as "invite by
  /// email", which works whether or not anyone has signed up with it.
  String? get _typedEmail {
    final text = _query.text.trim();
    return _invites && _emailPattern.hasMatch(text) ? text : null;
  }

  Future<void> _inviteEmail(String email) async {
    if (_emailing) return;
    setState(() => _emailing = true);
    final sent = await _invitesApi.create(
      realmId: widget.realm.id,
      target: email,
      purpose: _purpose['purpose'],
      role: _purpose['role'],
    );
    if (!mounted) return;
    setState(() => _emailing = false);
    if (sent == null) return;
    CLAlerts.show(
      sent.alreadyInvited
          ? '$email already has an invite waiting.'
          : 'Invite emailed to $email.',
      type: sent.alreadyInvited ? CLAlertType.info : CLAlertType.success,
    );
    _query.clear();
    setState(() {
      _results.clear();
      _searched = false;
    });
    _loadPending();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  bool get _fromParentServer => (widget.parentRealmId ?? '').isNotEmpty;

  Future<void> _search() async {
    final query = _query.text.trim();
    // A global search needs something to search FOR; the server's member list
    // is a finite set worth showing unprompted.
    if (query.isEmpty && !_fromParentServer) {
      setState(() {
        _results.clear();
        _searched = false;
      });
      return;
    }

    setState(() => _searching = true);
    final found = _fromParentServer
        ? await _parentServerMembers(query)
        // Entities, not people - a page can be a member. realmTypes defaults to
        // "page", which is what can hold a membership.
        // Bots included: adding one to a realm is the point of the
        // picker for them, and the default types are people and pages only -
        // so a bot was not merely unflagged here, it was unreachable.
        : await SearchApi()
            .searchEntitiesRequest(query, types: "user,realm,bot");
    if (!mounted) return;
    setState(() {
      _results
        ..clear()
        ..addAll(found);
      _searching = false;
      _searched = true;
    });
  }

  /// The parent server's members, mapped into the same shape the global search
  /// returns so the selection, the chips and the invite payload below need no
  /// second code path.
  Future<List<SearchResultUser>> _parentServerMembers(String query) async {
    final page = await ProfileApi().getRealmMembersRequest(
      widget.parentRealmId!,
      pageSize: 50,
      search: query,
    );
    return page.results
        .map((member) => SearchResultUser(
              id: member.accountId,
              entityId: member.entityId,
              username: member.handle,
              // displayName is already "First Middle Last"; splitting it back
              // out would only risk losing a part, and inviteFullName just
              // rejoins these.
              firstName: member.displayName,
              middleName: '',
              lastName: '',
              profile: member.profile,
              // Carried through, not defaulted: SearchResultUser.type falls
              // back to "user", so every page and bot in a server's member
              // list arrived claiming to be a person and no row could mark it.
              type: member.entityType.isEmpty ? 'user' : member.entityType,
              realmType: member.realmType,
              hasConnection: false,
              connectionAccomplished: false,
              isActionByEntity: false,
              isVerified: member.isVerified,
            ))
        .toList();
  }

  /// Invites everyone picked, one each. Leaves the screen once any went out;
  /// a refusal has already said why.
  Future<void> _invite() async {
    setState(() => _adding = true);
    var sent = 0;
    for (final entity in _selected.values.toList()) {
      final result = await _invitesApi.create(
        realmId: widget.realm.id,
        targetEntityId: entity.entityId,
        purpose: _purpose['purpose'],
        role: _purpose['role'],
      );
      if (result != null) {
        sent++;
        _selected.remove(entity.entityId);
      }
    }
    if (!mounted) return;
    setState(() => _adding = false);
    if (sent == 0) return;
    CLAlerts.show(
      sent == 1 ? 'Invite sent.' : '$sent invites sent.',
      type: CLAlertType.success,
    );
    // Nobody joined yet - they will once they accept - so the roster behind
    // this screen has nothing new to show.
    if (_selected.isEmpty) {
      Navigator.of(context).pop(false);
    } else {
      _loadPending();
    }
  }

  Future<void> _add() async {
    if (_selected.isEmpty || _adding) return;
    if (_invites) return _invite();
    setState(() => _adding = true);

    final ok = await ProfileApi().addRealmMembersRequest(
      // The realm id, which for a group IS its conversation id - the field web
      // calls conversationID.
      conversationId: widget.realm.id,
      // A server takes the other endpoint, so the member also lands in its
      // public channels - see addRealmMembersRequest.
      isServer: widget.realm.type == 'server',
      members: _selected.values
          .map((entity) => RealmMemberInvite(
                accountId: entity.id,
                entityId: entity.entityId,
                username: entity.username,
                fullName: inviteFullName(entity),
              ))
          .toList(),
    );
    if (!mounted) return;
    setState(() => _adding = false);

    // The request has already said why (reportedAction).
    if (!ok) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final selected = _selected.values.toList();

    return CLScreen(
      backgroundColor: p.bg,
      appBar: AppBar(
          title: Text(_invites ? 'Invite people' : 'Add members')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                CLSpacing.contentGutter, 12, CLSpacing.contentGutter, 8),
            child: CLField(
              controller: _query,
              placeholder: _fromParentServer
                  ? 'Search server members'
                  : _invites
                      ? 'Search, or type an email'
                      : 'Search people and pages',
              icon: Icons.search,
              onChanged: _onQueryChanged,
            ),
          ),

          // A page invites to follow it or to help run it; everything else
          // has one kind of invite.
          if (_invites && _isPage)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  CLSpacing.contentGutter, 0, CLSpacing.contentGutter, 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final choice in const [
                    ('follow', 'To follow'),
                    ('moderator', 'As moderator'),
                    ('admin', 'As admin'),
                  ])
                    CLChip(
                      label: choice.$2,
                      active: _pageChoice == choice.$1,
                      onTap: () => setState(() => _pageChoice = choice.$1),
                    ),
                ],
              ),
            ),

          // The running selection, so you can see what you are about to add
          // without scrolling back through the results to find the ticks.
          if (selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: CLSpacing.contentGutter, vertical: 4),
              child: SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: selected.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final entity = selected[index];
                    return CLChip(
                      label: inviteFullName(entity),
                      icon: Icons.close,
                      active: true,
                      onTap: () =>
                          setState(() => _selected.remove(entity.entityId)),
                    );
                  },
                ),
              ),
            ),

          Expanded(child: _resultsBody(p)),

          // Pinned, because the list above scrolls and the action must not
          // scroll away from a selection made at the bottom of it.
          Padding(
            // Flat 12, NOT clSheetBottomGap: that helper is for modal sheets,
            // which draw over the system bars. This is a pushed CLScreen whose
            // body is already inside a SafeArea, so adding the inset here
            // would stack it on top of one already applied.
            padding: const EdgeInsets.fromLTRB(
                CLSpacing.contentGutter, 8, CLSpacing.contentGutter, 12),
            child: CLBtn(
              label: _invites
                  ? (_adding
                      ? 'Inviting…'
                      : selected.isEmpty
                          ? 'Select someone to invite'
                          : selected.length == 1
                              ? 'Invite 1 person'
                              : 'Invite ${selected.length} people')
                  : _adding
                      ? 'Adding…'
                      : selected.isEmpty
                          ? 'Select someone to add'
                          : selected.length == 1
                              ? 'Add 1 member'
                              : 'Add ${selected.length} members',
              iconL: Icons.person_add_alt,
              block: true,
              size: CLBtnSize.lg,
              onPressed: selected.isEmpty || _adding ? null : _add,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultsBody(CLPalette p) {
    // Inset and sized to line up with the real rows: the list pads by
    // contentGutter and each row by another 4, and CLListRowSkeleton already
    // carries 6 of its own - so 12 here puts the placeholder avatar at the same
    // 18px from the edge. Unpadded it sat against the screen edge and the whole
    // list appeared to shift right once the results arrived.
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(
            CLSpacing.contentGutter - 2, 4, CLSpacing.contentGutter - 2, 8),
        // 38, matching CLAvatar in the rows below - the default 46 made the
        // text bars start further right than the real names do.
        child: CLListSkeleton(avatarSize: 38),
      );
    }

    final email = _typedEmail;

    if (!_searched) {
      final empty = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: CLSectionEmpty(
            icon: Icons.person_search_outlined,
            title: _invites ? 'Search to invite' : 'Search to add',
            subtitle: _invites
                ? 'Anyone you can find can be invited to this '
                    '${realmKindNoun(widget.realm)}, or type an email to invite '
                    'someone who is not on Chatterloop yet. They join once they '
                    'accept.'
                : 'Anyone you can find can be added to this '
                    '${realmKindNoun(widget.realm)} - they do not have to be a '
                    'contact.',
          ),
        ),
      );
      if (_pending.isEmpty && email == null) return empty;
      return ListView(
        padding: const EdgeInsets.fromLTRB(
            CLSpacing.contentGutter, 4, CLSpacing.contentGutter, 8),
        children: [
          if (email != null) _emailTile(p, email),
          if (_pending.isNotEmpty) ..._pendingRows(p),
          if (_pending.isEmpty) empty,
        ],
      );
    }

    if (_results.isEmpty && email != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
            CLSpacing.contentGutter, 4, CLSpacing.contentGutter, 8),
        children: [_emailTile(p, email)],
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: CLSectionEmpty(
            icon: Icons.search_off,
            title: 'No matches',
            subtitle: _fromParentServer
                ? 'Nobody in this server matches that name.'
                : 'Nobody matching that name or handle turned up.',
          ),
        ),
      );
    }

    final lead = email != null ? 1 : 0;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          CLSpacing.contentGutter, 4, CLSpacing.contentGutter, 8),
      itemCount: _results.length + lead,
      itemBuilder: (context, index) {
        if (index < lead) return _emailTile(p, email!);
        final entity = _results[index - lead];
        final already = widget.existingEntityIds.contains(entity.entityId);
        final picked = _selected.containsKey(entity.entityId);
        final name = inviteFullName(entity);

        return Opacity(
          opacity: already ? 0.55 : 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(CLRadii.md),
            onTap: already
                ? null
                : () => setState(() {
                      if (picked) {
                        _selected.remove(entity.entityId);
                      } else {
                        _selected[entity.entityId] = entity;
                      }
                    }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  CLAvatar(
                      id: entity.entityId,
                      entityId: entity.entityId,
                      name: name,
                      src: entity.profile,
                      size: 38,
                      kind: entity.type),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(name.isEmpty ? entity.username : name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: CLType.body,
                                      fontWeight: FontWeight.w600,
                                      color: p.text)),
                            ),
                            ...clEntityMarkers(
                              context,
                              isVerified: entity.isVerified,
                              isPage: entity.isRealm,
                              isBot: entity.type == 'bot',
                              badgeSize: 13,
                            ),
                          ],
                        ),
                        Text(
                          already ? 'Already a member' : '@${entity.username}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: CLType.caption, color: p.text2),
                        ),
                      ],
                    ),
                  ),
                  if (!already)
                    Icon(
                      picked
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: picked ? p.brand : p.text3,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// "Invite x@y.com by email" - on top of whatever the search found.
  Widget _emailTile(CLPalette p, String email) {
    return InkWell(
      borderRadius: BorderRadius.circular(CLRadii.md),
      onTap: _emailing ? null : () => _inviteEmail(email),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration:
                  BoxDecoration(color: p.brandSoft, shape: BoxShape.circle),
              child: Icon(Icons.mail_outline, size: 19, color: p.brand),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_emailing ? 'Sending…' : 'Invite by email',
                      style: TextStyle(
                          fontSize: CLType.body,
                          fontWeight: FontWeight.w600,
                          color: p.text)),
                  Text(email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: CLType.caption, color: p.text2)),
                ],
              ),
            ),
            Icon(Icons.send, size: 18, color: p.brand),
          ],
        ),
      ),
    );
  }

  List<Widget> _pendingRows(CLPalette p) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
          child: Text('WAITING FOR AN ANSWER',
              style: TextStyle(
                  fontSize: CLType.meta,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: p.text3)),
        ),
        for (final invite in _pending)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                CLAvatar(
                  id: invite.targetEntity?.id ?? invite.targetEmail ?? invite.id,
                  name: invite.targetEntity?.name ?? invite.targetEmail,
                  src: invite.targetEntity?.profile,
                  kind: invite.targetEntity?.type,
                  size: 34,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          invite.targetEntity?.name ??
                              invite.targetEmail ??
                              'Someone',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: CLType.bodySm,
                              fontWeight: FontWeight.w600,
                              color: p.text)),
                      Text(
                          'Invited ${invite.purposeLabel}'
                          '${invite.targetEntity == null ? ' · by email' : ''}',
                          style: TextStyle(
                              fontSize: CLType.meta, color: p.text3)),
                    ],
                  ),
                ),
                CLBtn(
                  label: 'Withdraw',
                  size: CLBtnSize.sm,
                  variant: CLBtnVariant.outline,
                  onPressed: _withdrawing == invite.token
                      ? null
                      : () => _withdraw(invite),
                ),
              ],
            ),
          ),
      ];
}
