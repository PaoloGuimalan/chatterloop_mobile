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

import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/requests/search_api.dart';
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

  @override
  void initState() {
    super.initState();
    // Nothing to type for a server-sourced list - show it immediately.
    if (_fromParentServer) _search();
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
        : await SearchApi().searchEntitiesRequest(query);
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
              hasConnection: false,
              connectionAccomplished: false,
              isActionByEntity: false,
            ))
        .toList();
  }

  Future<void> _add() async {
    if (_selected.isEmpty || _adding) return;
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

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not add them. Please try again.')));
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final selected = _selected.values.toList();

    return CLScreen(
      backgroundColor: p.bg,
      appBar: CLPanelAppBar(title: const Text('Add members')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                CLSpacing.contentGutter, 12, CLSpacing.contentGutter, 8),
            child: CLField(
              controller: _query,
              placeholder: _fromParentServer
                  ? 'Search server members'
                  : 'Search people and pages',
              icon: Icons.search,
              onChanged: _onQueryChanged,
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
              label: _adding
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

    if (!_searched) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: CLSectionEmpty(
            icon: Icons.person_search_outlined,
            title: 'Search to add',
            subtitle: 'Anyone you can find can be added to this '
                '${realmKindNoun(widget.realm)} - they do not have to be a '
                'contact.',
          ),
        ),
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

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          CLSpacing.contentGutter, 4, CLSpacing.contentGutter, 8),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final entity = _results[index];
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
                      name: name,
                      src: entity.profile,
                      size: 38),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name.isEmpty ? entity.username : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: CLType.body,
                                fontWeight: FontWeight.w600,
                                color: p.text)),
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
}
