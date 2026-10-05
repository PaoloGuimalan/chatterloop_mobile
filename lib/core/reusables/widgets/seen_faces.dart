import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:flutter/material.dart';

/// One member's "seen" face.
class SeenFace {
  /// The member's ENTITY id - it keys the face across messages.
  final String entityId;
  final String name;
  final String? src;
  final String? kind;

  const SeenFace(
      {required this.entityId, required this.name, this.src, this.kind});
}

/// Faces drawn before the rest collapse into "+N".
const int _maxSeenFaces = 5;
const double _seenFaceSize = 16;

/// Where each member's face was last drawn in ONE conversation, so a face
/// that turns up under a newer message can start where it was and slide down
/// to it - the move the webapp gets from framer's `layoutId`.
///
/// Positions are recorded in global coordinates together with the list's
/// scroll offset at that moment, and corrected for scrolling since: in the
/// thread's `reverse: true` list, scrolling back (pixels growing) carries
/// every row DOWN the screen by the same amount.
class SeenFaceTracker {
  final ScrollController? scrollController;
  final Map<String, _FaceSnapshot> _last = {};

  SeenFaceTracker({this.scrollController});

  double get _pixels => scrollController?.hasClients == true
      ? scrollController!.position.pixels
      : 0;

  void record(String entityId, String messageId, Offset global) {
    _last[entityId] = _FaceSnapshot(messageId, global, _pixels);
  }

  /// Where [entityId]'s face was drawn under a DIFFERENT message, adjusted for
  /// scrolling since - null when it was never drawn, or was drawn right here.
  Offset? previousPosition(String entityId, String messageId) {
    final snapshot = _last[entityId];
    if (snapshot == null || snapshot.messageId == messageId) return null;
    return snapshot.global + Offset(0, _pixels - snapshot.pixels);
  }

  bool hasMoved(String entityId, String messageId) {
    final snapshot = _last[entityId];
    return snapshot != null && snapshot.messageId != messageId;
  }

  /// Already drawn under this very message - a row rebuilt after scrolling
  /// back into view, which should simply be there again.
  bool isAt(String entityId, String messageId) =>
      _last[entityId]?.messageId == messageId;
}

class _FaceSnapshot {
  final String messageId;
  final Offset global;
  final double pixels;
  const _FaceSnapshot(this.messageId, this.global, this.pixels);
}

/// The "seen" faces under one message in a group or channel: everyone whose
/// newest seen message is this one (see utils/message_runs' seenFaceAnchors).
/// Right-aligned whoever sent the message. A face that moved here from an
/// older message slides down from it; a face seen for the first time pops in.
///
/// No presence marker: at 16px it would cover the face, and this is a
/// decorative stack like the Popular Topics faces, which skip it too.
class SeenFacesRow extends StatelessWidget {
  final String messageId;
  final List<SeenFace> faces;
  final SeenFaceTracker tracker;

  const SeenFacesRow(
      {super.key,
      required this.messageId,
      required this.faces,
      required this.tracker});

  @override
  Widget build(BuildContext context) {
    if (faces.isEmpty) return const SizedBox.shrink();
    final p = cl(context);
    final shown = faces.take(_maxSeenFaces).toList();
    final hidden = faces.length - shown.length;
    return Semantics(
      label: "Seen by ${faces.map((f) => f.name).join(", ")}",
      child: Padding(
        padding: const EdgeInsets.only(top: 2, right: 4, bottom: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (final face in shown)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: _SeenFaceView(
                  key: ValueKey(face.entityId),
                  face: face,
                  messageId: messageId,
                  tracker: tracker,
                ),
              ),
            if (hidden > 0)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text("+$hidden",
                    style: TextStyle(fontSize: CLType.meta, color: p.text3)),
              ),
          ],
        ),
      ),
    );
  }
}

class _SeenFaceView extends StatefulWidget {
  final SeenFace face;
  final String messageId;
  final SeenFaceTracker tracker;

  const _SeenFaceView(
      {super.key,
      required this.face,
      required this.messageId,
      required this.tracker});

  @override
  State<_SeenFaceView> createState() => _SeenFaceViewState();
}

class _SeenFaceViewState extends State<_SeenFaceView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420));

  /// Measured, not the face itself: the slide is a Transform INSIDE it, which
  /// moves what is painted without moving this box.
  final GlobalKey _boxKey = GlobalKey();

  /// Where the slide starts, relative to where the face now sits.
  Offset _from = Offset.zero;

  /// True for a face that moved here: it pops in only when it is new, and it
  /// stays invisible for the one frame before its start is measured, so it
  /// never flashes at its destination first.
  late final bool _moving =
      widget.tracker.hasMoved(widget.face.entityId, widget.messageId);
  bool _measured = false;

  @override
  void initState() {
    super.initState();
    if (_moving) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startSlide());
      return;
    }
    _measured = true;
    if (widget.tracker.isAt(widget.face.entityId, widget.messageId)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _record());
  }

  void _startSlide() {
    if (!mounted) return;
    final now = _globalPosition();
    final previous = widget.tracker
        .previousPosition(widget.face.entityId, widget.messageId);
    setState(() {
      _from = now != null && previous != null ? previous - now : Offset.zero;
      _measured = true;
    });
    _controller.forward(from: 0);
    _record();
  }

  Offset? _globalPosition() {
    final box = _boxKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero);
  }

  void _record() {
    if (!mounted) return;
    final now = _globalPosition();
    if (now != null) {
      widget.tracker.record(widget.face.entityId, widget.messageId, now);
    }
  }

  @override
  void didUpdateWidget(covariant _SeenFaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rows above can change height without this face moving to another
    // message - keep its last known spot current for the next slide.
    WidgetsBinding.instance.addPostFrameCallback((_) => _record());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final face = widget.face;
    return SizedBox(
      key: _boxKey,
      width: _seenFaceSize,
      height: _seenFaceSize,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(_controller.value);
          if (!_measured) return Opacity(opacity: 0, child: child);
          if (_moving) {
            return Transform.translate(
                offset: Offset.lerp(_from, Offset.zero, t)!, child: child);
          }
          return Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.4 + 0.6 * t, child: child),
          );
        },
        child: CLAvatar(
          // The entity id, like the message avatars, so a face keeps its
          // colour everywhere it appears.
          id: face.entityId,
          name: face.name,
          src: face.src,
          kind: face.kind,
          size: _seenFaceSize,
        ),
      ),
    );
  }
}
