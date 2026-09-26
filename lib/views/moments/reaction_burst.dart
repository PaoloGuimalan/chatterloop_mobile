import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A reaction emoji that bursts when it is chosen (Moments polish 1a / 1c):
/// it pops, a ring spreads from its circle, and a larger copy floats up and
/// fades. Bump [burst] to play it again; at 0 it sits still, unpopped - a
/// reaction made on an earlier visit shows chosen, without the fanfare.
///
/// The copy floats OUTSIDE this widget's box, so nothing above it may clip.
class ReactionBurst extends StatefulWidget {
  final String emoji;

  /// The glyph's font size at rest.
  final double size;

  /// The spreading ring - the circle's own highlight colour.
  final Color ringColor;
  final int burst;

  /// Plays only the pop - for the small toggle that shows your reaction.
  final bool popOnly;

  const ReactionBurst({
    super.key,
    required this.emoji,
    required this.size,
    required this.ringColor,
    required this.burst,
    this.popOnly = false,
  });

  @override
  State<ReactionBurst> createState() => _ReactionBurstState();
}

class _ReactionBurstState extends State<ReactionBurst>
    with SingleTickerProviderStateMixin {
  // The whole burst: the rise is the longest part (.95s); the pop takes the
  // first .5s of it and the ring the first .6s.
  static const _total = 950.0;
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 950));

  @override
  void initState() {
    super.initState();
    if (widget.burst > 0) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant ReactionBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.burst != oldWidget.burst && widget.burst > 0) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Scale through the pop's keyframes: 1 → 1.55 → .92 → 1.12, and held there
  /// once it has played - the chosen one stays a touch larger.
  static double _pop(double t) {
    if (t <= 0) return 1;
    if (t < 0.35) return _lerp(1, 1.55, Curves.easeOut.transform(t / 0.35));
    if (t < 0.65) {
      return _lerp(1.55, 0.92, Curves.easeInOut.transform((t - 0.35) / 0.3));
    }
    if (t < 1) {
      return _lerp(0.92, 1.12, Curves.easeOut.transform((t - 0.65) / 0.35));
    }
    return 1.12;
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final elapsed = _controller.value * _total;
        final running = _controller.isAnimating;
        final pop = _pop(elapsed / 500);
        final ring = (elapsed / 600).clamp(0.0, 1.0);
        final rise = Curves.easeOutCubic.transform(_controller.value);
        // Fades in over the first 18%, out over the rest.
        final riseOpacity = _controller.value < 0.18
            ? _controller.value / 0.18
            : 1 - (_controller.value - 0.18) / 0.82;

        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (running && !widget.popOnly && ring < 1)
              Positioned.fill(
                child: IgnorePointer(
                  child: Transform.scale(
                    scale: 1 + ring,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: widget.ringColor
                                .withValues(alpha: 0.9 * (1 - ring)),
                            width: 2),
                      ),
                    ),
                  ),
                ),
              ),
            Transform.scale(
              scale: pop,
              child: Text(widget.emoji,
                  style: TextStyle(fontSize: widget.size, height: 1)),
            ),
            if (running && !widget.popOnly)
              Positioned(
                left: -40,
                right: -40,
                bottom: 0,
                child: IgnorePointer(
                  child: Transform.translate(
                    offset: Offset(0, 8 - 104 * rise),
                    child: Opacity(
                      opacity: math.max(0, math.min(1, riseOpacity)),
                      child: Transform.scale(
                        scale: 0.5 + 1.1 * rise,
                        child: Text(widget.emoji,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: widget.size * 1.6, height: 1)),
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
