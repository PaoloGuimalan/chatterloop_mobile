// Creating a group chat - webapp's CreateGroupChatModal.
//
// Its own screen, not a mode of CreateRealmScreen, even though the two forms
// look alike and POST nearly the same payload. What they do NOT share is the
// surface they belong to: a server and its channels are the gold Servers
// surface, and a group chat is a conversation reached from Messages, which is
// blue. Folding it into the servers screen meant a form opened from the inbox
// answering in the servers accent - and every future divergence would have to
// be re-branched there.
//
// Same three parts as web's modal:
//
//   name      seeded "<first name>'s Group Chat", editable
//   privacy   Private by default, as web defaults it
//   people    opens on your CONNECTIONS, switches to a global entity search
//             the moment something is typed
//
// A pushed screen rather than a bottom sheet, for the reason every picker in
// this app is one: a search field plus a scrolling result list in a sheet
// leaves the list about four rows tall, and the keyboard then covers those.

import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/network_api.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/requests/search_api.dart';
import 'package:chatterloop_app/models/user_models/search_result_model.dart';
import 'package:chatterloop_app/views/realm/realm_add_members_view.dart'
    show inviteFullName;
import 'package:flutter/material.dart';

class CreateGroupChatScreen extends StatefulWidget {
  const CreateGroupChatScreen({super.key});

  @override
  State<CreateGroupChatScreen> createState() => _CreateGroupChatScreenState();
}

class _CreateGroupChatScreenState extends State<CreateGroupChatScreen> {
  late final TextEditingController _name =
      TextEditingController(text: _defaultName);
  final TextEditingController _query = TextEditingController();

  final List<SearchResultUser> _results = [];

  /// Keyed by entity id, so a selection survives the result list changing
  /// underneath it as the query is refined.
  final Map<String, SearchResultUser> _selected = {};

  /// Web's default.
  bool _isPrivate = true;

  Timer? _debounce;
  bool _searching = false;
  bool _saving = false;

  /// Web seeds the name from the ACCOUNT's first name - "Paolo's Group Chat" -
  /// even while acting as a page. Kept as is: it is a starting point in an
  /// editable field, not an identity claim.
  String get _defaultName {
    final first = appStore.state.userAuth.user.firstname.trim();
    return first.isEmpty ? 'New Group Chat' : "$first's Group Chat";
  }

