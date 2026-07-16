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
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/call_api.dart';
import 'package:chatterloop_app/models/call_models/call_signed_payloads_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';

const _kCallBg = Color(0xFF14161A);

class ActiveCallView extends StatefulWidget {
  const ActiveCallView({super.key});

  @override
  State<ActiveCallView> createState() => _ActiveCallViewState();
}

class _ActiveCallViewState extends State<ActiveCallView> {
  bool _endingOrGone = false;

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
      renderer.initialize().then((_) {
        if (!mounted) {
          renderer.dispose();
          return;
        }
        renderer.srcObject = entry.value.consumer.stream;
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

  Future<void> _endCall() async {
    if (_endingOrGone) return;
    setState(() => _endingOrGone = true);

    final current = appStore.state.currentCall;
    // Only the caller ever notifies the other side explicitly (matches
    // webapp's CallWindow.tsx isCaller gate) - a callee hanging up just
    // leaves the mediasoup room below, surfacing to the caller as an
    // ordinary participant-left roster event, nothing more.
    if (current != null && current.isOutgoing && current.recepients.isNotEmpty) {
      CallApi().endCallRequest(IEndCallRequest(
        conversationID: current.conversationID,
        conversationType: current.conversationType,
        recepients: current.recepients,
      ));
    }

    await CallController.instance.leaveCall();
    appStore.dispatch(DispatchModel(clearCurrentCallT, null));
    if (mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/messages');
      }
    }
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

          // The call ended out from under this screen - either the other
          // side's decline/hangup arrived via sse_events.dart's
          // "callreject" case (which calls leaveCall() directly), the
          // transport-close safety net in CallController fired, or the
          // other side just silently left the mediasoup room with no
          // explicit signal at all. Either way status ends up idle here
          // and this screen needs to both pop AND clear the cross-screen
          // Redux signal - _endCall() below does the latter for an
          // explicit hangup, but this branch is the only place that does
          // it for the other paths, which don't go through _endCall().
          if (controller.status == CallEngineStatus.idle && !_endingOrGone) {
            _endingOrGone = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              appStore.dispatch(DispatchModel(clearCurrentCallT, null));
              if (!mounted) return;
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/messages');
              }
            });
          }

          final connecting = controller.status == CallEngineStatus.joining;
          final statusText = connecting
              ? "Connecting…"
              : controller.joinedParticipants.isEmpty
                  ? "Ringing…"
                  : "Connected";

          final hasAnyVideo = !controller.cameraOff || _remoteRenderers.isNotEmpty;

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
  String _statusLabel(String name, {required bool cameraOff, required bool muted}) {
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
    // Participants who've joined but don't have a live video consumer
    // yet - matches webapp's waitingParticipants placeholder tiles
    // exactly (CallWindow.tsx lines 1303-1318).
    final videoConsumerOwnerIds = controller.consumers.values
        .where((e) => e.kind == 'video')
        .map((e) => e.ownerClientId)
        .whereType<String>()
        .toSet();
    final waitingParticipants = controller.joinedParticipants
        .where((p) => !videoConsumerOwnerIds.contains(p.clientId))
        .toList();

    final remoteEntries = controller.consumers.entries
        .where((e) => e.value.kind == 'video' && _remoteRenderers.containsKey(e.key))
        .toList();

    return Stack(
      children: [
        Positioned.fill(
          child: remoteEntries.isEmpty
              ? _buildLocalOrWaitingFill(controller, statusText, waitingParticipants)
              : remoteEntries.length == 1
                  ? _remoteVideoTile(controller, remoteEntries.first, fill: true)
                  : _remoteVideoGrid(controller, remoteEntries, waitingParticipants),
        ),
        if (!controller.cameraOff && _localRendererReady)
          Positioned(
            top: 16,
            right: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 110,
                height: 150,
                child: RTCVideoView(
                  _localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
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

  /// No live remote video yet - shows our own camera full-bleed if it's
  /// on, else the "You • ..." placeholder tile, plus any waiting
  /// participants stacked below (rare on a 1:1 call before the other side
  /// answers, more relevant once M8 group calls land).
  Widget _buildLocalOrWaitingFill(CallController controller, String statusText,
      List<JoinedParticipant> waitingParticipants) {
    return Container(
      color: _kCallBg,
      child: Column(
        children: [
          Expanded(
            child: !controller.cameraOff && _localRendererReady
                ? RTCVideoView(_localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : _placeholderTile(
                    _statusLabel("You",
                        cameraOff: controller.cameraOff, muted: controller.muted),
                  ),
          ),
          if (waitingParticipants.isNotEmpty)
            SizedBox(
              height: 100,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                children: waitingParticipants
                    .map((p) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: SizedBox(
                            width: 140,
                            child: _placeholderTile(
                              _statusLabel(
                                "@${p.username.isNotEmpty ? p.username : p.clientId}",
                                cameraOff: controller.participantStatuses[p.clientId]
                                        ?.cameraOff ??
                                    false,
                                muted: controller.participantStatuses[p.clientId]
                                        ?.muted ??
                                    false,
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  /// #3D4043 background, 5px-derived rounded corners, centered label -
  /// matches webapp's .div_video_blocks / .video_call_display exactly
  /// (CallWindow.tsx lines 1274-1280, 1308-1316).
  Widget _placeholderTile(String label) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: CLColors.callTile,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _remoteVideoTile(
      CallController controller, MapEntry<String, ConsumerEntry> entry,
      {required bool fill}) {
    final owner = entry.value.ownerClientId != null
        ? controller.joinedParticipants
            .where((p) => p.clientId == entry.value.ownerClientId)
            .toList()
        : const <JoinedParticipant>[];
    final status = entry.value.ownerClientId != null
        ? controller.participantStatuses[entry.value.ownerClientId]
        : null;
    final label = owner.isNotEmpty ? "@${owner.first.username}" : "Participant";

    final video = RTCVideoView(_remoteRenderers[entry.key]!,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);

    return ClipRRect(
      borderRadius: fill ? BorderRadius.zero : BorderRadius.circular(8),
      child: Container(
        color: CLColors.callTile,
        child: Stack(
          fit: StackFit.expand,
          children: [
            video,
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _statusLabel(label,
                      cameraOff: status?.cameraOff ?? false, muted: status?.muted ?? false),
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Group-call tile grid - same tile styling as the 1:1 full-bleed case,
  /// just wrapped two-per-row instead of stretched full-screen. Ported
  /// for structural fidelity with M8 in mind; this milestone only ever
  /// exercises the single-remote-tile path above.
  Widget _remoteVideoGrid(CallController controller,
      List<MapEntry<String, ConsumerEntry>> remoteEntries,
      List<JoinedParticipant> waitingParticipants) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - 12) / 2;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(4),
          child: Wrap(
            children: [
              ...remoteEntries.map((entry) => SizedBox(
                    width: tileWidth,
                    height: tileWidth * 1.2,
                    child: _remoteVideoTile(controller, entry, fill: false),
                  )),
              ...waitingParticipants.map((p) => SizedBox(
                    width: tileWidth,
                    height: tileWidth * 1.2,
                    child: _placeholderTile(_statusLabel(
                      "@${p.username.isNotEmpty ? p.username : p.clientId}",
                      cameraOff:
                          controller.participantStatuses[p.clientId]?.cameraOff ?? false,
                      muted: controller.participantStatuses[p.clientId]?.muted ?? false,
                    )),
                  )),
            ],
          ),
        );
      },
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
            onPressed: controller.isActive ? () => controller.toggleMic() : null,
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
