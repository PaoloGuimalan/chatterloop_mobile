// Inside a server - webapp's Channels.tsx.
//
// Web renders a channel sidebar beside a routed pane, and on mobile web the
// server rail hides entirely once you are inside (`railHidden = isMobile &&
// isInsideServer`). So the phone shape is: the channel list IS the screen, and
// opening a channel pushes the conversation over it.
//
// A channel needs no conversation screen of its own. Web's ServerConversation
// is a thin wrapper that hands the channel's `groupID` to the SAME ConversationV2
// the messages tab uses; this pushes /conversation/<groupID> for the same
// reason. What differs is the header - see conversation_view's call gating,
// which drops the call buttons for a channel.
//
// Creating channels lives in create_realm_view.dart, reached from the + beside
// the Channels heading.
//
// NOT here: voice channels themselves. One can be CREATED - the server does that
// work, and a channel you cannot enter from a phone is still a channel your
// members use from the web - but it is listed and not enterable, because it
// needs the mediasoup stack, the unmaintained dependency we already flagged.
// Offering a room that silently fails to connect would be worse than saying so.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/report_sheet.dart';
import 'package:chatterloop_app/core/utils/sse_events.dart';
import 'package:chatterloop_app/models/http_models/paged_result.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/views/realm/realm_manage_view.dart';
import 'package:chatterloop_app/views/servers/create_realm_view.dart';
import 'package:chatterloop_app/views/servers/servers_view.dart';
import 'package:chatterloop_app/views/servers/voice_channel_view.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ServerChannelsPane extends StatefulWidget {
  final String serverId;

  /// Passed through from the directory row so the header has a name before the
  /// channel request lands - the same reason the conversation screen takes its
  /// title from the row that opened it.
  final String? serverName;
  final String? serverProfile;

  /// Called after LEAVING, so the shell can drop the server from the rail and
  /// swap this pane back to the directory. The shell owns both, and leaving
  /// should not take you out of the servers screen - you are still browsing.
  final void Function(String serverId)? onLeave;

  const ServerChannelsPane({
    super.key,
    required this.serverId,
    this.serverName,
    this.serverProfile,
    this.onLeave,
  });

  @override
  State<ServerChannelsPane> createState() => _ServerChannelsPaneState();
}

class _ServerChannelsPaneState extends State<ServerChannelsPane> {
  List<ServerChannel> _channels = const [];
  bool _loading = true;

  /// Straight off the channels payload - see getServerChannelsRequest. Web reads
  /// `serverdetails.is_admin` from the same object, and two earlier attempts to
  /// derive it elsewhere were both wrong: the realm profile looked up by SLUG
  /// cannot resolve a server (servers have no slug - `forManage: true` is what
  /// switches that lookup to realm_id), and my own member row does not say
  /// "admin" for an owner.
  bool _isAdmin = false;

