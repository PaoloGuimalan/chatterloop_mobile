// Starting a one-to-one conversation: pick someone, land in the thread.
//
// No webapp counterpart. Web's Messages screen only offers Create Group -
// starting a DM there means finding the person's profile first and pressing
// Message. On a phone that is three screens deep for the single most common
// thing anyone does in an inbox, which is why this exists.
//
// It is the profile Message button's flow with the profile taken out. Tapping
// a row posts to /m/crtc, which is GET-OR-CREATE: an existing conversation
// comes back by its own id and nothing is duplicated, so there is no need to
// know in advance whether you have talked to this person before.
//
// A pushed screen rather than a sheet, for the same reason
// [CreateRealmScreen] is one: a search field plus a scrolling result list in a
// sheet leaves the list about four rows tall, and the keyboard then covers
// those.

import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/core/requests/network_api.dart';
import 'package:chatterloop_app/core/requests/search_api.dart';
import 'package:chatterloop_app/models/user_models/search_result_model.dart';
import 'package:chatterloop_app/views/realm/realm_add_members_view.dart'
    show inviteFullName;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class NewMessageScreen extends StatefulWidget {
  const NewMessageScreen({super.key});

  @override
  State<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends State<NewMessageScreen> {
  final TextEditingController _query = TextEditingController();
  final List<SearchResultUser> _results = [];

  Timer? _debounce;
  bool _loading = false;

  /// The row being opened, by entity id. Held so that row alone shows a
  /// spinner - /m/crtc is a round trip, and a list that looks inert for it
  /// invites a second tap, which would be a second request for the same
  /// conversation.
  String? _opening;

  @override
  void initState() {
    super.initState();
    // Opens on your connections, like the group-chat picker: an inbox is
    // mostly people you already talk to, and an empty screen asking you to
    // type is a worse first frame than a list you can tap.
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  /// One list from one source, chosen by whether a query is typed - never the
  /// two merged. Same rule the group-chat picker follows.
  Future<void> _load() async {
    final query = _query.text.trim();
    setState(() => _loading = true);

    final found = query.isEmpty
        ? await _connections()
        // Bots and pages included: both are messageable entities, and /m/crtc
        // is entity-generic - it takes two entity ids and does not care what
        // kind they are.
        : await SearchApi()
            .searchEntitiesRequest(query, types: "user,realm,bot");
    if (!mounted) return;

    // Never yourself. Compared on ENTITY ids, because a page's account id can
    // never equal a user id.
    final me = appStore.state.userAuth.user.entityId;
    setState(() {
      _results
        ..clear()
        ..addAll(found.where((entity) => entity.entityId != me));
      _loading = false;
    });
  }

  /// Your connections in the shape the search returns, so one row builder and
  /// one tap handler serve both sources.
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

  /// Opens a conversation with the picked entity - the profile screens'
  /// Message button, with the profile taken out.
  ///
  /// Identical to [RealmProfileScreen]'s `_openMessage`: post to /m/crtc, then
  /// push the conversation it names. /m/crtc is GET-OR-CREATE, so that one
  /// call both answers "do these two already have a conversation" and makes
  /// one if they do not - which is why no check precedes it and why picking
  /// somebody you already talk to reopens that thread rather than starting a
  /// second.
  ///
  /// Always the endpoint, never the connectionId this screen sometimes holds
  /// from the connections list: the shortcut saves a round trip and buys a
  /// second way to be wrong.
  ///
  /// push, not pushReplacement - the same thing the Message button does, so
  /// backing out of the thread returns you to where you opened it from.
  Future<void> _open(SearchResultUser entity) async {
    if (_opening != null) return;
    setState(() => _opening = entity.entityId);

    final conversationId =
        await ConversationsApi().createInitialConversationRequest(
      entity.entityId,
    );
    if (!mounted) return;
    setState(() => _opening = null);

    if (conversationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't open that conversation. Please try again.")));
      return;
    }
    context.push('/conversation/$conversationId');
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    return CLScreen(
      backgroundColor: p.bg,
      appBar: AppBar(title: const Text('New message')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                CLSpacing.contentGutter, 12, CLSpacing.contentGutter, 8),
            child: CLField(
              controller: _query,
              placeholder: 'Search people, pages and bots',
              icon: Icons.search,
              onChanged: _onQueryChanged,
            ),
          ),
          Expanded(child: _body(p)),
        ],
      ),
    );
  }

  Widget _body(CLPalette p) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(
            CLSpacing.contentGutter - 2, 4, CLSpacing.contentGutter - 2, 8),
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
                  subtitle: 'Search above for anyone - you do not have to be '
                      'connected to message them.',
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
        final name = inviteFullName(entity);
        final opening = _opening == entity.entityId;

        return InkWell(
          borderRadius: BorderRadius.circular(CLRadii.md),
          // Inert while any row is opening, so a slow /m/crtc cannot be turned
          // into two conversations by an impatient second tap.
          onTap: _opening == null ? () => _open(entity) : null,
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
                      Text('@${entity.username}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: CLType.caption, color: p.text2)),
                    ],
                  ),
                ),
                if (opening)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(Icons.chevron_right, size: 20, color: p.text3),
              ],
            ),
          ),
        );
      },
    );
  }
}
