// Full-screen "in a call" UI. Audio-only calls keep a centered avatar +
// status layout (a native-mobile equivalent of webapp's always-tiled
// window, confirmed as the right call for a phone - see the design
// decision below); as soon as there's any video to show, it switches to
// a tile-based layout that reuses webapp's actual visual language:
// #3D4043 tile backgrounds, the exact "You"/"@username" + " • muted" +
// " • camera off" status-suffix pattern from CallWindow.tsx, and the
// control bar's button shapes/colors (rounded-rect not circle, #888 for
// the "off" state, red end-call). What's deliberately NOT copied is
// webapp's actual page layout - it's a small floating/draggable window
// over the rest of the app (multi-call desktop UX has no mobile
// equivalent), confirmed out of scope; a phone call screen should still
// be full-screen like a native phone app.
//
// Rebuilds off CallController.instance directly via ListenableBuilder
// rather than owning any call-engine state itself, matching the mobile
// calling plan's CallController design.

import 'package:chatterloop_app/core/calls/call_controller.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/call_api.dart';
import 'package:chatterloop_app/models/call_models/call_signed_payloads_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

const _kCallBg = Color(0xFF14161A);

class ActiveCallView extends StatefulWidget {
  const ActiveCallView({super.key});

  @override
  State<ActiveCallView> createState() => _ActiveCallViewState();
}

class _ActiveCallViewState extends State<ActiveCallView> {
  bool _endingOrGone = false;
  bool _hadRemoteParticipant = false;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _localRendererReady = false;
  MediaStream? _localRendererStream;

