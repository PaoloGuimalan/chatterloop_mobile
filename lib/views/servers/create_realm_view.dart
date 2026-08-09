// Creating a server, and creating a channel inside one - webapp's
// CreateServerModal and Servers/CreateChannelModal.
//
// ONE screen for both, because web's two modals are the same form: a name, a
// privacy choice, a member picker and Create. What actually differs is small
// and is spelled out in `_isChannel` branches below:
//
//   server   no type field; members come from a GLOBAL entity search
//   channel  a text/voice type field; members come from the PARENT SERVER, and
//            are only asked for at all when the channel is private
//
// A pushed screen rather than a bottom sheet. The picker needs a search field, a
// scrolling result list and a pinned action - a sheet holding all three leaves
// the list about four rows tall, and the keyboard then covers those.
//
// Deliberate departures from web, both carried over from the add-members screen
// so the two pickers behave identically:
//
//  - the SERVER picker searches globally and searches ENTITIES, where web
//    offers only your one-on-one contacts. Membership is entity-based, so a
//    page can be a member exactly as a person can.
//  - the CHANNEL picker pages the server's member list through the Django
//    members endpoint (with search), where web hands it the already-loaded
//    `serverdetails.usersWithInfo`. Same set, but it does not go stale and it
//    is not capped by whatever the channels payload happened to include.

import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/requests/search_api.dart';
import 'package:chatterloop_app/models/user_models/search_result_model.dart';
import 'package:chatterloop_app/views/realm/realm_add_members_view.dart'
    show inviteFullName;
import 'package:flutter/material.dart';

/// What a successful create pops back, so the caller knows what landed:
/// "server", "channel" or "voice". A voice channel needs a second, delayed
/// refresh (see below), and only the caller can do that.
typedef CreatedRealmKind = String;

/// Where the member picker's candidates come from - the one rule that differs
/// between the two forms, and the one the product asked for explicitly:
///
///   server                    globalEntities       anyone findable
///   private channel or voice  parentServerMembers  you can only add to a
///                             channel someone who is already in the server
///                             that owns it
///   public channel or voice   none                 membership follows the
///                             server, so there is nothing to choose
///
/// Top-level and pure so the rule is testable on its own; web's equivalent is
/// spread across a `gcprivacy &&` in the JSX and which list it was handed.
enum CreateRealmMemberSource { none, globalEntities, parentServerMembers }

CreateRealmMemberSource createRealmMemberSource({
  required bool isChannel,
  required bool isPrivate,
}) {
  if (!isChannel) return CreateRealmMemberSource.globalEntities;
  return isPrivate
      ? CreateRealmMemberSource.parentServerMembers
      : CreateRealmMemberSource.none;
}

class CreateRealmScreen extends StatefulWidget {
  /// Null creates a SERVER. Set creates a channel inside that server.
  final String? parentServerId;

  const CreateRealmScreen.server({super.key}) : parentServerId = null;

  const CreateRealmScreen.channel({super.key, required String serverId})
      : parentServerId = serverId;

  @override
  State<CreateRealmScreen> createState() => _CreateRealmScreenState();
}

class _CreateRealmScreenState extends State<CreateRealmScreen> {
  late final TextEditingController _name =
      TextEditingController(text: _defaultName);
  final TextEditingController _query = TextEditingController();

  final List<SearchResultUser> _results = [];

  /// Keyed by entity id, so a selection survives the result list changing
  /// underneath it as the query is refined.
  final Map<String, SearchResultUser> _selected = {};

  /// Web's default for both modals is Private.
  bool _isPrivate = true;

  /// Web's select, and its default: "channel" is a text channel, "voice" a
  /// voice room. Ignored in server mode.
  String _channelType = 'channel';

  Timer? _debounce;
  bool _searching = false;
  bool _searched = false;
  bool _saving = false;

  bool get _isChannel => widget.parentServerId != null;

  /// Web seeds the name from the ACCOUNT's first name - "Paolo's Server" -
  /// even while acting as a page. Kept as is: it is a starting point in an
  /// editable field, not an identity claim.
  String get _defaultName {
    final first = appStore.state.userAuth.user.firstname.trim();
    final noun = _isChannel ? 'Channel' : 'Server';
    return first.isEmpty ? 'New $noun' : "$first's $noun";
  }

