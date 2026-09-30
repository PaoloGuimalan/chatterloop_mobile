// The live call, outside its own screen.
//
//   In the app, on any other screen: a small floating window - drag it to
//   either side, tap it to go back to the call, or end the call from it.
//   As a picture-in-picture window: the same picture, filling the window.
//
// Mounted once above every route (main.dart), so it is there whichever screen
// the user went to - see CallScreens for why leaving a call screen no longer
// ends the call.
import 'dart:math' as math;

import 'package:chatterloop_app/core/calls/call_controller.dart';
import 'package:chatterloop_app/core/calls/call_screens.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_call_native/chatterloop_call_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallOverlayHost extends StatelessWidget {
  const CallOverlayHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final call = CallController.instance;
    return ListenableBuilder(
      listenable:
          Listenable.merge([call, CallNative.inPip, CallScreens.onScreen]),
      builder: (context, _) {
        final live = call.status == CallEngineStatus.joining ||
            call.status == CallEngineStatus.active;
        final inPip = live && CallNative.inPip.value;
        final floating = live && !inPip && !CallScreens.onScreen.value;
        return Stack(
          children: [
            child,
            // The whole app is what shrinks into a PiP window, whatever
            // screen it was on - so the call covers all of it.
            if (inPip)
              const Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: CallStage(),
                ),
              ),
            if (floating) const Positioned.fill(child: _FloatingCallWindow()),
          ],
        );
      },
    );
  }
}

/// The floating window. Only its card takes touches - the rest of the layer
/// lets them through to the app underneath.
class _FloatingCallWindow extends StatefulWidget {
  const _FloatingCallWindow();

  @override
  State<_FloatingCallWindow> createState() => _FloatingCallWindowState();
}

class _FloatingCallWindowState extends State<_FloatingCallWindow> {
  static const Size _size = Size(104, 152);
  static const double _margin = 10;

  /// Top-left of the card; null until first placed (top right).
  Offset? _offset;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final minX = _margin;
        final maxX =
            math.max(minX, constraints.maxWidth - _size.width - _margin);
        final minY = padding.top + _margin;
        final maxY = math.max(
          minY,
          constraints.maxHeight - _size.height - padding.bottom - _margin,
        );
        final wanted = _offset ?? Offset(maxX, padding.top + 64);
        final at = Offset(
          wanted.dx.clamp(minX, maxX),
          wanted.dy.clamp(minY, maxY),
        );

        return Stack(
          children: [
            AnimatedPositioned(
              duration: _dragging
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              left: at.dx,
              top: at.dy,
              child: GestureDetector(
                onTap: CallScreens.reopen,
                onPanStart: (_) => setState(() => _dragging = true),
                onPanUpdate: (d) => setState(() => _offset = at + d.delta),
                // Settles against whichever side it was let go nearer to.
                onPanEnd: (_) => setState(() {
                  _dragging = false;
                  final nearLeft =
                      at.dx + _size.width / 2 < constraints.maxWidth / 2;
                  _offset = Offset(nearLeft ? minX : maxX, at.dy);
                }),
                child: Material(
                  color: CLColors.callBg,
                  elevation: 10,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox.fromSize(
                    size: _size,
                    child: Stack(
                      children: [
                        const Positioned.fill(child: CallStage(compact: true)),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: _EndButton(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EndButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: CLColors.callEnd,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => CallController.instance.hangUp(),
        child: const SizedBox(
          width: 30,
          height: 30,
          child: Icon(Icons.call_end, size: 16, color: Colors.white),
        ),
      ),
    );
  }
}

/// The one picture that matters most in the call - a shared screen, else
/// someone else's camera, else your own, else who the call is with - with its
/// own renderer, since the call screen's go when it closes.
class CallStage extends StatefulWidget {
  const CallStage({super.key, this.compact = false});

  /// The floating window's size: a smaller avatar and name.
  final bool compact;

  @override
  State<CallStage> createState() => _CallStageState();
}

class _CallStageState extends State<CallStage> {
  final CallController _call = CallController.instance;
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  bool _ready = false;

  /// What the renderer shows: a remote producer id, 'local', or nothing.
  String? _bound;
  bool _boundIsScreen = false;

  @override
  void initState() {
    super.initState();
    _call.addListener(_sync);
    _renderer.initialize().then((_) {
      if (!mounted) return;
      _ready = true;
      _sync();
    });
  }

  @override
  void dispose() {
    _call.removeListener(_sync);
    _renderer.srcObject = null;
    _renderer.dispose();
    super.dispose();
  }

  MapEntry<String, ConsumerEntry>? _mainRemote() {
    final video = _call.consumers.entries.where((e) {
      if (e.value.kind != 'video') return false;
      if (e.value.source == 'screen') return true;
      // A camera its owner has switched off is a black frame - skip it.
      final owner = e.value.ownerClientId;
      return owner == null || _call.participantStatuses[owner]?.cameraOff != true;
    }).toList();
    return video.where((e) => e.value.source == 'screen').firstOrNull ??
        video.firstOrNull;
  }

  void _sync() {
    if (!mounted) return;
    final remote = _mainRemote();
    final target = remote?.key ??
        (!_call.cameraOff && _call.mediaStream != null ? 'local' : null);
    if (_ready && target != _bound) {
      _bound = target;
      _boundIsScreen = remote?.value.source == 'screen';
      if (remote != null) {
        try {
          // This consumer's own track - a peer's camera and screen share one
          // stream (see ActiveCallView._syncRenderers).
          _renderer.setSrcObject(
            stream: remote.value.consumer.stream,
            trackId: remote.value.consumer.track.id,
          );
        } catch (_) {
          _renderer.srcObject = remote.value.consumer.stream;
        }
      } else {
        _renderer.srcObject = target == 'local' ? _call.mediaStream : null;
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final showVideo = _ready && _bound != null;
    return ColoredBox(
      color: CLColors.callBg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showVideo)
            RTCVideoView(
              _renderer,
              mirror: _bound == 'local',
              objectFit: _boundIsScreen
                  ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
                  : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            _who(),
          if (_call.muted)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.mic_off, size: 14, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _who() {
    final title = CallScreens.title(_call);
    final initial = title.replaceFirst('@', '').trim();
    final radius = widget.compact ? 22.0 : 28.0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CLAvatar(
              id: _call.conversationID,
              name: initial,
              src: _call.displayImage,
              size: radius * 2,
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: CLColors.callText,
                fontSize: widget.compact ? 11 : 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