  /// False when /s/initserverchannels answered 401 - you are not a member.
  ///
  /// Reachable now that Explore opens a server by id whether or not you are in
  /// one (web does the same, and bounces to its directory on the refusal). An
  /// empty channel list would be a lie about why the screen is empty, and the
  /// useful thing to offer here is Join.
  bool _hasAccess = true;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Refetch whenever a message lands anywhere - web re-runs its channels
    // fetch on the messages list for the same reason. The SSE signal is used
    // rather than the redux conversation list because that list comes from
    // /m/conversations, which does not include channels, so a channel message
    // never moves it.
    messagesListSignals.addListener(_onMessagesSignal);
    // A channel was CREATED. The messages signal above covers a text channel
    // only by accident - creating one writes a system message, which raises
    // messages_list - and covers a VOICE room not at all, because a room has no
    // chat history to write that message into. So a voice channel someone else
    // created stayed invisible here until the list happened to be refetched for
    // an unrelated reason. This is the direct statement of it.
    serverChannelsChanges.addListener(_onChannelsChanged);
    // Live occupancy, without refetching: the counts on the rows come from
    // VoiceRoomPresence, which the SSE events patch as people come and go.
    VoiceRoomPresence.instance.revision.addListener(_onPresenceChanged);
  }

  @override
  void dispose() {
    messagesListSignals.removeListener(_onMessagesSignal);
    serverChannelsChanges.removeListener(_onChannelsChanged);
    VoiceRoomPresence.instance.revision.removeListener(_onPresenceChanged);
    super.dispose();
  }

  void _onMessagesSignal() {
    if (mounted) _load();
  }

  void _onChannelsChanged() {
    final change = serverChannelsChanges.value;
    if (!mounted || change == null) return;
    // Only THIS server's list. Another server's new channel is none of this
    // pane's business - it will be there when that server is opened.
    if (change.serverId != widget.serverId) return;
    _load();
  }

  void _onPresenceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final result = await ProfileApi().getServerChannelsRequest(widget.serverId);
    if (!mounted) return;
    for (final channel in result.channels) {
      if (channel.isVoice) {
        VoiceRoomPresence.instance
            .seed(channel.conversationId, channel.voiceParticipantIds);
      }
    }
    setState(() {
      _channels = result.channels;
      _isAdmin = result.isAdmin;
      _hasAccess = result.hasAccess;
      _loading = false;
    });
  }

  /// Joining from inside the server you were refused - the same call the
  /// directory card makes. On success the channel list is re-read, which is
  /// what turns this screen into the real thing; the rail picks the server up
  /// on its own, from the membership event the join publishes.
  Future<void> _join() async {
    if (_joining) return;
    setState(() => _joining = true);
    final joined = await ProfileApi().joinServerRequest(widget.serverId);
    if (!mounted) return;
    setState(() => _joining = false);
    if (!joined) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not join. Please try again.')));
      return;
    }
    setState(() => _loading = true);
    await _load();
  }

  PopupMenuItem<String> _menuItem(
      CLPalette p, String value, IconData icon, String label,
      {bool danger = false}) {
    final color = danger ? p.pink : p.text2;
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(
                color: danger ? p.pink : p.text, fontSize: CLType.body)),
      ]),
    );
  }

  /// Leaving is removing yourself - the same call the conversation's Leave entry
  /// makes, and it takes the ENTITY id despite the field being `account_ids`.
  Future<void> _leaveServer() async {
    final p = cl(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surface,
        title: Text('Leave server?',
            style: TextStyle(color: p.text, fontSize: CLType.screenTitle)),
        content: Text(
          "You'll lose access to its channels, and you'll need to be added "
          "back or join again to return.",
          style: TextStyle(color: p.text2, fontSize: CLType.body),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: p.text2))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: p.pink),
              child: const Text('Leave')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final result = await ProfileApi().removeRealmMembersRequest(
        widget.serverId, [appStore.state.userAuth.user.entityId]);
    if (!mounted) return;
    if (!result.ok) {
      // The owner is refused here ("Transfer ownership to another member
      // before leaving.") - this screen does not carry the realm payload, so
      // it reports the server's reason rather than pre-empting it.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(result.message ?? 'Could not leave. Please try again.')));
      return;
    }
    // Back to the directory, NOT out to the Servers tab. You have left one
    // server, which is no reason to close the whole screen - Top Servers is
    // where you would go next anyway. The shell also drops it from the rail:
    // refetching /s/initserverlist would work but is a round trip to learn
    // something already known, and until it landed the rail would still show a
    // server you are no longer in.
    widget.onLeave?.call(widget.serverId);
  }

  /// Pushes the create form, then re-reads the channel list.
  ///
  /// A VOICE channel gets a second read two seconds later, exactly as web does:
  /// the room is provisioned asynchronously by the media service, so the list
  /// fetched immediately after the create call usually does not have it yet.
  Future<void> _createChannel() async {
    final created = await Navigator.of(context).push<CreatedRealmKind>(
      MaterialPageRoute(
          builder: (_) => CreateRealmScreen.channel(serverId: widget.serverId)),
    );
    if (created == null || !mounted) return;
    await _load();
    if (created == 'voice') {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) await _load();
    }
  }

  /// Joining a voice room, by the SAME path an outgoing call takes: joinCall,
  /// then the CallSession in redux, then /call/active. Deliberately the proven
  /// screen rather than a bespoke one - ActiveCallView owns the renderers, the
  /// camera and screen-share controls and the teardown, and a voice room needs
  /// every one of those. Web makes the same choice: VoiceChannel.tsx renders the
  /// call window's own VoiceWindow.
  ///
  /// The one step it does NOT take is CallApi().callRequest - that is the ring.
  /// A voice channel is a room you walk into; nobody is being invited.
  ///
  /// conversationType 'group' is load-bearing: the engine's single-call
  /// watchdogs (45s ringing cap, auto-end-when-alone, 25s media-silence) all
  /// short-circuit on isGroup, and a room has to survive one person sitting in
  /// it. callType 'audio' matches web forcing type: "audio", and the camera stays
  /// available through ActiveCallView's own toggle.
  /// Opens the room's own screen, which joins on arrival - see
  /// VoiceChannelScreen. No ring, no recipient list: a voice channel is walked
  /// into, and presence is announced by the controller's notify-voice-join.
  void _openVoice(ServerChannel channel) {
    if (appStore.state.currentCall != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Leave your current call first.')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VoiceChannelScreen(
        conversationId: channel.conversationId,
        channelName: channel.name,
        isPrivate: channel.isPrivate,
      ),
    ));
  }

  void _open(ServerChannel channel) {
    if (channel.conversationId.isEmpty) return;
    if (channel.isVoice) {
      _openVoice(channel);
      return;
    }
    // The channel's groupID IS its conversation id - web hands the same value
    // to ConversationV2.
    context.push('/conversation/${channel.conversationId}');
  }

  @override
  Widget build(BuildContext context) => _shell(cl(context));

  Widget _shell(CLPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The server's own header - avatar, name, and the info action web puts
        // in the same corner.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              CLAvatar(
                  id: widget.serverId,
                  name: widget.serverName ?? '',
                  src: clCleanMediaSrc(widget.serverProfile),
                  // 40 and CLType.title below: exactly the conversation
                  // header's avatar and name. A channel list and a conversation
                  // are the same kind of place, so their headers should not read
                  // at two different weights.
                  size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.serverName ?? 'Server',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: CLType.title,
                        fontWeight: FontWeight.bold,
                        color: p.text)),
              ),
              // A menu, not a single action - the same shape the conversation
              // header uses, and web's server header carries the same three.
              PopupMenuButton<String>(
                tooltip: 'Options',
                color: p.surface,
                icon: Icon(Icons.info_outline, size: 20, color: p.text2),
                onSelected: (value) {
                  switch (value) {
                    case 'info':
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ServerInfoScreen(
                          serverId: widget.serverId,
                          serverName: widget.serverName,
                          serverProfile: widget.serverProfile,
                        ),
                      ));
                    case 'manage':
                      openRealmManage(context, widget.serverId);
                    case 'report':
                      showReportSheet(
                        context,
                        targetType: ReportTargetType.realm,
                        // The realm id - the reports endpoint resolves a realm
                        // from either that or its entity id, and this pane only
                        // ever holds the former.
                        targetId: widget.serverId,
                        title: 'Report this server',
                      );
                    case 'leave':
                      _leaveServer();
                  }
                },
                itemBuilder: (context) => [
                  _menuItem(p, 'info', Icons.info_outline, 'Info'),
                  // Admins only. The server refuses a non-admin's edits anyway,
                  // but offering the entry means every non-admin who taps it
                  // gets a screen that can only fail - and Leave, the thing they
                  // actually want, sits right under it.
                  if (_isAdmin)
                    _menuItem(p, 'manage', Icons.tune, 'Manage server'),
                  // Above Leave, matching web's server info modal: Leave is the
                  // destructive one and stays last, so Report never sits where
                  // a mis-tap costs a membership.
                  _menuItem(p, 'report', Icons.report, 'Report server',
                      danger: true),
                  // Nothing to leave when you were never in - this pane is
                  // reachable from Explore for a server you are not a member of.
                  if (_hasAccess)
                    _menuItem(p, 'leave', Icons.logout, 'Leave server',
                        danger: true),
                ],
              ),
            ],
          ),
        ),
        Divider(height: 1, color: p.border),
        Expanded(child: _body(p)),
      ],
    );
  }

  Widget _body(CLPalette p) {
    // Channel-shaped placeholders: a small icon square and one name bar each.
    // CLListSkeleton draws avatar-and-two-lines rows, which promised messages
    // rather than the single-line rows this list actually has.
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          for (var i = 0; i < 8; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  const CLSkeleton(width: 18, height: 18),
                  const SizedBox(width: 10),
                  // Alternating widths so it reads as a list of names rather
                  // than a stack of identical bars.
                  CLSkeleton(width: i.isEven ? 130 : 100, height: 12),
                ],
              ),
            ),
        ],
      );
    }

    // Refused, not empty. Says which it is and offers the one action that
    // changes it, rather than showing a channel list that cannot exist.
    if (!_hasAccess) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CLEmptyState(
                icon: Icons.lock_outline,
                iconBg: p.surface2,
                iconColor: p.text2,
                iconBorderColor: p.border,
                compact: true,
                title: 'You are not in this server',
                subtitle: 'Join to see its channels and take part in them.',
              ),
              const SizedBox(height: 18),
              CLBtn(
                label: _joining ? 'Joining…' : 'Join server',
                iconL: Icons.add,
                variant: CLBtnVariant.gold,
                size: CLBtnSize.md,
                onPressed: _joining ? null : _join,
              ),
            ],
          ),
        ),
      );
    }

    // ONE list, in the order the server returns - deliberately not split into
    // text and voice sections. Web renders them together and distinguishes them
    // by icon, which is what makes a channel list scannable: the sections would
    // reorder a list whose order the server owns.
    if (_channels.isEmpty) {
      // Web has a dedicated NoChannel screen for exactly this.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CLEmptyState(
                icon: Icons.tag,
                iconBg: p.surface2,
                iconColor: p.text2,
                iconBorderColor: p.border,
                compact: true,
                title: 'No channels yet',
                subtitle: _isAdmin
                    ? 'Create the first one and it shows up here.'
                    : 'This server has no channels yet.'
                        ' An admin can create the first one.',
              ),
              // The one case web cannot reach at all: its + only renders
              // alongside the Channels heading, which only renders when there
              // ARE channels - so a brand new server has no way to get its
              // first one. Here the empty state carries the action, the same
              // shape the Servers tab uses for Open Servers.
              if (_isAdmin) ...[
                const SizedBox(height: 18),
                CLBtn(
                  label: 'Create channel',
                  iconL: Icons.add,
                  variant: CLBtnVariant.gold,
                  size: CLBtnSize.md,
                  onPressed: _createChannel,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
        itemCount: _channels.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                children: [
                  const Expanded(child: _SectionLabel(label: 'Channels')),
                  // Admins only, like Manage server in the header menu. Web
                  // shows the + to everyone, but the server refuses a
                  // non-admin's create - so the entry would only ever fail for
                  // them, on the surface where the useful action (opening a
                  // channel) is every row below it.
                  if (_isAdmin)
                    CLIconBtn(icon: Icons.add, onPressed: _createChannel),
                ],
              ),
            );
          }
          final channel = _channels[index - 1];
          return _ChannelRow(
            channel: channel,
            // Live, not the count that came with the payload.
            inRoom: channel.isVoice
                ? VoiceRoomPresence.instance.countFor(channel.conversationId)
                : 0,
            onTap: () => _open(channel),
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Text(label,
        style: TextStyle(
            // sectionTitle: it heads rows that are themselves CLType.title, so
            // it has to sit above them to read as a heading at all.
            fontSize: CLType.sectionTitle,
            fontWeight: FontWeight.w700,
            color: p.text));
  }
}