  @override
  void initState() {
    super.initState();
    // Opens on your connections, the way web's modal opens on your contacts.
    // A new group starts with only you in it, so there is always somebody to
    // choose - an empty screen asking you to type would be a worse first frame
    // than a list you can tap.
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  /// ONE list from ONE source, chosen by whether a query is typed - never the
  /// two merged. Web's modal is explicit about this: "who do I already know"
  /// and "who exists" are different questions, and a merged list cannot say
  /// which a row answered, so its empty state would be wrong for both.
  Future<void> _load() async {
    final query = _query.text.trim();
    setState(() => _searching = true);

    final found = query.isEmpty
        ? await _connections()
        // Bots and pages included - membership is entity-based, so either can
        // be a founding member exactly as a person can. realmTypes stays at
        // its "page" default: a group or a server is not something you add to
        // a group chat.
        : await SearchApi()
            .searchEntitiesRequest(query, types: "user,realm,bot");
    if (!mounted) return;

    // Never yourself: you are the creator and are made owner server-side.
    // Compared on ENTITY ids, because a page's account id can never equal a
    // user id.
    final me = appStore.state.userAuth.user.entityId;
    setState(() {
      _results
        ..clear()
        ..addAll(found.where((entity) => entity.entityId != me));
      _searching = false;
    });
  }

  /// Your connections in the shape the search returns, so the selection, the
  /// chips and the payload need no second code path.
  Future<List<SearchResultUser>> _connections() async {
    final page = await NetworkApi().networkSectionRequest(
      NetworkSection.connections,
      pageSize: 30,
    );
    return page.results
        .map((entity) => SearchResultUser(
              id: entity.id,
              entityId: entity.entityId,
              username: entity.handle,
              // displayName is already "First Middle Last"; splitting it back
              // out would only risk losing a part, and inviteFullName just
              // rejoins these.
              firstName: entity.displayName,
              middleName: '',
              lastName: '',
              profile: entity.profile,
              type: entity.type,
              realmType: entity.realmType,
              isVerified: entity.isVerified,
              hasConnection: true,
              connectionAccomplished: true,
              connectionId: entity.connectionId,
              isActionByEntity: false,
            ))
        .toList();
  }

  Future<void> _create() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A group chat needs a name.')),
      );
      return;
    }

    setState(() => _saving = true);
    final ok = await ProfileApi().createGroupChatRequest(
      name: name,
      isPrivate: _isPrivate,
      memberEntityIds: _selected.keys.toList(),
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not create the group chat. Please try '
                'again.')),
      );
      return;
    }
    // True, not the conversation id: /u/createContactGroupChat answers
    // {status, message} and nothing else - the conversation itself reaches the
    // client over SSE - so all the caller can be told is that it worked, and
    // it refreshes its list on that.
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final selected = _selected.values.toList();

    return CLScreen(
      backgroundColor: p.bg,
      appBar: AppBar(title: const Text('Create group chat')),
      body: Column(
        children: [
          // The form. Fixed above the picker rather than scrolling with it:
          // there are only two short fields, and a name you cannot see while
          // choosing members is a name you forget to set.
          Padding(
            padding: const EdgeInsets.fromLTRB(
                CLSpacing.contentGutter, 12, CLSpacing.contentGutter, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CLField(
                  controller: _name,
                  label: 'Name of Group Chat',
                  placeholder: 'Group chat name',
                ),
                const SizedBox(height: 12),
                CLSegmentedChoice<bool>(
                  label: 'Privacy',
                  value: _isPrivate,
                  enabled: !_saving,
                  // Brand blue by default, which is this surface's accent -
                  // no accent: needed, unlike the servers form.
                  options: const [
                    CLSegmentedOption(false, 'Public', Icons.public),
                    CLSegmentedOption(true, 'Private', Icons.lock_outline),
                  ],
                  onChanged: (value) => setState(() => _isPrivate = value),
                ),
                const SizedBox(height: 12),
                CLField(
                  controller: _query,
                  label: 'Add People',
                  placeholder: 'Search people, pages and bots',
                  icon: Icons.search,
                  onChanged: _onQueryChanged,
                ),
              ],
            ),
          ),

          // The running selection, so you can see who you are about to add
          // without scrolling back through the results to find the ticks.
          if (selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  CLSpacing.contentGutter, 8, CLSpacing.contentGutter, 0),
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
          // scroll away from a selection made at the bottom of it. Flat 12
          // rather than clSheetBottomGap - this is a pushed CLScreen, already
          // inside a SafeArea.
          Padding(
            padding: const EdgeInsets.fromLTRB(
                CLSpacing.contentGutter, 8, CLSpacing.contentGutter, 12),
            child: CLBtn(
              label: _saving ? 'Creating…' : 'Create group chat',
              iconL: Icons.group_add,
              // Brand blue, NOT the servers gold. This form is reached from
              // Messages and makes a conversation; the gold belongs to the
              // Servers surface, and wearing it here would say this screen
              // came from somewhere it did not.
              variant: CLBtnVariant.primary,
              block: true,
              size: CLBtnSize.lg,
              onPressed: _saving ? null : _create,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultsBody(CLPalette p) {
    if (_searching) {
      // Inset and sized to line up with the real rows: the list pads by
      // contentGutter and each row by another 4, and CLListRowSkeleton already
      // carries 6 of its own - so 12 here puts the placeholder avatar at the
      // same 18px from the edge.
      return const Padding(
        padding: EdgeInsets.fromLTRB(
            CLSpacing.contentGutter - 2, 4, CLSpacing.contentGutter - 2, 8),
        // 38, matching CLAvatar in the rows below.
        child: CLListSkeleton(avatarSize: 38),
      );
    }

    if (_results.isEmpty) {
      // With nothing typed this is an empty address book, not a failed search.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _query.text.trim().isEmpty
              ? const CLSectionEmpty(
                  icon: Icons.people_outline,
                  title: 'No connections yet',
                  subtitle: 'Search above to add anyone - they do not have to '
                      'be a contact.',
                )
              : const CLSectionEmpty(
                  icon: Icons.search_off,
                  title: 'No matches',
                  subtitle: 'Nobody matching that name or handle turned up.',
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
        final picked = _selected.containsKey(entity.entityId);
        final name = inviteFullName(entity);

        return InkWell(
          borderRadius: BorderRadius.circular(CLRadii.md),
          onTap: () => setState(() {
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
                    src: clCleanMediaSrc(entity.profile),
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
                      Text('@${entity.username}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: CLType.caption, color: p.text2)),
                    ],
                  ),
                ),
                Icon(
                  picked ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 20,
                  // Blue when ticked, matching the Create button below and the
                  // Messages surface this was opened from.
                  color: picked ? p.brand : p.text3,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
