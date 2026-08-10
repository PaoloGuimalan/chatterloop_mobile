// A voice channel - webapp's VoiceChannel.tsx.
//
// The layout is the conversation screen's: a header with a back button, then the
// body. Where a text channel renders messages and a composer, this renders the
// call stage and its controls. Its OWN screen rather than a branch inside
// conversation_view, which stays untouched - a room and a thread share a frame,
// not an implementation.
//
// It is also not the /call/active route: that screen is built around a call that
// was placed or answered. Here you are simply in, the moment you walk in - web
// does the same by handing VoiceWindow a fabricated `type: "audio"` payload
// rather than going through its ringing flow.
//
// conversationType 'group' is load-bearing: every single-call watchdog in
// CallController - the 45s ringing cap, auto-end-when-alone, the 25s
// media-silence fallback - short-circuits on isGroup, and a room has to survive
// one person sitting in it.
//
// No ring, and no recipient list: nobody is being invited. Presence is announced
// by the controller's own notify-voice-join, which is what moves the "N in this
// room" label on the channel list.

import 'package:chatterloop_app/core/calls/call_controller.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/models/messages_models/conversation_info_model.dart';
import 'package:chatterloop_app/views/messages/conversation_info_view.dart';
import 'package:chatterloop_app/views/realm/realm_manage_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class VoiceChannelScreen extends StatefulWidget {
  /// The channel's groupID - its conversation id, which is the SFU's room key.
  final String conversationId;
  final String? channelName;
  final bool isPrivate;

  const VoiceChannelScreen({
    super.key,
    required this.conversationId,
    this.channelName,
    this.isPrivate = false,
  });

  @override
  State<VoiceChannelScreen> createState() => _VoiceChannelScreenState();
}

class _VoiceChannelScreenState extends State<VoiceChannelScreen> {
  final CallController _controller = CallController.instance;

  /// One renderer per remote VIDEO producer, plus one for the local camera.
  /// Created lazily as tracks appear and disposed with the screen - a renderer
  /// left open holds the texture and the camera with it.
  final Map<String, RTCVideoRenderer> _remote = {};
  final RTCVideoRenderer _local = RTCVideoRenderer();
  bool _localReady = false;
  MediaStream? _localStream;

  bool _joining = true;
  bool _joined = false;
  String? _error;

  /// The channel's own details - members, privacy, and whether YOU administer
  /// it. Fetched here rather than passed in because the channel ROW carries
  /// none of it: the list payload knows a channel's name, type and occupancy,
  /// and `is_admin` on that response is the SERVER's, not this channel's.
  ///
  /// The same request the conversation screen makes for a text channel, and it
  /// feeds the same info screen. Type "voice" is only used by the endpoint to
  /// branch single-vs-group; the realm's real kind is read from the database
  /// (routes/messages/index.js), so it cannot be spoofed into showing the wrong
  /// thing.
  ConversationInfoModel? _info;

  /// The channel refused to tell us about itself, so we never tried to join.
  ///
  /// A private channel you are not a member of is the case this is for: the
  /// details endpoint runs isRealmMember before it answers, and the media
  /// service runs the SAME check on join-room. Without this the screen would
  /// walk into the room, get turned away by the SFU, and report it as
  /// "Could not connect" - a transport failure, which is the wrong thing to
  /// tell someone who simply is not in the channel.
  ///
  /// The wording is the conversation screen's, and so is its hedge: a failed
  /// request cannot distinguish "not a member" from "no network", so the copy
  /// names the likely cause and leaves room for the other.
  bool _accessDenied = false;

  /// Guards the channel-leave flow against a second tap while its request is
  /// in flight - it ends in a pop, and firing it twice would remove you, fail,
  /// and then report the failure.
  bool _leavingChannel = false;

