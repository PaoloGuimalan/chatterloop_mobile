// Rounded-square tile for the Contacts screen's group chat rail and its
// "See all" grid. Flutter counterpart of webapp's GroupTile.
//
// These are shortcuts into CONVERSATIONS the entity is actually in, not a
// realm directory - hence the group-chat glyph and the small forum marker,
// which is what makes a tile read as "a thread" rather than "a page".

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/models/user_models/network_models.dart';
import 'package:flutter/material.dart';

/// The rounded-square badge inside a tile.
const double _kTileBadge = 54.0;

/// Tile width in the horizontal rail (the grid variant sizes to its cell).
///
/// Deliberately close to [_kTileBadge]: the tile is only as wide as it is to
/// give the label a line to sit on, and every pixel of the difference shows up
/// as blank space on BOTH sides of the badge, doubled again by the rail's gap.
/// At the mockup's 108 around a 54px badge that read as 54px of nothing between
/// two tiles. A label that no longer fits wraps to a second line instead of
/// demanding width.
const double kGroupTileWidth = 76;

class CLGroupTile extends StatelessWidget {
  final GroupShortcut group;
  final ValueChanged<GroupShortcut> onOpen;

  /// Rail tiles are pinned to [kGroupTileWidth]; grid tiles fill their cell.
  final bool fillWidth;

  const CLGroupTile({
    super.key,
    required this.group,
    required this.onOpen,
    this.fillWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final gradient = clEntityGradient(group.realmId);

    return SizedBox(
      width: fillWidth ? null : kGroupTileWidth,
      child: InkWell(
        onTap: () => onOpen(group),
        borderRadius: BorderRadius.circular(CLRadii.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _kTileBadge,
              height: _kTileBadge,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (group.profile != null)
                    CLAvatar(
                      id: group.realmId,
                      name: group.displayName,
                      src: group.profile,
                      size: _kTileBadge,
                      cornerRadius: 16,
                    )
                  else
                    // Saturated gradient + white glyph, matching the avatars
                    // beside it - a soft tint washed out badly against the
                    // light-mode background.
                    Container(
                      width: _kTileBadge,
                      height: _kTileBadge,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: gradient,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.groups,
                          size: 26, color: Colors.white),
                    ),
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Icon(Icons.forum, size: 11, color: p.brand),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Text(
              group.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: CLType.label,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: p.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CLGroupTileSkeleton extends StatelessWidget {
  final bool fillWidth;

  const CLGroupTileSkeleton({super.key, this.fillWidth = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fillWidth ? null : kGroupTileWidth,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CLSkeleton(
              width: _kTileBadge,
              height: _kTileBadge,
              borderRadius: BorderRadius.all(Radius.circular(16))),
          SizedBox(height: 9),
          CLSkeleton(width: 62, height: 10),
        ],
      ),
    );
  }
}
