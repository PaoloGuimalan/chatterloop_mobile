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
    _join();
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

  /// The video renderer belonging to a participant, if they are sending one.
  RTCVideoRenderer? _rendererFor(String clientId) {
    for (final entry in _controller.consumers.entries) {
      if (entry.value.kind != 'video') continue;
      if (entry.value.ownerClientId == clientId) return _remote[entry.key];
    }
    return null;
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
        child: Column(
          children: [
            _header(p, others.length + 1),
            Divider(height: 1, color: p.border),
            Expanded(child: _stage(p, others)),
            _controls(p),
          ],
        ),
      ),
    );
  }

  /// The conversation header's shape - back arrow, identity, count - so a room
  /// and a thread read as the same kind of place.
  Widget _header(CLPalette p, int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
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
            decoration: BoxDecoration(
              color: p.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: p.border),
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
                  _error != null
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
        ],
      ),
    );
  }

  Widget _stage(CLPalette p, List<JoinedParticipant> others) {
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

    final me = appStore.state.userAuth.user;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          CLSpacing.contentGutter, 16, CLSpacing.contentGutter, 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: [
          _Tile(
            name: 'You',
            seed: me.entityId,
            src: me.activeAvatarSrc,
            muted: _controller.muted,
            connecting: _joining,
            // The local preview only exists while the camera is on - the tile
            // falls back to the avatar otherwise, rather than a black rectangle.
            renderer: _controller.cameraOff || !_localReady ? null : _local,
            mirror: true,
          ),
          for (final participant in others)
            _Tile(
              name: participant.username,
              seed: participant.clientId,
              muted: _controller
                      .participantStatuses[participant.clientId]?.muted ??
                  false,
              renderer: _rendererFor(participant.clientId),
            ),
        ],
      ),
    );
  }

  Widget _controls(CLPalette p) {
    final disabled = _joining || _error != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
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

/// One participant - their video if they are sending it, their avatar if not.
class _Tile extends StatelessWidget {
  final String name;
  final String seed;
  final String? src;
  final bool muted;
  final bool connecting;
  final bool mirror;
  final RTCVideoRenderer? renderer;

  const _Tile({
    required this.name,
    required this.seed,
    required this.muted,
    this.src,
    this.connecting = false,
    this.mirror = false,
    this.renderer,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final hasVideo = renderer != null && renderer!.srcObject != null;

    return Container(
      width: 150,
      height: 168,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: connecting ? p.border : p.gold, width: 1.5),
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasVideo)
            RTCVideoView(renderer!,
                mirror: mirror,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
          else
            Center(
              child: CLAvatar(
                  id: seed, name: name, src: clCleanMediaSrc(src), size: 64),
            ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Row(
              children: [
                if (muted) ...[
                  Icon(Icons.mic_off, size: 14, color: p.pink),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: CLType.caption,
                          fontWeight: FontWeight.w600,
                          // Over video the label needs its own contrast.
                          color: hasVideo ? Colors.white : p.text,
                          shadows:
                              hasVideo ? const [Shadow(blurRadius: 4)] : null)),
                ),
              ],
            ),
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