  /// Popped once, ever.
  ///
  /// Leave used to pop TWICE: _leave() awaits leaveCall(), which drives the
  /// engine to idle, which fires _onEngine, which pops - and then _leave popped
  /// again on the way back. Two pops walked past the channel list and out of the
  /// server screen entirely.
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onEngine);
    // Initialized up front, exactly as ActiveCallView does: a renderer created
    // lazily on first camera-on had nothing bound the frame the local track
    // appeared, which is why you could not see yourself.
    _local.initialize().then((_) {
      if (mounted) setState(() => _localReady = true);
    });
    _start();
  }

  /// Details first, THEN the room.
  ///
  /// Deliberately serial, at the cost of one round trip before any audio: the
  /// details endpoint is the access check (it runs isRealmMember for anything
  /// that is not a DM), so asking it first is what turns "you are not in this
  /// channel" into a plain statement instead of a connection failure after the
  /// SFU refuses the join. It is also the same order the conversation screen
  /// uses - resolve the place, then open it.
  Future<void> _start() async {
    final info = await ConversationsApi()
        .getConversationInfoModelRequest(widget.conversationId, 'voice');
    if (!mounted) return;
    if (info == null) {
      setState(() {
        _joining = false;
        _accessDenied = true;
      });
      return;
    }
    setState(() => _info = info);
    await _join();
  }

  @override
  void dispose() {
    _controller.removeListener(_onEngine);
    for (final renderer in _remote.values) {
      renderer.srcObject = null;
      renderer.dispose();
    }
    _local.dispose();
    super.dispose();
  }

  void _onEngine() {
    if (!mounted) return;
    if (_joined && _controller.status == CallEngineStatus.idle) {
      // The engine tore down - by Leave, by a transport closing, by anything.
      _popOnce();
      return;
    }
    _syncRenderers();
    setState(() {});
  }

  Future<void> _join() async {
    if (_controller.status != CallEngineStatus.idle) {
      setState(() {
        _joining = false;
        _error = _controller.conversationID == widget.conversationId
            ? 'You are already in this room.'
            : 'Leave your current call before joining a room.';
      });
      return;
    }

    final ok = await _controller.joinCall(
      conversationID: widget.conversationId,
      // See the header - this is what keeps the single-call watchdogs off.
      conversationType: 'group',
      callType: 'audio',
      isOutgoing: false,
      startCameraOff: true,
      // ALWAYS muted on the way in, unlike a call you placed or answered.
      //
      // A voice channel is a room you walk into, often just to see who is
      // there - and it can already be full of people mid-conversation. Joining
      // live is how you broadcast a room you are in, a keyboard, or half a
      // sentence to someone else, to a room that never agreed to be called.
      // Unmuting is one tap; taking back what was already transmitted is not.
      startMuted: true,
    );
    if (!mounted) return;
    _syncRenderers();
    setState(() {
      _joining = false;
      _joined = ok;
      _error = ok ? null : (_controller.lastError ?? 'Could not connect.');
    });
  }

  /// Attaches every video track that has arrived, and drops the renderers for
  /// producers that have gone. Called on every engine notification rather than
  /// during build, because initialize() is async and build must not be.
  Future<void> _syncRenderers() async {
    // Local camera - bound whenever the stream identity changes, the same
    // check ActiveCallView makes.
    if (_localReady && _controller.mediaStream != _localStream) {
      _localStream = _controller.mediaStream;
      _local.srcObject = _localStream;
    }

    // Remote video producers.
    final video = <String, ConsumerEntry>{};
    for (final entry in _controller.consumers.entries) {
      if (entry.value.kind == 'video') video[entry.key] = entry.value;
    }
    for (final producerId in _remote.keys.toList()) {
      if (!video.containsKey(producerId)) {
        final renderer = _remote.remove(producerId);
        renderer?.srcObject = null;
        renderer?.dispose();
      }
    }
    for (final entry in video.entries) {
      if (_remote.containsKey(entry.key)) continue;
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      if (!mounted) {
        renderer.dispose();
        return;
      }
      // Per-TRACK, not per-stream: mediasoup_client_flutter groups every
      // remote track from one peer into a single MediaStream keyed by the RTP
      // CNAME, so a peer's camera and screen-share consumers share one stream
      // object. Plain srcObject renders only its first video track, which is
      // how every tile for that peer ends up showing the camera. Lifted from
      // ActiveCallView, comment and fallback included.
      try {
        renderer.setSrcObject(
          stream: entry.value.consumer.stream,
          trackId: entry.value.consumer.track.id,
        );
      } catch (_) {
        renderer.srcObject = entry.value.consumer.stream;
      }
      _remote[entry.key] = renderer;
    }
    if (mounted) setState(() {});
  }

  /// Back to the channel list - ONE pop, and only if this screen is still the
  /// route on top. The engine's own teardown path also lands here, so both have
  /// to be safe to call and safe to call twice.
  void _popOnce() {
    if (_popped || !mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    _popped = true;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _leave() async {
    await _controller.leaveCall();
    _popOnce();
  }

  /// The channel's info screen - the SAME one a text channel opens, handed the
  /// model this screen already fetched. A voice channel is a realm with members
  /// like any other, and the screen already names the kind ("Voice room").
  void _openInfo() {
    final info = _info;
    if (info == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConversationInfoScreen(
        info: info,
        title: widget.channelName ?? 'Voice channel',
        conversationType: 'voice',
      ),
    ));
  }

  /// Leaving the CHANNEL, not the room - web's "Leave Channel", offered on its
  /// exact condition (`groupdetails.privacy`): private channels only. A public
  /// channel takes its membership from the server, so leaving one means
  /// nothing - the next fetch would put you straight back in it.
  ///
  /// Membership goes first and the room second. If the removal fails you are
  /// still sitting in the room you were in, which is the honest outcome;
  /// leaving the room first would drop you out of a channel you turned out to
  /// still be a member of.
  Future<void> _leaveChannel() async {
    if (_leavingChannel) return;
    final p = cl(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surface,
        title: Text('Leave channel?',
            style: TextStyle(color: p.text, fontSize: CLType.screenTitle)),
        content: Text(
          "You'll leave this room and lose access to the channel. An admin "
          "has to add you back to return.",
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

    setState(() => _leavingChannel = true);
    // The ENTITY id, despite the endpoint's field being `account_ids` - the
    // same call and the same trap as leaving a server.
    final ok = await ProfileApi().removeRealmMembersRequest(
        widget.conversationId, [appStore.state.userAuth.user.entityId]);
    if (!mounted) return;
    if (!ok) {
      setState(() => _leavingChannel = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not leave the channel. Please try again.')));
      return;
    }
    // The channel list refetches on its own: removed_user_notif is published
    // to the removed member, and this app's handler bumps messagesListSignals.
    await _leave();
  }

  PopupMenuItem<String> _menuItem(
      CLPalette p, String value, IconData icon, String label,
      {bool danger = false, bool enabled = true}) {
    final color = danger ? p.pink : p.text2;
    return PopupMenuItem(
      value: value,
      enabled: enabled,
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(
                color: danger ? p.pink : p.text, fontSize: CLType.body)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final others = _controller.joinedParticipants
        .where((participant) => participant.clientId != _controller.clientId)
        .toList();

    return CLScreen(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        // Three regions on the canvas - header, stage, controls - each its own
        // panel with the gutter between them. The rule that used to sit under
        // the header is gone: the gutter separates them now.
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            CLSpacing.canvasGutter,
            CLSpacing.canvasTop,
            CLSpacing.canvasGutter,
            CLSpacing.canvasGutter,
          ),
          child: Column(
            children: [
              _header(p, others.length + 1),
              const SizedBox(height: CLSpacing.canvasGutter),
              Expanded(child: _stage(p)),
              // No controls at all when you were never let in - there is no
              // room to mute, point a camera at, or leave. The header's back
              // arrow is the only thing this screen can honestly offer.
              if (!_accessDenied) ...[
                const SizedBox(height: CLSpacing.canvasGutter),
                _controls(p),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The conversation header's shape - back arrow, identity, count - so a room
  /// and a thread read as the same kind of place.
  Widget _header(CLPalette p, int total) {
    return CLPanel(
      padding: CLSpacing.headerPanelPadding.copyWith(left: 4),
      child: SizedBox(
        height: CLSpacing.headerPanelHeight - 12,
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 20, color: p.text2),
            ),
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              // Gold-tint disc, no outline: inside a panel the tint alone is
              // enough to seat the glyph, and the border was the hairline
              // language this redesign drops.
              decoration: BoxDecoration(
                color: p.goldSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                  widget.isPrivate ? Icons.volume_up : Icons.volume_up_outlined,
                  size: 18,
                  color: p.gold),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.channelName ?? 'Voice channel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: CLType.title,
                          fontWeight: FontWeight.bold,
                          color: p.text)),
                  Text(
                    _accessDenied
                        ? 'No access'
                        : _error != null
                            ? 'Not connected'
                            : _joining
                                ? 'Connecting...'
                                : total <= 1
                                    ? 'Only you'
                                    : '$total in this room',
                    style: TextStyle(fontSize: CLType.meta, color: p.text2),
                  ),
                ],
              ),
            ),
            // The same menu the channel list's header carries, and web's own
            // voice-channel menu: info, Manage for admins, Leave for a private
            // channel. Rendered while the details are still loading so the
            // header does not reflow when they land - Info is simply disabled
            // until it has something to show.
            //
            // Gone entirely once access is refused: every entry acts on a channel
            // this account has no standing in, and "Leave channel" in particular
            // would offer to drop a membership that is the very thing missing.
            if (!_accessDenied)
              PopupMenuButton<String>(
                tooltip: 'Options',
                color: p.surface,
                icon: Icon(Icons.info_outline, size: 20, color: p.text2),
                onSelected: (value) {
                  switch (value) {
                    case 'info':
                      _openInfo();
                    case 'manage':
                      openRealmManage(context, widget.conversationId);
                    case 'leave':
                      _leaveChannel();
                  }
                },
                itemBuilder: (context) => [
                  _menuItem(p, 'info', Icons.info_outline, 'Info',
                      enabled: _info != null),
                  // Admins only, as on the server menu: the server refuses a
                  // non-admin's edits, so the entry could only ever fail for them.
                  // This channel's own is_admin, not the server's - they are
                  // usually the same and the channel is the one being managed.
                  if (_info?.isAdmin ?? false)
                    _menuItem(p, 'manage', Icons.tune, 'Manage channel'),
                  // Private only - see _leaveChannel.
                  if (widget.isPrivate || (_info?.isPrivate ?? false))
                    _menuItem(p, 'leave', Icons.logout, 'Leave channel',
                        danger: true, enabled: !_leavingChannel),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _stage(CLPalette p) {
    // Word for word the conversation screen's, because it is the same fact
    // about the same kind of place - a private channel you are not in reads
    // identically whether it holds messages or voices.
    if (_accessDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A lock, not a warning triangle: this is about permission, and
              // an error glyph reads as "something broke, try again".
              Icon(Icons.lock_outline, size: 40, color: p.text3),
              const SizedBox(height: 10),
              Text('You do not have access to this voice channel',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: p.text,
                      fontWeight: FontWeight.w700,
                      fontSize: CLType.sectionTitle)),
              const SizedBox(height: 4),
              Text(
                  'It may be private, or you may no longer be a member. Check '
                  'your connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.text2, fontSize: CLType.bodySm)),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: CLEmptyState(
            icon: Icons.volume_off_outlined,
            iconBg: p.surface2,
            iconColor: p.text2,
            iconBorderColor: p.border,
            compact: true,
            title: 'Not connected',
            subtitle: _error!,
          ),
        ),
      );
    }

    // Never empty - your own tile is always in it, which is what an empty room
    // looks like. The header's "Only you" says the rest.
    final tiles = _buildTiles(p);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          CLSpacing.contentGutter - 4, 12, CLSpacing.contentGutter - 4, 12),
      child: _tileGrid(tiles),
    );
  }

  /// One tile per video SOURCE in the room - your own camera, PLUS every remote
  /// participant's camera AND screen-share (each is a separate mediasoup
  /// consumer, so each gets its own tile bound to its own track), PLUS a
  /// placeholder for anyone who has joined but has no live video yet.
  ///
  /// ActiveCallView's arrangement exactly, and for its reason: a room is N
  /// people, not a fixed pair, and one person's camera + screen are two
  /// distinct tiles. The old per-PARTICIPANT wrap could only ever show one
  /// video each, so a peer sharing their screen while their camera was on had
  /// one of the two silently dropped - and which one depended on consumer
  /// arrival order.
  List<Widget> _buildTiles(CLPalette p) {
    // Only consumers whose renderer is already bound - one appears a frame or
    // two after the consumer itself, since initialize() is async.
    final remoteVideo = _controller.consumers.entries
        .where((entry) =>
            entry.value.kind == 'video' && _remote.containsKey(entry.key))
        .toList();
    // Shared screens sit ABOVE the camera tiles - a screen-share is usually the
    // focus of the room, so it leads the grid, then our own camera, then
    // everyone else's.
    final screens =
        remoteVideo.where((entry) => entry.value.source == 'screen').toList();
    final cameras =
        remoteVideo.where((entry) => entry.value.source != 'screen').toList();

    final withVideo = <String>{};
    for (final entry in remoteVideo) {
      final owner = entry.value.ownerClientId;
      if (owner != null) withVideo.add(owner);
    }

    final tiles = <Widget>[
      for (final entry in screens) _remoteTile(p, entry),
      _selfTile(p),
      for (final entry in cameras) _remoteTile(p, entry),
    ];

    // Joined participants with no live video yet - a tile each, so the room
    // shows who is in it while they are still muted-and-camera-off.
    for (final participant in _controller.joinedParticipants) {
      if (participant.clientId == _controller.clientId) continue;
      if (withVideo.contains(participant.clientId)) continue;
      tiles.add(_waitingTile(p, participant));
    }

    return tiles;
  }

  /// "@username" + " - camera off" + " - muted", the suffix pattern and
  /// ordering ActiveCallView took from webapp's placeholder tiles.
  String _statusLabel(String name,
      {required bool cameraOff, required bool muted}) {
    final buffer = StringBuffer(name);
    if (cameraOff) buffer.write(" - camera off");
    if (muted) buffer.write(" - muted");
    return buffer.toString();
  }

  Widget _selfTile(CLPalette p) {
    final me = appStore.state.userAuth.user;
    // The local preview only exists while the camera is on - the tile falls
    // back to the avatar otherwise, rather than a black rectangle.
    final showVideo = !_controller.cameraOff && _localReady;
    return _tileFrame(
      p,
      key: const ValueKey('tile-self'),
      label: _statusLabel('You',
          cameraOff: _controller.cameraOff, muted: _controller.muted),
      isScreen: false,
      placeholder: CLAvatar(
          id: me.entityId,
          name: 'You',
          src: clCleanMediaSrc(me.activeAvatarSrc),
          size: 64),
      child: showVideo
          ? RTCVideoView(_local,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
          : null,
    );
  }

  Widget _remoteTile(CLPalette p, MapEntry<String, ConsumerEntry> entry) {
    final ownerId = entry.value.ownerClientId;
    final owner = ownerId != null
        ? _controller.joinedParticipants
            .where((participant) => participant.clientId == ownerId)
            .toList()
        : const <JoinedParticipant>[];
    final name = owner.isNotEmpty ? "@${owner.first.username}" : "Participant";
    final status =
        ownerId != null ? _controller.participantStatuses[ownerId] : null;
    final isScreen = entry.value.source == 'screen';
    final renderer = _remote[entry.key]!;
    final screenLabel = "$name - screen";
    final video = RTCVideoView(
      renderer,
      // A shared screen is usually a desktop aspect ratio - `contain` so
      // nothing is cropped; a camera fills its tile with `cover`.
      objectFit: isScreen
          ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
          : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
    return _tileFrame(
      p,
      // Keyed by producerId so each remote video keeps its OWN RTCVideoView
      // (and its own texture) as tiles are added, removed and reordered.
      key: ValueKey('tile-${entry.key}'),
      label: isScreen
          ? screenLabel
          : _statusLabel(name,
              cameraOff: status?.cameraOff ?? false,
              muted: status?.muted ?? false),
      isScreen: isScreen,
      // Shared screens: pinch-to-zoom in place, plus a corner button for a
      // fullscreen zoomable viewer to read fine detail with.
      onExpand:
          isScreen ? () => _openScreenFullscreen(renderer, screenLabel) : null,
      child: isScreen
          ? InteractiveViewer(
              panEnabled: true,
              scaleEnabled: true,
              minScale: 1.0,
              maxScale: 5.0,
              child: video,
            )
          : video,
    );
  }

  Widget _waitingTile(CLPalette p, JoinedParticipant participant) {
    final status = _controller.participantStatuses[participant.clientId];
    final name = participant.username.isNotEmpty
        ? participant.username
        : participant.clientId;
    return _tileFrame(
      p,
      key: ValueKey('tile-waiting-${participant.clientId}'),
      label: _statusLabel("@$name",
          cameraOff: status?.cameraOff ?? true, muted: status?.muted ?? false),
      isScreen: false,
      placeholder: CLAvatar(id: participant.clientId, name: name, size: 64),
      child: null,
    );
  }

  /// Fullscreen zoomable view of a shared screen. Binds a SECOND RTCVideoView
  /// to the same renderer - the renderer belongs to [_remote], so this route
  /// must never dispose it; popping tears down only this extra view.
  void _openScreenFullscreen(RTCVideoRenderer renderer, String label) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    panEnabled: true,
                    scaleEnabled: true,
                    minScale: 1.0,
                    maxScale: 6.0,
                    child: RTCVideoView(
                      renderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  left: 4,
                  right: 4,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: CLType.bodySm),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Common tile chrome - the room's own card (surface, border, md radius, as
  /// the tiles here always had), the video or an avatar placeholder, a
  /// bottom-left label chip, and a fullscreen button on screen tiles.
  Widget _tileFrame(
    CLPalette p, {
    Key? key,
    required String label,
    required bool isScreen,
    VoidCallback? onExpand,
    Widget? placeholder,
    Widget? child,
  }) {
    // Each participant is their own floating panel. No outline: the surface
    // fill and its elevation against the canvas are enough separation, and a
    // gold ring on every tile read as a state - "live", "speaking" - that it
    // never actually tracked.
    return Container(
      key: key,
      margin: const EdgeInsets.all(4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(CLRadii.panel),
        boxShadow: p.panelShadow,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child ??
              Center(
                child:
                    placeholder ?? Icon(Icons.person, color: p.text3, size: 40),
              ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  // Its own contrast, so the label reads the same over a
                  // camera, a shared screen and a plain avatar tile.
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontSize: CLType.meta),
                ),
              ),
            ),
          ),
          if (isScreen)
            Positioned(
              top: 6,
              right: 6,
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onExpand,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child:
                        Icon(Icons.fullscreen, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Responsive grid: FILLS the stage for a handful of tiles (1 = full,
  /// 2 = stacked, 3-4 = 2x2), then switches to a scrollable 2-column grid once
  /// there are more than comfortably fit. Works for any occupancy without
  /// hardcoding a case - which is the whole point in a room people walk in and
  /// out of.
  Widget _tileGrid(List<Widget> tiles) {
    final n = tiles.length;
    if (n == 1) return tiles.first;
    if (n <= 4) {
      final cols = n == 2 ? 1 : 2; // two tiles stack vertically on a phone
      final rows = (n / cols).ceil();
      return Column(
        children: [
          for (var r = 0; r < rows; r++)
            Expanded(
              child: Row(
                children: [
                  // Only emit an Expanded for cells that actually have a tile -
                  // so a row holding a single tile (the 3rd of three) stretches
                  // to the FULL width instead of leaving a 50% gap beside it.
                  for (var c = 0; c < cols; c++)
                    if (r * cols + c < n) Expanded(child: tiles[r * cols + c]),
                ],
              ),
            ),
        ],
      );
    }
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 3 / 4,
      children: tiles,
    );
  }

  Widget _controls(CLPalette p) {
    final disabled = _joining || _error != null;
    // The call controls are their own panel at the foot of the canvas, the
    // same way the tab bar is on a tab screen - the row of round targets is
    // the panel's whole content.
    return CLPanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Control(
            icon: _controller.muted ? Icons.mic_off : Icons.mic,
            label: _controller.muted ? 'Unmute' : 'Mute',
            color: _controller.muted ? p.pink : p.text,
            background: _controller.muted ? p.pinkSoft : p.surface2,
            onPressed: disabled ? null : _controller.toggleMic,
          ),
          const SizedBox(width: 12),
          _Control(
            icon: _controller.cameraOff ? Icons.videocam_off : Icons.videocam,
            label: 'Camera',
            color: _controller.cameraOff ? p.text : p.gold,
            background: _controller.cameraOff ? p.surface2 : p.goldSoft,
            onPressed: disabled
                ? null
                : () async {
                    await _controller.toggleCamera();
                    await _syncRenderers();
                  },
          ),
          const SizedBox(width: 12),
          _Control(
            icon: _controller.speakerOn ? Icons.volume_up : Icons.hearing,
            label: _controller.speakerOn ? 'Speaker' : 'Earpiece',
            color: _controller.speakerOn ? p.gold : p.text,
            background: _controller.speakerOn ? p.goldSoft : p.surface2,
            onPressed: disabled ? null : _controller.toggleSpeaker,
          ),
          const SizedBox(width: 12),
          _Control(
            icon: Icons.call_end,
            label: 'Leave',
            color: Colors.white,
            background: p.pink,
            onPressed: _leave,
          ),
        ],
      ),
    );
  }
}

class _Control extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color background;
  final VoidCallback? onPressed;

  const _Control({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Column(
        children: [
          InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(CLRadii.pill),
            child: Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration:
                  BoxDecoration(color: background, shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 23),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: CLType.meta, color: p.text2)),
        ],
      ),
    );
  }
}