  CreateRealmMemberSource get _memberSource => createRealmMemberSource(
        isChannel: _isChannel,
        isPrivate: _isPrivate,
      );

  /// A public channel takes its membership from the server, so web hides the
  /// picker entirely for one - there is nothing to choose. A server always asks,
  /// public or not, since it starts with only you in it.
  bool get _picksMembers => _memberSource != CreateRealmMemberSource.none;

  @override
  void initState() {
    super.initState();
    // A server's member list is a finite set worth showing unprompted; a global
    // search has nothing to search for yet.
    if (_isChannel) _search();
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
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty && !_isChannel) {
      setState(() {
        _results.clear();
        _searched = false;
      });
      return;
    }

    setState(() => _searching = true);
    final found = switch (_memberSource) {
      CreateRealmMemberSource.parentServerMembers =>
        await _serverMembers(query),
      CreateRealmMemberSource.globalEntities =>
        await SearchApi().searchEntitiesRequest(query),
      // Unreachable while the picker is hidden, and harmless if it is not.
      CreateRealmMemberSource.none => const <SearchResultUser>[],
    };
    if (!mounted) return;

    // Never yourself. You are the creator of a server and already a member of
    // the parent server - web excludes the acting entity from its channel
    // picker for the same reason, and compares on entity ids because a page's
    // account id can never match a user id.
    final me = appStore.state.userAuth.user.entityId;
    setState(() {
      _results
        ..clear()
        ..addAll(found.where((entity) => entity.entityId != me));
      _searching = false;
      _searched = true;
    });
  }

  /// The parent server's members, mapped into the shape the global search
  /// returns so the selection, the chips and the payload need no second code
  /// path. Same mapping as the add-members screen's parent-server mode.
  Future<List<SearchResultUser>> _serverMembers(String query) async {
    final page = await ProfileApi().getRealmMembersRequest(
      widget.parentServerId!,
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

  Future<void> _create() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('A ${_isChannel ? 'channel' : 'server'} needs a name.')));
      return;
    }

    // Only what the form asked for. A channel switched back to public after
    // people were ticked must not carry those ticks - the picker is hidden at
    // that point, so sending them would create members the user cannot see.
    final memberEntityIds =
        _picksMembers ? _selected.keys.toList() : const <String>[];

    setState(() => _saving = true);
    final ok = _isChannel
        ? await ProfileApi().createChannelRequest(
            serverId: widget.parentServerId!,
            name: name,
            isPrivate: _isPrivate,
            type: _channelType,
            memberEntityIds: memberEntityIds,
          )
        : await ProfileApi().createServerRequest(
            name: name,
            isPrivate: _isPrivate,
            memberEntityIds: memberEntityIds,
          );
    if (!mounted) return;
    setState(() => _saving = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not create the '
              '${_isChannel ? 'channel' : 'server'}. Please try again.')));
      return;
    }
    Navigator.of(context)
        .pop<CreatedRealmKind>(_isChannel ? _channelType : 'server');
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final selected = _selected.values.toList();

    return CLScreen(
      backgroundColor: p.bg,
      appBar:
          AppBar(title: Text(_isChannel ? 'Create channel' : 'Create server')),
      body: Column(
        children: [
          // The form. Fixed above the picker rather than scrolling with it:
          // there are at most three short fields, and a name you cannot see
          // while choosing members is a name you forget to set.
          Padding(
            padding: const EdgeInsets.fromLTRB(
                CLSpacing.contentGutter, 12, CLSpacing.contentGutter, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CLField(
                  controller: _name,
                  label: _isChannel ? 'Name of Channel' : 'Name of Server',
                  placeholder: _isChannel ? 'Channel name' : 'Server name',
                ),
                const SizedBox(height: 12),
                _ChoiceField(
                  label: 'Privacy',
                  value: _isPrivate,
                  enabled: !_saving,
                  options: const [(false, 'Public'), (true, 'Private')],
                  onChanged: (value) => setState(() => _isPrivate = value),
                ),
                if (_isChannel) ...[
                  const SizedBox(height: 12),
                  _ChoiceField<String>(
                    label: 'Type',
                    value: _channelType,
                    enabled: !_saving,
                    // Web's two select options, same values and same order.
                    options: const [
                      ('channel', 'Text Channel'),
                      ('voice', 'Voice Channel'),
                    ],
                    onChanged: (value) => setState(() => _channelType = value),
                  ),
                ],
                const SizedBox(height: 14),
                if (_picksMembers)
                  CLField(
                    controller: _query,
                    label: 'Add People',
                    placeholder: _isChannel
                        ? 'Search server members'
                        : 'Search people and pages',
                    icon: Icons.search,
                    onChanged: _onQueryChanged,
                  ),
              ],
            ),
          ),

          // The running selection, so you can see what you are about to add
          // without scrolling back through the results to find the ticks.
          if (_picksMembers && selected.isNotEmpty)
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

          Expanded(child: _picksMembers ? _resultsBody(p) : _publicNote(p)),

          // Pinned, because the list above scrolls and the action must not
          // scroll away from a selection made at the bottom of it. Flat 12
          // rather than clSheetBottomGap - this is a pushed CLScreen, already
          // inside a SafeArea.
          Padding(
            padding: const EdgeInsets.fromLTRB(
                CLSpacing.contentGutter, 8, CLSpacing.contentGutter, 12),
            child: CLBtn(
              label: _saving
                  ? 'Creating…'
                  : _isChannel
                      ? 'Create channel'
                      : 'Create server',
              iconL: Icons.add,
              // Gold: this is the servers surface, and every action on it uses
              // the servers accent rather than the app blue.
              variant: CLBtnVariant.gold,
              block: true,
              size: CLBtnSize.lg,
              onPressed: _saving ? null : _create,
            ),
          ),
        ],
      ),
    );
  }

  /// What fills the space where the picker would be for a PUBLIC channel -
  /// web just leaves a gap. Saying why there is nothing to choose is the whole
  /// point: it is the answer to "where did the member list go".
  Widget _publicNote(CLPalette p) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: CLSectionEmpty(
            icon: Icons.tag,
            title: 'Open to the whole server',
            subtitle: 'Everyone in the server can see and join a public '
                '${_channelType == 'voice' ? 'voice room' : 'channel'}, '
                'so there is nobody to add.',
          ),
        ),
      );

  Widget _resultsBody(CLPalette p) {
    if (_searching) return const CLListSkeleton();

    if (!_searched) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: CLSectionEmpty(
            icon: Icons.person_search_outlined,
            title: 'Search to add',
            subtitle: 'Anyone you can find can be added - they do not have to '
                'be a contact. You can also add people after creating it.',
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
            subtitle: _isChannel
                ? 'Nobody else in this server matches that name.'
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
                    name: name,
                    src: clCleanMediaSrc(entity.profile),
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
                  // Gold when ticked, matching the Create button below and the
                  // rest of this surface.
                  color: picked ? p.gold : p.text3,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A labelled row of chips - what a two- or three-value choice looks like on a
/// phone, where web uses a toggle switch and a select. Generic so privacy
/// (bool) and channel type (String) share one control.
///
/// Its own rather than CLChip's `active` styling: an active CLChip fills with
/// the app blue, and nothing on the servers surface is blue.
class _ChoiceField<T> extends StatelessWidget {
  final String label;
  final T value;
  final bool enabled;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  const _ChoiceField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: CLType.bodySm,
                fontWeight: FontWeight.w600,
                color: p.text)),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final (optionValue, optionLabel) in options)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(CLRadii.pill),
                  onTap: enabled ? () => onChanged(optionValue) : null,
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: optionValue == value ? p.goldSoft : p.surface,
                      borderRadius: BorderRadius.circular(CLRadii.pill),
                      border: Border.all(
                          color: optionValue == value ? p.gold : p.border2),
                    ),
                    child: Center(
                      child: Text(
                        optionLabel,
                        style: TextStyle(
                          fontSize: CLType.bodySm,
                          fontWeight: FontWeight.w600,
                          color: optionValue == value ? p.gold : p.text2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
