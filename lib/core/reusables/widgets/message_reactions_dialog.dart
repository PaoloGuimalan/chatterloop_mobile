// Long-press message dialog - quick reactions, the message itself, and the
// context menu (Reply / Copy / Delete / React).
//
// A thin re-implementation of flutter_chat_reactions' ReactionsDialogWidget,
// which is only ~40 lines of composition. Only its MESSAGE BUBBLE is reused;
// the context menu and the reactions row are replaced.
//
// Why replace the context menu: it hardcodes its own typography and spacing
// and exposes no hooks. Labels render at Material's 14 with 24px icons -
// larger than anything in this app's scale - and its container has NO padding,
// so the first and last options sit 4px from the edge while the options
// between them get 8px.
//
// Why replace the reactions row: it has no notion of a PERSISTENT selection,
// only a tap animation, so it could not show which emoji you already had.
//
// The reaction and menu tap handlers keep the package's 500ms delay: it lets
// the tap animation finish before the route pops, and dropping it makes the
// dialog vanish mid-animation.

import 'dart:ui';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_reactions/model/menu_item.dart';
import 'package:flutter_chat_reactions/widgets/message_bubble.dart';


class CLMessageReactionsDialog extends StatefulWidget {
  const CLMessageReactionsDialog({
    super.key,
    required this.id,
    required this.messageWidget,
    required this.onReactionTap,
    required this.onContextMenuTap,
    required this.menuItems,
    required this.reactions,
    this.myReaction,
    this.widgetAlignment = Alignment.centerRight,
    this.menuItemsWidth = 0.45,
  });

  final String id;
  final Widget messageWidget;
  final void Function(String) onReactionTap;
  final void Function(MenuItem) onContextMenuTap;
  final List<MenuItem> menuItems;
  final List<String> reactions;

  /// The emoji this user has already picked, if any - drawn selected so the
  /// row says what your current reaction is rather than looking untouched.
  final String? myReaction;

  final Alignment widgetAlignment;

  /// Fraction of screen width, matching the package's own convention.
  final double menuItemsWidth;

  @override
  State<CLMessageReactionsDialog> createState() =>
      _CLMessageReactionsDialogState();
}

class _CLMessageReactionsDialogState extends State<CLMessageReactionsDialog> {
  bool _reactionClicked = false;
  int? _clickedReactionIndex;
  int? _clickedMenuIndex;

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ReactionsRow(
                reactions: widget.reactions,
                alignment: widget.widgetAlignment,
                onReactionTap: _handleReactionTap,
                clickedIndex: _clickedReactionIndex,
                reactionClicked: _reactionClicked,
                selected: widget.myReaction,
              ),
              const SizedBox(height: 10),
              MessageBubble(
                id: widget.id,
                messageWidget: widget.messageWidget,
                alignment: widget.widgetAlignment,
              ),
              const SizedBox(height: 10),
              _ContextMenu(
                menuItems: widget.menuItems,
                alignment: widget.widgetAlignment,
                menuWidth: widget.menuItemsWidth,
                clickedIndex: _clickedMenuIndex,
                onMenuItemTap: _handleMenuTap,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleReactionTap(String reaction, int index) {
    setState(() {
      _reactionClicked = true;
      _clickedReactionIndex = index;
    });
    Future.delayed(const Duration(milliseconds: 500)).whenComplete(() {
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onReactionTap(reaction);
    });
  }

  void _handleMenuTap(MenuItem item, int index) {
    setState(() => _clickedMenuIndex = index);
    Future.delayed(const Duration(milliseconds: 500)).whenComplete(() {
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onContextMenuTap(item);
    });
  }
}

/// The options card. Padding lives on the CARD, not only on each row, so the
/// first and last options get the same breathing room as the ones between
/// them - the gap the package's version left.
class _ContextMenu extends StatelessWidget {
  const _ContextMenu({
    required this.menuItems,
    required this.alignment,
    required this.menuWidth,
    required this.clickedIndex,
    required this.onMenuItemTap,
  });

  final List<MenuItem> menuItems;
  final Alignment alignment;
  final double menuWidth;
  final int? clickedIndex;
  final void Function(MenuItem, int) onMenuItemTap;

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    return Align(
      alignment: alignment,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * menuWidth,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < menuItems.length; i++) ...[
                _MenuRow(
                  item: menuItems[i],
                  isClicked: clickedIndex == i,
                  onTap: () => onMenuItemTap(menuItems[i], i),
                ),
                // Inset so the rule stops short of the card's rounded edge
                // instead of running into it.
                if (i != menuItems.length - 1)
                  Divider(
                    color: p.border,
                    thickness: 0.5,
                    height: 0.5,
                    indent: 12,
                    endIndent: 12,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.item,
    required this.isClicked,
    required this.onTap,
  });

  final MenuItem item;
  final bool isClicked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    // The package's own field name carries this typo - kept so MenuItem stays
    // interchangeable with DefaultData.menuItems.
    final color = item.isDestuctive ? p.pink : p.text;

    return InkWell(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isClicked ? 0.45 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                item.label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: CLType.body,
                  color: color,
                ),
              ),
              Icon(item.icon, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quick-reaction row.
///
/// Replaces the package's ReactionsRow for two reasons: it has no notion of a
/// PERSISTENT selection - `isClicked` is only the tap animation - so the row
/// gave no clue which emoji you already had, and its surface/shadow come from
/// Material defaults rather than the app's tokens.
class _ReactionsRow extends StatelessWidget {
  const _ReactionsRow({
    required this.reactions,
    required this.alignment,
    required this.onReactionTap,
    required this.clickedIndex,
    required this.reactionClicked,
    required this.selected,
  });

  final List<String> reactions;
  final Alignment alignment;
  final void Function(String, int) onReactionTap;
  final int? clickedIndex;
  final bool reactionClicked;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    return Align(
      alignment: alignment,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: p.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < reactions.length; i++)
                _ReactionButton(
                  emoji: reactions[i],
                  isSelected: selected == reactions[i],
                  isClicked: reactionClicked && clickedIndex == i,
                  onTap: () => onReactionTap(reactions[i], i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.emoji,
    required this.isSelected,
    required this.isClicked,
    required this.onTap,
  });

  final String emoji;
  final bool isSelected;
  final bool isClicked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 250),
        scale: isClicked ? 1.35 : 1,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            // A filled pill behind the emoji - emoji glyphs ignore colour, so
            // tinting the text would do nothing; the background is the only
            // thing that can carry the selected state.
            color: isSelected ? p.brand.withValues(alpha: 0.18) : null,
            shape: BoxShape.circle,
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 22)),
        ),
      ),
    );
  }
}