class _ChannelRow extends StatelessWidget {
  final ServerChannel channel;

  /// How many are in the room NOW - from VoiceRoomPresence, so it moves without
  /// the list being refetched.
  final int inRoom;
  final VoidCallback onTap;

  const _ChannelRow({
    required this.channel,
    required this.onTap,
    this.inRoom = 0,
  });

  /// Web's exact matrix, from Channels.tsx:
  ///
  ///   voice + private  filled sound      voice + public  outline sound
  ///   text  + private  lock              text  + public  hashtag
  ///
  /// Privacy is part of the icon rather than a separate badge, which is what
  /// lets a long list be read at a glance.
  IconData get _icon {
    if (channel.isVoice) {
      return channel.isPrivate ? Icons.volume_up : Icons.volume_up_outlined;
    }
    return channel.isPrivate ? Icons.lock : Icons.tag;
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final unread = channel.unreadCount > 0;

    // No dimming any more: a voice channel opens now, so presenting it as
    // half-unavailable would be a lie about the one thing the opacity was for.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CLRadii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            Icon(_icon, size: 18, color: p.text2),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: CLType.title,
                      // Bold on unread, normal otherwise - web bolds the name
                      // and never shows a count, so neither does this.
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
                      color: p.text,
                    ),
                  ),
                  Text(
                    channel.isVoice
                        // Who is in there, which for a room is the only thing
                        // worth saying on the row - it has no last message.
                        ? (inRoom > 0
                            ? '$inRoom in this room'
                            : 'Voice channel')
                        : 'Text channel',
                    style: TextStyle(
                        fontSize: CLType.caption,
                        color: inRoom > 0 ? p.gold : p.text2),
                  ),
                ],
              ),
            ),
            // The COUNT, not just the bold name web settles for. A channel
            // list is where the number earns its pixels: it is how you pick
            // which channel to open, whereas a conversation list already
            // tells you through its preview line.
            //
            // Capped at 99+ so a long-neglected channel cannot widen the row
            // and squeeze the name out.
            // Web's own live-room indicator, on the same side as the unread
            // badge a text channel gets.
            if (inRoom > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.settings_voice, size: 16, color: p.gold),
              ),
            if (unread)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: CLBadge(
                  label: channel.unreadCount > 99
                      ? '99+'
                      : '${channel.unreadCount}',
                  // alert = FILLED pink with white text. The pink tone is a
                  // pale tint on pink text, which reads as a label; a count
                  // meant to be noticed needs the contrast.
                  tone: CLBadgeTone.alert,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The whole servers experience in one pushed screen: the rail on the left and
/// a pane that is either the directory or a server channel list - which is what
/// the screenshots show, and what web does with nested routes.
class ServerScreen extends StatefulWidget {
  /// Null opens on the directory. Set opens straight into that server.
  final String? serverId;
  final String? serverName;
  final String? serverProfile;

  const ServerScreen({
    super.key,
    this.serverId,
    this.serverName,
    this.serverProfile,
  });

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  List<RealmSummary> _mine = const [];

  late String? _serverId = widget.serverId;
  late String? _serverName = widget.serverName;
  late String? _serverProfile = widget.serverProfile;

  @override
  void initState() {
    super.initState();
    _loadMine();
    // Being removed from the server you are looking at - web's Channels.tsx
    // navigates to /servers on the same event.
    realmRemovals.addListener(_onRealmRemoval);
    // Joining one, from anywhere: this screen's own directory, another device,
    // or an admin adding you. Only the first of those used to move the rail,
    // and only because the directory pane calls back into _loadMine.
    realmMembershipChanges.addListener(_onMembershipChanged);
  }

  @override
  void dispose() {
    realmRemovals.removeListener(_onRealmRemoval);
    realmMembershipChanges.removeListener(_onMembershipChanged);
    super.dispose();
  }

  void _onMembershipChanged() {
    final change = realmMembershipChanges.value;
    if (!mounted || change == null) return;
    // Servers only, and only when it happened to ME - the same event goes to
    // everyone who stays in the realm so their member lists can move, and their
    // rail did not change.
    if (change.type != 'server') return;
    if (!change.involves(appStore.state.userAuth.user.entityId)) return;
    // Refetched rather than patched: the event carries an id, not the name and
    // photo the rail draws, so there is nothing to insert locally.
    _loadMine();
  }

  void _onRealmRemoval() {
    final removal = realmRemovals.value;
    if (!mounted || removal == null) return;
    // Losing a server you are not currently inside still empties one slot in
    // the rail. Dropped locally: the fact is already known, and a refetch would
    // leave it sitting there until the round trip lands.
    //
    // A channel removal ("group" type) is left to the channels list refetching -
    // channels are not in the rail.
    if (removal.realmId != _serverId) {
      if (_mine.any((server) => server.id == removal.realmId)) {
        setState(() => _mine =
            _mine.where((server) => server.id != removal.realmId).toList());
      }
      return;
    }

    // Anything pushed ON TOP of this screen is a room inside the server that
    // was just taken away - a channel conversation, its info screen - so it
    // goes too. Without this the user stays in a channel of a server they are
    // no longer in, with a composer that looks live and sends that fail.
    final own = ModalRoute.of(context);
    if (own != null && !own.isCurrent) {
      Navigator.of(context).popUntil((route) => route == own);
    }
    _onLeft(removal.realmId);
  }

  Future<void> _loadMine() async {
    final mine = await ProfileApi().getMyServersRequest();
    if (!mounted) return;
    setState(() => _mine = mine);
  }

  void _select(RealmProfile server) => setState(() {
        _serverId = server.id;
        _serverName = server.name;
        _serverProfile = server.profile;
      });

  void _showDirectory() => setState(() {
        _serverId = null;
        _serverName = null;
        _serverProfile = null;
      });

  /// After leaving OR being removed: drop it from the rail and land on the
  /// directory.
  ///
  /// The rail is patched locally rather than refetched, for the same reason a
  /// joined card flips locally - the answer is already known, and a refetch
  /// leaves the server you just left sitting in the rail until it returns.
  void _onLeft(String serverId) => setState(() {
        _mine = _mine.where((server) => server.id != serverId).toList();
        _serverId = null;
        _serverName = null;
        _serverProfile = null;
      });

  /// Back always lands on the Servers TAB, never one frame up the stack.
  ///
  /// go(), not pop(): this screen is reached from the tab, but the rail also
  /// moves between servers WITHOUT pushing, so the stack depth does not track
  /// how deep the user feels they are. Popping once could leave them on a
  /// conversation they opened from a channel, which is not "back" from here by
  /// any reading. One arrow, one destination.
  void _back() => context.go('/servers');

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return CLScreen(
      backgroundColor: p.bg,
      // SafeArea for the TOP specifically. This screen has no AppBar - the rail
      // carries its own back button, as the layout does - and CLScreen only
      // insets the bottom, so without this the rail and the server header run
      // up under the status bar.
      body: SafeArea(
        bottom: false,
        child: Row(
          children: [
            _ServerRail(
              servers: _mine,
              activeId: _serverId,
              onBack: _back,
              onHome: _showDirectory,
              onOpen: (server) => setState(() {
                _serverId = server.id;
                _serverName = server.name;
                _serverProfile = server.profile;
              }),
            ),
            // The 1px full-height divider that used to sit here is gone: it
            // ran straight past the rail's rounded corners. The rail draws its
            // own border now, which follows the radius.
            Expanded(
              child: _serverId == null
                  ? ServersDirectoryPane(
                      onOpenServer: _select,
                      // A newly created server has to appear in the rail too.
                      onServersChanged: _loadMine,
                    )
                  : ServerChannelsPane(
                      // Keyed so switching servers in the rail rebuilds the
                      // pane and refetches, instead of leaving the previous
                      // server channels on screen.
                      key: ValueKey(_serverId),
                      serverId: _serverId!,
                      serverName: _serverName,
                      serverProfile: _serverProfile,
                      onLeave: _onLeft,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The vertical rail. Back and all-servers are pinned; the servers scroll on
/// their own, because that list is unbounded in principle and must never be
/// what decides the rail's height - or push the way out of a server off screen.
class _ServerRail extends StatelessWidget {
  final List<RealmSummary> servers;
  final String? activeId;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final void Function(RealmSummary server) onOpen;

  const _ServerRail({
    required this.servers,
    required this.activeId,
    required this.onBack,
    required this.onHome,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Container(
      width: 60,
      // Rounded on the RIGHT only - the left edge is the screen edge, so
      // rounding it would just leave a sliver of the body showing through.
      // Reads as a half-stadium tucked against the side of the screen.
      //
      // decoration, not `color`: the two can't both be set on a Container.
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(CLRadii.lg),
          bottomRight: Radius.circular(CLRadii.lg),
        ),
        // Uniform Border.all, not a right-only BorderSide: BoxDecoration can
        // only paint a border around a borderRadius when every side matches,
        // and a one-sided border would go back to being the straight line this
        // replaced. The left side lands on the screen edge, where it isn't
        // visible anyway.
        border: Border.all(color: p.border),
      ),
      // Clips the scrolling server list to the rounded corners; without it the
      // avatars at the very top and bottom paint over them.
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const SizedBox(height: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onBack,
            tooltip: 'Back',
            // Gold: this whole surface is the servers accent, so its controls
            // use it rather than the app blue.
            icon: Icon(Icons.arrow_back, color: p.gold, size: 20),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onHome,
            tooltip: 'All servers',
            // Always gold. It was dimming to text3 whenever a server was open,
            // which read as "disabled" on the one control that takes you back
            // to the directory - the state it was signalling is already carried
            // by which avatar has the ring.
            icon: Icon(Icons.dns, color: p.gold, size: 20),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Divider(height: 1, color: p.border),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: servers.length,
              itemBuilder: (context, index) {
                final server = servers[index];
                // Both sides must be non-empty. When the Node payload was being
                // mis-parsed every id came back "" - and "" == "" meant EVERY
                // avatar drew the ring at once. The parse is fixed; this makes
                // the comparison unable to lie again.
                final active = server.id.isNotEmpty && server.id == activeId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Center(
                    child: InkWell(
                      onTap: () => onOpen(server),
                      borderRadius: BorderRadius.circular(CLRadii.pill),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            // Grey, not the accent: the ring is positional, not
                            // a status, so it stays quiet and lets gold mean
                            // actions.
                            color: active ? p.border2 : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        // No src when there is no photo, so CLAvatar draws the
                        // gradient and the server initials.
                        child: CLAvatar(
                          id: server.id,
                          name: server.name,
                          src: clCleanMediaSrc(server.profile),
                          size: 38,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Server info - webapp's ServerInfoModal, as a pushed screen.
///
/// A screen rather than a modal for the same reason the conversation info is
/// one: web's is a full-height panel, which on a phone is a screen wearing a
/// modal's clothes. And like that screen it is DISPLAY only - the actions live
/// in the header menu that opened it, not scattered through the list.
class ServerInfoScreen extends StatefulWidget {
  final String serverId;
  final String? serverName;
  final String? serverProfile;

  const ServerInfoScreen({
    super.key,
    required this.serverId,
    this.serverName,
    this.serverProfile,
  });

  @override
  State<ServerInfoScreen> createState() => _ServerInfoScreenState();
}

class _ServerInfoScreenState extends State<ServerInfoScreen> {
  final List<RealmPerson> _members = [];

  /// The server's own description. NOT on the channels payload web builds this
  /// screen from - ServerChannelsListInterface carries serverName, profile,
  /// is_admin, channels and usersWithInfo and nothing else, which is why web's
  /// ServerInfoModal shows no description at all. It lives on the Django realm,
  /// so it takes a second request.
  String? _description;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Both at once - the description is a display detail, and making the member
    // list wait for a serial second request would be paying for it twice.
    //
    // forManage: true is what lets a SERVER be looked up at all. It is not an
    // authorisation mode despite the name: it only switches the realm lookup
    // from `slug=` to `realm_id=`, and a server has no slug. Without it this
    // request 404s, which is the same wall the earlier is_admin attempt hit.
    final results = await Future.wait([
      // One page. This is a display screen, not the roster you manage - that is
      // Manage server, which pages, searches and can remove people. Paging here
      // would be building a second version of it.
      ProfileApi().getRealmMembersRequest(widget.serverId, pageSize: 50),
      ProfileApi().getRealmProfileRequest(widget.serverId, forManage: true),
    ]);
    if (!mounted) return;

    final page = results[0] as PagedResult<RealmPerson>;
    final realm = results[1] as RealmProfile?;
    setState(() {
      _members
        ..clear()
        ..addAll(page.results);
      _description = realm?.description;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return CLScreen(
      // surface, matching the conversation info screen: one continuous panel of
      // identity, with nothing on it needing a darker ground to sit against.
      backgroundColor: p.surface,
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            CLSpacing.contentGutter, 8, CLSpacing.contentGutter, 24),
        children: [
          Center(
            child: Column(
              children: [
                CLAvatar(
                    id: widget.serverId,
                    name: widget.serverName ?? '',
                    src: clCleanMediaSrc(widget.serverProfile),
                    size: 84,
                    // Squared, like a group tile: a server is a room, not a
                    // person.
                    cornerRadius: CLRadii.lg),
                const SizedBox(height: 10),
                Text(widget.serverName ?? 'Server',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: CLType.screenTitle,
                        fontWeight: FontWeight.w800,
                        color: p.text)),
                const SizedBox(height: 2),
                Text('Server',
                    style: TextStyle(fontSize: CLType.caption, color: p.text2)),
                // Under the identity block and above the members, because that
                // is the order you read it in: what this place is, then who is
                // in it. Not truncated - an info screen is where the whole
                // description belongs, unlike the directory card that clamps it.
                if (_loading)
                  // Shaped like the justified paragraph it stands in for: four
                  // full-width lines and a half line to end on, left aligned so
                  // the ragged edge is at the bottom right where a paragraph's
                  // is. It sits where the real text will, which is what stops
                  // the members heading below from jumping when it arrives.
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 12, not 9: the bars run the full column width, and at
                        // 9 that width made each one read as a tube rather than
                        // a line of text. 12 with a 6 gap is about the 13/1.35
                        // line box the real description occupies.
                        CLSkeleton(width: double.infinity, height: 12),
                        SizedBox(height: 6),
                        CLSkeleton(width: double.infinity, height: 12),
                        SizedBox(height: 6),
                        CLSkeleton(width: double.infinity, height: 12),
                        SizedBox(height: 6),
                        CLSkeleton(width: double.infinity, height: 12),
                        SizedBox(height: 6),
                        // A FRACTION, not a fixed width: the last line has to
                        // stay half the column on any screen, and a 140px bar
                        // is most of a narrow phone and a third of a wide one.
                        FractionallySizedBox(
                          widthFactor: 0.5,
                          child: CLSkeleton(width: double.infinity, height: 12),
                        ),
                      ],
                    ),
                  )
                else if ((_description ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  // Full width, so justify has something to justify against -
                  // the Column above centres its children, which would size a
                  // short description to its own text and make the alignment
                  // moot.
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      _description!.trim(),
                      textAlign: TextAlign.justify,
                      style: TextStyle(
                          fontSize: CLType.bodySm,
                          color: p.text2,
                          height: 1.35),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _loading
                ? 'Members'
                : _members.length == 1
                    ? '1 member'
                    : '${_members.length} members',
            style: TextStyle(
                fontSize: CLType.sectionTitle,
                fontWeight: FontWeight.w700,
                color: p.text),
          ),
          const SizedBox(height: 8),
          // The panel is drawn while loading too, with placeholder rows INSIDE
          // it. A bare CLListSkeleton in its place started 6px from the screen
          // edge with no panel around it, so the whole list jumped inwards and
          // grew a border when the members arrived.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              // surface2 on a surface background - a surface card here would
              // be an outline around nothing. Same call as the conversation
              // info screen's member panel.
              color: p.surface2,
              border: Border.all(color: p.border),
              borderRadius: BorderRadius.circular(CLRadii.md),
            ),
            child: _loading
                // 36 and the 6px vertical rhythm are _MemberRow's, so the bars
                // land where the names will.
                ? Column(
                    children: [
                      for (var i = 0; i < 5; i++)
                        const CLListRowSkeleton(
                            avatarSize: 36,
                            padding: EdgeInsets.symmetric(
                                vertical: 6, horizontal: 0)),
                    ],
                  )
                : _members.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: CLSectionEmpty(
                          icon: Icons.group_outlined,
                          title: 'No members listed',
                          subtitle: 'Nobody could be resolved for this server.',
                        ),
                      )
                    : Column(
                        children: [
                          for (final member in _members)
                            _MemberRow(member: member),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final RealmPerson member;
  const _MemberRow({required this.member});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final role = member.role;
    final meta = [
      if (member.handle.isNotEmpty) '@${member.handle}',
      if (role != null && role.isNotEmpty) role,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CLAvatar(
              id: member.entityId,
              name: member.displayName,
              src: clCleanMediaSrc(member.profile),
              size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                          member.displayName.isEmpty
                              ? 'Unknown'
                              : member.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: CLType.bodySm,
                              fontWeight: FontWeight.w600,
                              color: p.text)),
                    ),
                    if (member.isVerified) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.verified, size: 13, color: p.brand),
                    ],
                  ],
                ),
                if (meta.isNotEmpty)
                  Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: CLType.caption, color: p.text2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
