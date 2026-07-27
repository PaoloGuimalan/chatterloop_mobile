// Section headers and horizontal rails - Flutter counterparts of webapp's
// SectionTitle + HScrollRail (reusables/design).
//
// A rail is driven by chevron buttons rather than a scrollbar, and each
// chevron only appears when there is actually something to reveal on that
// side, so a rail whose contents fit shows no chrome at all. The track itself
// still scrolls normally - a swipe works exactly as it would without the
// arrows.
//
// Unlike web, the arrows sit BESIDE the content instead of floating over it:
// a phone-width rail holds barely more than two cards, so an overlaid chevron
// would cover a meaningful part of one. The rail section puts them in its
// header next to "See all"; the chips rail flanks the track with them.

import 'package:flutter/material.dart';

import 'tokens.dart';

/// How much of a rail scrolls per chevron tap. Just under a full viewport, so
/// a card of context carries across taps and nothing is skipped.
const double _kRailScrollFraction = 0.8;

/// Tracks whether a rail can still scroll left/right and rebuilds its arrows
/// when that changes.
///
/// Listens for BOTH kinds of change: ScrollNotification (the user scrolled)
/// and ScrollMetricsNotification (the content itself resized - e.g. real
/// cards replacing skeletons after a fetch). Without the second one a rail
/// populated after loading would keep the arrow state it had while empty.
class _RailArrowScope extends StatefulWidget {
  final ScrollController controller;
  final Widget Function(BuildContext context, bool canLeft, bool canRight)
      builder;

  const _RailArrowScope({required this.controller, required this.builder});

  @override
  State<_RailArrowScope> createState() => _RailArrowScopeState();
}

class _RailArrowScopeState extends State<_RailArrowScope> {
  bool _canLeft = false;
  bool _canRight = false;

  @override
  void initState() {
    super.initState();
    // Sync once after the first layout. Notifications alone are not enough: a
    // rail whose contents don't change after they're first laid out never
    // dispatches ScrollMetricsNotification, so its arrows would only appear
    // once the user scrolled - and then the row would reflow around them.
    // The controller has no clients until the track below has laid out, which
    // is exactly what a post-frame callback waits for.
    _syncAfterFrame();
  }

  @override
  void didUpdateWidget(covariant _RailArrowScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Contents can change without any scrolling - skeletons being replaced by
    // real cards is the common case, and it changes what's reachable.
    _syncAfterFrame();
  }

  void _syncAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  void _sync() {
    if (!widget.controller.hasClients) return;
    final position = widget.controller.position;
    // 1px slack: fractional widths otherwise leave an arrow enabled forever
    // at the true end of the track.
    final canLeft = position.pixels > position.minScrollExtent + 1;
    final canRight = position.pixels < position.maxScrollExtent - 1;
    if (canLeft == _canLeft && canRight == _canRight) return;
    setState(() {
      _canLeft = canLeft;
      _canRight = canRight;
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<Notification>(
      onNotification: (notification) {
        if (notification is ScrollNotification ||
            notification is ScrollMetricsNotification) {
          // Metrics are reported mid-layout; defer the setState out of it.
          _syncAfterFrame();
        }
        return false;
      },
      child: widget.builder(context, _canLeft, _canRight),
    );
  }
}

/// The 26px circular chevron from the mockup.
///
/// When its direction has nothing left to reveal it stays visible and DIMS,
/// rather than disappearing. Both alternatives were worse: hiding it outright
/// makes the whole row reflow the moment a rail is scrolled off its start, and
/// replacing it with a same-size invisible box (what this used to do) leaves a
/// 32px hole to the left of the first chip - the rail sits at its start most of
/// the time, so that hole was the normal state, not an edge case. A dimmed
/// chevron also says "you're at the start", which nothing else on the row does.
class _RailArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _RailArrow(
      {required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(CLRadii.pill),
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.surface,
            shape: BoxShape.circle,
            border: Border.all(color: p.border2),
          ),
          child: Icon(icon, size: 16, color: p.text2),
        ),
      ),
    );
  }
}

void _nudge(ScrollController controller, int direction) {
  if (!controller.hasClients) return;
  final position = controller.position;
  controller.animateTo(
    (position.pixels + direction * position.viewportDimension * _kRailScrollFraction)
        .clamp(position.minScrollExtent, position.maxScrollExtent),
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
  );
}

