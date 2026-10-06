import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:flutter/material.dart';

/// Motion for the conversation thread and its composer strips - the
/// counterpart of the webapp's useThreadScroll / composer strip transitions.

/// How long a new message takes to come in, and a strip to open or close.
/// The same 220ms the webapp's strips use; a new message runs a little
/// longer because it travels its whole height.
const Duration kThreadEntryDuration = Duration(milliseconds: 260);
const Duration kComposerStripDuration = Duration(milliseconds: 220);

/// One row of the reversed message list.
///
/// A row that is NEW at the bottom (a pending send, a message that just
/// arrived) grows in from the bottom edge: the list is `reverse: true` and
/// pinned to its bottom, so as the row's height goes from nothing to full,
/// everything above it moves up with it and the row itself is revealed top
/// first - the same picture as the webapp, where the thread holds still and
/// glides. Without this a new message was simply there on the next frame and
/// everything above jumped by its height.
///
/// Every row also eases its own height changes ([AnimatedSize]). That is
/// what makes a pending send turning into its sent message smooth: the two
/// share a key (the pendingID), so the row is kept and only its height moves,
/// instead of one row vanishing and another appearing. Clips only while
/// animating, so seen faces and reaction pills hanging off a bubble are not
/// cut the rest of the time.
class ThreadEntry extends StatefulWidget {
  /// Read once, when the row is first built - a row only ever comes in once.
  final bool animateIn;
  final Widget child;

  const ThreadEntry({super.key, required this.animateIn, required this.child});

  @override
  State<ThreadEntry> createState() => _ThreadEntryState();
}

class _ThreadEntryState extends State<ThreadEntry>
    with SingleTickerProviderStateMixin {
  AnimationController? _entry;

  @override
  void initState() {
    super.initState();
    if (widget.animateIn) {
      _entry = AnimationController(vsync: this, duration: kThreadEntryDuration)
        ..addStatusListener((status) {
          // Done: drop the transition, and with it the clip it brings.
          if (status == AnimationStatus.completed && mounted) {
            setState(() {
              _entry?.dispose();
              _entry = null;
            });
          }
        })
        ..forward();
    }
  }

  @override
  void dispose() {
    _entry?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final row = reduceMotion
        ? widget.child
        : AnimatedSize(
            duration: kComposerStripDuration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: widget.child,
          );
    final entry = _entry;
    if (entry == null || reduceMotion) return row;
    final curve = CurvedAnimation(parent: entry, curve: Curves.easeOutCubic);
    return SizeTransition(
      sizeFactor: curve,
      // Top-aligned: the row's top shows first, as if it rose from under the
      // list's bottom edge.
      alignment: Alignment.topCenter,
      child: FadeTransition(opacity: curve, child: row),
    );
  }
}

/// A composer strip - "Replying to ..." and "Use AI Reply Assist?" - opening
/// and closing.
///
/// Both used to animate a fixed height while their content and colour were
/// decided by `isReplying` on every build. A send or a cancel clears that at
/// once, so the strip emptied (and lost its fill) in the first frame and then
/// collapsed as a blank bar over 500ms. This keeps the LAST child it was given
/// while open and closes that, height and opacity together, so the strip goes
/// away showing what it was. It cannot be tapped while it closes: its buttons
/// would act on a reply that no longer exists.
class ComposerStrip extends StatefulWidget {
  final bool open;

  /// The strip's laid-out height - its content is built for a fixed box.
  final double height;
  final Widget child;

  const ComposerStrip(
      {super.key,
      required this.open,
      required this.height,
      required this.child});

  @override
  State<ComposerStrip> createState() => _ComposerStripState();
}

class _ComposerStripState extends State<ComposerStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kComposerStripDuration,
    value: widget.open ? 1 : 0,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late Widget _shown = widget.child;

  @override
  void didUpdateWidget(covariant ComposerStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open) {
      _shown = widget.child;
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.isDismissed) return const SizedBox.shrink();
        return IgnorePointer(
          ignoring: !widget.open,
          child: ClipRect(
            child: Align(
              // Bottom-aligned: the strip rises out of the composer under it.
              alignment: Alignment.bottomCenter,
              heightFactor: _curve.value,
              child: Opacity(
                opacity: _curve.value.clamp(0.0, 1.0),
                child: SizedBox(
                  height: widget.height,
                  width: double.infinity,
                  child: _shown,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The "N unread messages" line, drawn right above the oldest unread message
/// (see utils/unread_divider.dart).
///
/// Neutral, not the accent: it marks a place in the thread rather than asking
/// for anything. Grey on light; on dark the label takes the full text colour
/// and the hairline text2, since the light greys sink into the dark thread.
/// The webapp's `.cl-unread-divider` makes the same call.
class UnreadDividerLine extends StatelessWidget {
  final String label;

  const UnreadDividerLine({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final line = (dark ? p.text2 : p.text3).withValues(alpha: 0.6);
    return Semantics(
      label: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Expanded(child: Container(height: 1, color: line)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: CLType.meta,
                  fontWeight: FontWeight.w600,
                  color: dark ? p.text : p.text2,
                ),
              ),
            ),
            Expanded(child: Container(height: 1, color: line)),
          ],
        ),
      ),
    );
  }
}
