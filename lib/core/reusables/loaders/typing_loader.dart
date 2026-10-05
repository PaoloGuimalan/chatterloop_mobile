import 'package:flutter/material.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';

/// One typer's face beside the typing bubble.
class TypingFace {
  final String key;
  final String name;

  /// Gradient key for the initials fallback, matching the member lists.
  final String colorKey;
  final String? src;
  final String? kind;

  const TypingFace({
    required this.key,
    required this.name,
    required this.colorKey,
    this.src,
    this.kind,
  });

  @override
  bool operator ==(Object other) =>
      other is TypingFace &&
      other.key == key &&
      other.name == name &&
      other.src == src &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(key, name, src, kind);
}

/// Where each face of a typing cluster sits inside the avatar column, as
/// (left, top, diameter) fractions of the column's width. The cluster never
/// grows past one avatar's square - that is what keeps the typing bubble
/// lined up with every message bubble above it, however many people type.
/// The webapp draws the same shapes (IsTypingLoader's CLUSTER).
const List<List<List<double>>> _clusterSlots = [
  [
    [0, 0, 1]
  ],
  // Two: a diagonal pair, the second over the first.
  [
    [0, 0, 0.69],
    [0.31, 0.31, 0.69]
  ],
  // Three or more: a small triangle - the third slot turns into "+N" when
  // there are more people than faces.
  [
    [0, 0, 0.56],
    [0.44, 0, 0.56],
    [0.22, 0.44, 0.56]
  ],
];

class TypingIndicator extends StatefulWidget {
  final bool isTyping;
  final CLPalette p;

  /// WHO is typing, drawn beside the bubble where a group run's avatar sits:
  /// one face at [faceSize], or a small cluster inside that same square when
  /// several people type at once. Empty for a DM, whose messages carry no
  /// avatar either. No
  /// presence marker - someone typing is plainly here, and the marker's "Nm"
  /// pill could otherwise claim they left minutes ago.
  final List<TypingFace> faces;
  final double faceSize;

  const TypingIndicator(
      {super.key,
      required this.isTyping,
      required this.p,
      this.faces = const [],
      this.faceSize = 32});
  @override
  TypingIndicatorState createState() => TypingIndicatorState();
}

class TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation1;
  late Animation<double> _animation2;
  late Animation<double> _animation3;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _animation1 = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6)),
    );
    _animation2 = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.2, 0.8)),
    );
    _animation3 = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.4, 1.0)),
    );

    // Only animate WHILE actually typing. This used to be `..repeat()`
    // unconditionally, so the controller ran forever for as long as the widget
    // was mounted. Now that the indicator lives in a fixed, always-mounted spot
    // above the input, that kept Flutter producing frames at 60fps nonstop -
    // the app never went idle, pinning CPU/GPU and heating the device even when
    // nobody was typing. Starting/stopping with isTyping lets the app go idle.
    if (widget.isTyping) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isTyping && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isTyping && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The faces, clustered into one avatar's square when there are several.
  /// Returns null when there is nothing to draw.
  Widget? _faces() {
    if (!widget.isTyping || widget.faces.isEmpty) return null;
    final count = widget.faces.length;
    final slots = _clusterSlots[(count - 1).clamp(0, 2)];
    final square = widget.faceSize;
    final clustered = count > 1;
    // Past three, the last slot says how many more rather than show a face.
    final overflow = count > slots.length ? count - (slots.length - 1) : 0;
    return SizedBox(
      width: square,
      height: square,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < slots.length; i++)
            Positioned(
              left: square * slots[i][0],
              top: square * slots[i][1],
              child: Container(
                width: square * slots[i][2],
                height: square * slots[i][2],
                // Ringed in the thread's colour, so overlapping faces read
                // as separate people rather than one blob.
                decoration: clustered
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.p.surface,
                        border: Border.all(color: widget.p.surface, width: 1.5))
                    : null,
                alignment: Alignment.center,
                child: overflow > 0 && i == slots.length - 1
                    ? Container(
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, color: widget.p.surface3),
                        alignment: Alignment.center,
                        child: FittedBox(
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Text("+$overflow",
                                style: TextStyle(
                                    fontSize: CLType.meta,
                                    fontWeight: FontWeight.w600,
                                    color: widget.p.text2)),
                          ),
                        ),
                      )
                    : CLAvatar(
                        id: widget.faces[i].colorKey,
                        name: widget.faces[i].name,
                        src: widget.faces[i].src,
                        kind: widget.faces[i].kind,
                        size: square * slots[i][2] - (clustered ? 3 : 0),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final faces = _faces();
    return Padding(
      // With faces the row starts where a run's avatar does, and the face and
      // its 8px gap put the bubble where every message bubble starts.
      padding: EdgeInsets.only(
          top: 0, bottom: 0, left: faces == null ? 5 : 0, right: 0),
      child: Column(
        children: [
          SizedBox(
            height: widget.isTyping ? 7 : 0,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (faces != null) ...[faces, const SizedBox(width: 8)],
              // RepaintBoundary so the per-frame dot animation only repaints
              // this little bubble, never the message list / whole screen.
              RepaintBoundary(
                child: AnimatedContainer(
                  width: widget.isTyping ? 60 : 0,
                  height: widget.isTyping ? 40 : 0,
                  decoration: BoxDecoration(
                      color: widget.p.surface3,
                      borderRadius: BorderRadius.circular(10)),
                  duration: Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: Padding(
                    padding: EdgeInsets.all(5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedDot(animation: _animation1, p: widget.p),
                        const SizedBox(width: 5),
                        AnimatedDot(animation: _animation2, p: widget.p),
                        const SizedBox(width: 5),
                        AnimatedDot(animation: _animation3, p: widget.p),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                  child: SizedBox(
                height: 0,
              ))
            ],
          )
        ],
      ),
    );
  }
}

class AnimatedDot extends AnimatedWidget {
  final CLPalette p;
  const AnimatedDot(
      {super.key, required Animation<double> animation, required this.p})
      : super(listenable: animation);

  Animation<double> get animation => listenable as Animation<double>;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: animation.value,
      child: Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          color: p.text,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