Widget _railArrows(BuildContext context, ScrollController controller,
    bool canLeft, bool canRight) {
  if (!canLeft && !canRight) return const SizedBox.shrink();
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _RailArrow(
        icon: Icons.chevron_left,
        enabled: canLeft,
        onTap: () => _nudge(controller, -1),
      ),
      const SizedBox(width: 6),
      _RailArrow(
        icon: Icons.chevron_right,
        enabled: canRight,
        onTap: () => _nudge(controller, 1),
      ),
    ],
  );
}

/// Section title with an optional trailing action - mirrors webapp's
/// SectionTitle. Used on its own for vertical sections (Content, and the
/// three Contacts people sections); [CLRailSection] wraps it for rails.
class CLSectionHeader extends StatelessWidget {
  final String title;

  /// "See all", "See all 38" - omitted when the section has nothing more to
  /// show than what's already on screen.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Extra trailing widget, right of the action label (the rail chevrons).
  final Widget? trailing;

  const CLSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: CLType.sectionTitle,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.15,
                color: p.text,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(CLRadii.xs),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  actionLabel!,
                  style: TextStyle(
                    fontSize: CLType.label,
                    fontWeight: FontWeight.w600,
                    color: p.brand,
                  ),
                ),
              ),
            ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Header + horizontally scrolling track, with the chevrons in the header.
///
/// The track is as tall as its tallest child and no taller: a
/// SingleChildScrollView + IntrinsicHeight + Row, rather than a horizontal
/// ListView. A ListView would need a hardcoded height (a horizontal list gives
/// its children a tight cross-axis constraint), and any such number is wrong
/// the moment a card's contents change - which is exactly how the rails ended
/// up with a strip of dead space inside every card after the type scale
/// landed. IntrinsicHeight also equalises the cards, so a name that wraps
/// doesn't leave its neighbours short.
class CLRailSection extends StatefulWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final List<Widget> children;
  final double gap;

  /// Rendered instead of the track when there is nothing to show - an empty
  /// rail with arrows would read as broken.
  final Widget? empty;

  const CLRailSection({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    required this.children,
    this.gap = 12,
    this.empty,
  });

  @override
  State<CLRailSection> createState() => _CLRailSectionState();
}

class _CLRailSectionState extends State<CLRailSection> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = widget.children.isEmpty;
    return _RailArrowScope(
      controller: _controller,
      builder: (context, canLeft, canRight) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CLSectionHeader(
            title: widget.title,
            actionLabel: widget.actionLabel,
            onAction: widget.onAction,
            trailing: isEmpty
                ? null
                : _railArrows(context, _controller, canLeft, canRight),
          ),
          if (isEmpty)
            widget.empty ?? const SizedBox.shrink()
          else
            SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              child: IntrinsicHeight(
                child: Row(
                  // stretch works because IntrinsicHeight hands the Row a
                  // tight height - every card ends up as tall as the tallest.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0;
                        index < widget.children.length;
                        index++) ...[
                      if (index > 0) SizedBox(width: widget.gap),
                      widget.children[index],
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A single row of chips (Explore's filters, Contacts' jump chips) flanked by
/// the chevrons, per the mockup. 36px tall - a 34px chip plus a hair of
/// breathing room.
///
/// Both chevrons appear or neither does: if the chips all fit there's nothing
/// to reveal in either direction, so the row shows no chrome at all. Once they
/// don't fit, both render and the one that can't move is dimmed rather than
/// hidden - see [_RailArrow].
class CLChipsRail extends StatefulWidget {
  final List<Widget> children;
  final double gap;

  const CLChipsRail({super.key, required this.children, this.gap = 8});

  @override
  State<CLChipsRail> createState() => _CLChipsRailState();
}

class _CLChipsRailState extends State<CLChipsRail> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _RailArrowScope(
      controller: _controller,
      builder: (context, canLeft, canRight) {
        final hasArrows = canLeft || canRight;
        return SizedBox(
          height: 36,
          child: Row(
            children: [
              if (hasArrows) ...[
                _RailArrow(
                  icon: Icons.chevron_left,
                  enabled: canLeft,
                  onTap: () => _nudge(_controller, -1),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: ListView.separated(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  itemCount: widget.children.length,
                  separatorBuilder: (_, __) => SizedBox(width: widget.gap),
                  itemBuilder: (_, index) => Center(child: widget.children[index]),
                ),
              ),
              if (hasArrows) ...[
                const SizedBox(width: 6),
                _RailArrow(
                  icon: Icons.chevron_right,
                  enabled: canRight,
                  onTap: () => _nudge(_controller, 1),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
