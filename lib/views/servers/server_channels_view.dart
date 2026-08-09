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
// NOT here: creating channels (web's CreateChannelModal, 378 lines) and voice
// channels. Voice is listed but not enterable - it needs the mediasoup stack,
// which is the unmaintained dependency we already flagged, so offering a room
// that cannot be joined would be worse than saying so.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/utils/sse_events.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/views/realm/realm_manage_view.dart';
import 'package:chatterloop_app/views/servers/servers_view.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ServerChannelsPane extends StatefulWidget {
  final String serverId;

  /// Passed through from the directory row so the header has a name before the
  /// channel request lands - the same reason the conversation screen takes its
  /// title from the row that opened it.
  final String? serverName;
  final String? serverProfile;

  const ServerChannelsPane({
    super.key,
    required this.serverId,
    this.serverName,
    this.serverProfile,
  });

  @override
  State<ServerChannelsPane> createState() => _ServerChannelsPaneState();
}

class _ServerChannelsPaneState extends State<ServerChannelsPane> {
  List<ServerChannel> _channels = const [];
  bool _loading = true;

  /// Straight off the channels payload - see getServerChannelsRequest. Web reads
  /// `serverdetails.is_admin` from the same object, and two earlier attempts to
  /// derive it elsewhere were both wrong: the realm-profile route cannot resolve
  /// a server id, and my own member row does not say "admin" for an owner.
  bool _isAdmin = false;

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
  }

  @override
  void dispose() {
    messagesListSignals.removeListener(_onMessagesSignal);
    super.dispose();
  }

  void _onMessagesSignal() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final result = await ProfileApi().getServerChannelsRequest(widget.serverId);
    if (!mounted) return;
    setState(() {
      _channels = result.channels;
      _isAdmin = result.isAdmin;
      _loading = false;
    });
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

    final ok = await ProfileApi().removeRealmMembersRequest(
        widget.serverId, [appStore.state.userAuth.user.entityId]);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not leave. Please try again.')));
      return;
    }
    // Out of the server entirely - staying on a channel list you are no longer
    // a member of shows rooms you cannot open.
    context.go('/servers');
  }

  void _open(ServerChannel channel) {
    if (channel.isVoice) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Voice channels are not available on mobile yet.')));
      return;
    }
    if (channel.conversationId.isEmpty) return;
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

    // ONE list, in the order the server returns - deliberately not split into
    // text and voice sections. Web renders them together and distinguishes them
    // by icon, which is what makes a channel list scannable: the sections would
    // reorder a list whose order the server owns.
    if (_channels.isEmpty) {
      // Web has a dedicated NoChannel screen for exactly this.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: CLEmptyState(
            icon: Icons.tag,
            iconBg: p.surface2,
            iconColor: p.text2,
            iconBorderColor: p.border,
            compact: true,
            title: 'No channels yet',
            subtitle: 'This server has no channels.'
                ' They can be created from the web app.',
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
                  CLIconBtn(
                    icon: Icons.add,
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Creating channels is not available on mobile yet.')),
                    ),
                  ),
                ],
              ),
            );
          }
          final channel = _channels[index - 1];
          return _ChannelRow(channel: channel, onTap: () => _open(channel));
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
  final VoidCallback onTap;

  const _ChannelRow({required this.channel, required this.onTap});

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

    return Opacity(
      // Voice reads as unavailable rather than looking like a channel that
      // opens - it needs the media stack this app does not have yet.
      opacity: channel.isVoice ? 0.6 : 1,
      child: InkWell(
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
                      channel.isVoice ? 'Voice channel' : 'Text channel',
                      style:
                          TextStyle(fontSize: CLType.caption, color: p.text2),
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
            Container(width: 1, color: p.border),
            Expanded(
              child: _serverId == null
                  ? ServersDirectoryPane(onOpenServer: _select)
                  : ServerChannelsPane(
                      // Keyed so switching servers in the rail rebuilds the
                      // pane and refetches, instead of leaving the previous
                      // server channels on screen.
                      key: ValueKey(_serverId),
                      serverId: _serverId!,
                      serverName: _serverName,
                      serverProfile: _serverProfile,
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
      color: p.surface,
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // One page. This is a display screen, not the roster you manage - that is
    // Manage server, which pages, searches and can remove people. Paging here
    // would be building a second version of it.
    final result = await ProfileApi()
        .getRealmMembersRequest(widget.serverId, pageSize: 50);
    if (!mounted) return;
    setState(() {
      _members
        ..clear()
        ..addAll(result.results);
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
          if (_loading)
            const CLListSkeleton()
          else
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
              child: _members.isEmpty
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