  // Keyed by producerId, mirroring CallController.consumers - one renderer
  // per remote video consumer. Generalizes past 1:1 for free (M8's group
  // tiles are the same map, just more entries), even though this milestone
  // only ever has one.
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize().then((_) {
      if (mounted) setState(() => _localRendererReady = true);
    });
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    for (final renderer in _remoteRenderers.values) {
      renderer.dispose();
    }
    super.dispose();
  }

  /// Keeps renderers in sync with CallController's live state - called
  /// from the ListenableBuilder below on every rebuild, but only ever
  /// does real work (async renderer init/dispose) when something actually
  /// changed, guarded by identity/key-set checks so it's a no-op the rest
  /// of the time.
  void _syncRenderers(CallController controller) {
    if (_localRendererReady && controller.mediaStream != _localRendererStream) {
      _localRendererStream = controller.mediaStream;
      _localRenderer.srcObject = _localRendererStream;
    }

    final videoConsumers = controller.consumers.entries
        .where((e) => e.value.kind == 'video')
        .toList();
    final liveIds = videoConsumers.map((e) => e.key).toSet();

    for (final entry in videoConsumers) {
      if (_remoteRenderers.containsKey(entry.key)) continue;
      final renderer = RTCVideoRenderer();
      renderer.initialize().then((_) async {
        if (!mounted) {
          renderer.dispose();
          return;
        }
        // CRUCIAL: bind to this consumer's SPECIFIC track, not just its
        // stream. mediasoup_client_flutter groups every remote track from
        // the same peer endpoint into ONE MediaStream keyed by the RTP
        // CNAME (unified_plan.dart receive(): streamId = rtcp.cname), and a
        // browser uses a single CNAME for ALL its producers - so a peer's
        // camera AND screen-share consumers share the exact same MediaStream
        // object, which then holds both video tracks. Plain
        // `srcObject = stream` renders only the FIRST video track, so every
        // tile for that peer shows the camera (the screen-share bug). Passing
        // the trackId renders THIS consumer's track specifically (Android:
        // render.setStream(stream, trackId, ownerTag)), which is how the
        // webapp keeps camera and screen distinct.
        try {
          await renderer.setSrcObject(
            stream: entry.value.consumer.stream,
            trackId: entry.value.consumer.track.id,
          );
        } catch (_) {
          if (!mounted) {
            renderer.dispose();
            return;
          }
          // Fallback for any renderer that rejects a per-track bind.
          renderer.srcObject = entry.value.consumer.stream;
        }
        if (!mounted) {
          renderer.dispose();
          return;
        }
        setState(() => _remoteRenderers[entry.key] = renderer);
      });
    }

    final staleIds =
        _remoteRenderers.keys.where((id) => !liveIds.contains(id)).toList();
    if (staleIds.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          for (final id in staleIds) {
            _remoteRenderers.remove(id)?.dispose();
          }
        });
      });
    }
  }

  void _closeCallScreen() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushNamedAndRemoveUntil('/messages', (route) => false);
    }
  }

  Future<void> _endCall() async {
    if (_endingOrGone) return;
    setState(() => _endingOrGone = true);

    final current = appStore.state.currentCall;
    // Only the caller ever notifies the other side explicitly (matches
    // webapp's CallWindow.tsx isCaller gate) - a callee hanging up just
    // leaves the mediasoup room below, surfacing to the caller as an
    // ordinary participant-left roster event, nothing more.
    if (current != null &&
        current.isOutgoing &&
        current.recepients.isNotEmpty) {
      CallApi().endCallRequest(IEndCallRequest(
        conversationID: current.conversationID,
        conversationType: current.conversationType,
        recepients: current.recepients,
      ));
    }

    // leaveCall() clears the Redux call state AND navigates off this
    // screen (see CallController._navigateAwayFromCall) - no need to
    // duplicate either here, which would double-pop.
    await CallController.instance.leaveCall();

    if (!mounted) return;
    _closeCallScreen();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back press triggers the same hangup flow as the end-call button,
      // rather than either silently leaving the call running in the
      // background (canPop: true with no side effect) or permanently
      // trapping the user on this screen if the automatic idle-detection
      // below ever has a gap for any reason (confirmed on a real device:
      // Android's own back-key handling reported the press as
      // "intercepted by the app" with no visible effect, while the call
      // was actually already stuck).
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!_endingOrGone) _endCall();
      },
      child: ListenableBuilder(
        listenable: CallController.instance,
        builder: (context, _) {
          final controller = CallController.instance;
          _syncRenderers(controller);

          // Navigation away when the call ends is now driven centrally by
          // CallController.leaveCall() (via the global router), so every
          // end path - the button, callreject, transport-close, the
          // single-call auto-end, the media watchdog - leaves this screen
          // reliably without depending on this widget being the mounted,
          // rebuilding one at the instant status flips to idle (which was
          // unreliable for the auto-end path). Nothing to do here.

          final connecting = controller.status == CallEngineStatus.joining;
          final statusText = connecting
              ? "Connecting…"
              : controller.joinedParticipants.isEmpty
                  ? "Ringing…"
                  : "Connected";

          final hasAnyVideo =
              !controller.cameraOff || _remoteRenderers.isNotEmpty;

          final hasRemote = controller.joinedParticipants.isNotEmpty;
          if (hasRemote) _hadRemoteParticipant = true;

          final shouldAutoCloseSingle = !controller.isGroup &&
              _hadRemoteParticipant &&
              controller.joinedParticipants.isEmpty &&
              controller.status != CallEngineStatus.joining;

          if (shouldAutoCloseSingle && !_endingOrGone) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted || _endingOrGone) return;
              final navigator = Navigator.of(context);

              setState(() => _endingOrGone = true);
              await controller.leaveCall();

              if (!mounted) return;
              if (navigator.canPop()) navigator.pop();
            });
          }

          return Scaffold(
            backgroundColor: _kCallBg,
            body: SafeArea(
              child: hasAnyVideo
                  ? _buildVideoLayout(controller, statusText)
                  : _buildAudioLayout(controller, statusText),
            ),
          );
        },
      ),
    );
  }

  /// "@username" + " • muted" + " • camera off" - the EXACT suffix text
  /// and ordering from CallWindow.tsx's placeholder tiles (camera-off
  /// suffix always precedes muted).
  String _statusLabel(String name,
      {required bool cameraOff, required bool muted}) {
    final buffer = StringBuffer(name);
    if (cameraOff) buffer.write(" • camera off");
    if (muted) buffer.write(" • muted");
    return buffer.toString();
  }

  Widget _buildAudioLayout(CallController controller, String statusText) {
    return Column(
      children: [
        const Spacer(flex: 2),
        const CircleAvatar(
          radius: 56,
          backgroundColor: CLColors.brand300,
          child: Icon(Icons.person, color: Colors.white, size: 48),
        ),
        const SizedBox(height: 20),
        Text(
          controller.isGroup ? "Group call" : "Call",
          style: const TextStyle(
              color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(statusText,
            style: const TextStyle(color: Colors.white70, fontSize: 15)),
        if (controller.joinedParticipants.isNotEmpty) ...[
          const SizedBox(height: 24),
          ...controller.joinedParticipants.map((p) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  p.username.isNotEmpty ? p.username : p.clientId,
                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                ),
              )),
        ],
        const Spacer(flex: 3),
        _buildControls(controller),
      ],
    );
  }

  Widget _buildVideoLayout(CallController controller, String statusText) {
    final tiles = _buildTiles(controller);
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            // Leave room for the floating control bar so the bottom row of
            // tiles isn't hidden behind it.
            padding: const EdgeInsets.only(bottom: 92),
            child: tiles.isEmpty
                ? Center(
                    child: Text(statusText,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 15)))
                : _tileGrid(tiles),
          ),
        ),
        if (controller.videoProduceFailed) _buildVideoErrorBanner(controller),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.only(bottom: 24, top: 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54],
              ),
            ),
            child: _buildControls(controller),
          ),
        ),
      ],
    );
  }

  /// One tile per video SOURCE in the call - your own camera, PLUS every
  /// remote participant's camera AND screen-share (each is a separate
  /// mediasoup consumer, so each gets its own tile bound to its own
  /// stream), PLUS a placeholder for anyone who's joined but has no live
  /// video yet. This is what makes the layout work for N participants and
  /// for screen-share (one person's camera + screen = two distinct tiles),
  /// instead of assuming a single remote. Because each remote tile binds
  /// to its OWN consumer.stream, the screen tile shows the screen and the
  /// camera tile shows the camera - they can no longer be confused.
  List<Widget> _buildTiles(CallController controller) {
    // Remote video consumers - camera and/or screen, one tile each.
    final remoteVideo = controller.consumers.entries
        .where((e) =>
            e.value.kind == 'video' && _remoteRenderers.containsKey(e.key))
        .toList();
    // Shared screens sit ABOVE the camera tiles - a screen-share is usually
    // the focus of the call, so it leads the grid, then our own camera, then
    // everyone else's cameras.
    final screens =
        remoteVideo.where((e) => e.value.source == 'screen').toList();
    final cameras =
        remoteVideo.where((e) => e.value.source != 'screen').toList();

    final withVideo = <String>{};
    for (final e in remoteVideo) {
      final owner = e.value.ownerClientId;
      if (owner != null) withVideo.add(owner);
    }

    final tiles = <Widget>[
      for (final entry in screens) _remoteTile(controller, entry),
      _selfTile(controller),
      for (final entry in cameras) _remoteTile(controller, entry),
    ];

    // Joined participants with no live video yet - placeholder tiles so
    // the grid still shows them (waiting / camera-off).
    for (final p in controller.joinedParticipants) {
      if (p.clientId == controller.clientId) continue;
      if (withVideo.contains(p.clientId)) continue;
      tiles.add(_waitingTile(controller, p));
    }

    return tiles;
  }

  Widget _selfTile(CallController controller) {
    final showVideo = !controller.cameraOff && _localRendererReady;
    return _tileFrame(
      key: const ValueKey('tile-self'),
      label: _statusLabel("You",
          cameraOff: controller.cameraOff, muted: controller.muted),
      isScreen: false,
      child: showVideo
          ? RTCVideoView(_localRenderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
          : null,
    );
  }

  Widget _remoteTile(
      CallController controller, MapEntry<String, ConsumerEntry> entry) {
    final ownerId = entry.value.ownerClientId;
    final owner = ownerId != null
        ? controller.joinedParticipants
            .where((p) => p.clientId == ownerId)
            .toList()
        : const <JoinedParticipant>[];
    final name = owner.isNotEmpty ? "@${owner.first.username}" : "Participant";
    final status =
        ownerId != null ? controller.participantStatuses[ownerId] : null;
    final isScreen = entry.value.source == 'screen';
    final renderer = _remoteRenderers[entry.key]!;
    final screenLabel = "$name • screen";
    final video = RTCVideoView(
      renderer,
      // A shared screen is usually a desktop aspect ratio - `contain` so
      // nothing is cropped; a camera fills its tile with `cover`.
      objectFit: isScreen
          ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
          : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
    return _tileFrame(
      // Keyed by producerId so each remote video keeps its OWN RTCVideoView
      // (and its own texture) even as tiles are added/removed/reordered.
      key: ValueKey('tile-${entry.key}'),
      label: isScreen
          ? screenLabel
          : _statusLabel(name,
              cameraOff: status?.cameraOff ?? false,
              muted: status?.muted ?? false),
      isScreen: isScreen,
      // Shared screens: pinch-to-zoom in place, plus a corner button to open
      // a fullscreen zoomable viewer for reading fine detail.
      onExpand: isScreen ? () => _openScreenFullscreen(renderer, screenLabel) : null,
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

  /// Fullscreen zoomable view of a shared screen. Binds a second
  /// RTCVideoView to the SAME renderer (the tile keeps its own) - the
  /// renderer is owned by _remoteRenderers, so this view must never dispose
  /// it; popping the route just tears down this extra view.
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
                              color: Colors.white70, fontSize: 13),
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

  Widget _waitingTile(CallController controller, JoinedParticipant p) {
    final status = controller.participantStatuses[p.clientId];
    return _tileFrame(
      key: ValueKey('tile-waiting-${p.clientId}'),
      label: _statusLabel(
        "@${p.username.isNotEmpty ? p.username : p.clientId}",
        cameraOff: status?.cameraOff ?? true,
        muted: status?.muted ?? false,
      ),
      isScreen: false,
      child: null,
    );
  }

  /// Common tile chrome - webapp's #3D4043 rounded card, the video (or a
  /// person placeholder when there's none), a bottom-left label chip, and
  /// a screen-share badge in the corner for screen tiles.
  Widget _tileFrame(
      {Key? key,
      required String label,
      required bool isScreen,
      VoidCallback? onExpand,
      Widget? child}) {
    return Container(
      key: key,
      margin: const EdgeInsets.all(4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CLColors.callTile,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child ??
              const Center(
                child: Icon(Icons.person, color: Colors.white54, size: 40),
              ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
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
                    child: Icon(Icons.fullscreen, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Responsive grid: FILLS the screen for a handful of tiles (1 = full,
  /// 2 = stacked, 3-4 = 2x2), then switches to a scrollable 2-column grid
  /// once there are more than comfortably fit. Works for any participant
  /// count without hardcoding the 1:1 case.
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
                  // Only emit an Expanded for cells that actually have a
                  // tile - so a row holding a single tile (e.g. the 3rd tile
                  // of three) stretches to the FULL width instead of leaving
                  // a 50% gap beside it.
                  for (var c = 0; c < cols; c++)
                    if (r * cols + c < n)
                      Expanded(child: tiles[r * cols + c]),
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

  Widget _buildVideoErrorBanner(CallController controller) {
    return Positioned(
      top: 16,
      left: 16,
      right: 146, // stay clear of the local preview PiP
      child: Material(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.videocam_off, color: CLColors.callEnd, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text("Video couldn't connect",
                    style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
              TextButton(
                onPressed: () => controller.retryVideo(),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text("Retry",
                    style: TextStyle(
                        color: CLColors.brand300,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls(CallController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CallControlButton(
            icon: controller.muted ? Icons.mic_off : Icons.mic,
            off: controller.muted,
            onPressed:
                controller.isActive ? () => controller.toggleMic() : null,
          ),
          _CallControlButton(
            icon: controller.cameraOff ? Icons.videocam_off : Icons.videocam,
            off: controller.cameraOff,
            onPressed:
                controller.isActive ? () => controller.toggleCamera() : null,
          ),
          if (!controller.cameraOff)
            _CallControlButton(
              icon: Icons.cameraswitch,
              off: false,
              onPressed:
                  controller.isActive ? () => controller.switchCamera() : null,
            ),
          _CallControlButton(
            icon: controller.speakerOn ? Icons.volume_up : Icons.hearing,
            off: !controller.speakerOn,
            onPressed:
                controller.isActive ? () => controller.toggleSpeaker() : null,
          ),
          Material(
            color: CLColors.callEnd,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _endingOrGone ? null : _endCall,
              child: const Padding(
                padding: EdgeInsets.all(18),
                child: Icon(Icons.call_end, color: Colors.white, size: 30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded-rectangle (not a full circle) pill, matching webapp's
/// .btn_call_controls exactly: default state is a plain white surface,
/// the "off" state (muted / camera off) turns webapp's exact #888 gray
/// (.btn_call_controls_enable) - counter-intuitively named in webapp's own
/// CSS (the class is applied when the feature is OFF, not when it's
/// "enabled"), kept here as a plain `off` boolean instead of reproducing
/// that naming.
class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final bool off;
  final VoidCallback? onPressed;

  const _CallControlButton(
      {required this.icon, required this.off, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: off ? CLColors.callControlOff : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Icon(icon,
              color: off ? Colors.white : const Color(0xFF14161A), size: 22),
        ),
      ),
    );
  }
}
