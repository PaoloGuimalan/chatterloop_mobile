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

/// Tile width in the horizontal rail. The grid variant sizes to its cell.
const double kGroupTileWidth = 108;

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
              width: 60,
              height: 60,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (group.profile != null)
                    CLAvatar(
                      id: group.realmId,
                      name: group.displayName,
                      src: group.profile,
                      size: 60,
                      cornerRadius: 18,
                    )
                  else
                    // Saturated gradient + white glyph, matching the avatars
                    // beside it - a soft tint washed out badly against the
                    // light-mode background.
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: gradient,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.groups,
                          size: 28, color: Colors.white),
                    ),
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      width: 20,
                      height: 20,
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
                      child: Icon(Icons.forum, size: 12, color: p.brand),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              group.displayName,
              maxLines: fillWidth ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
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
              width: 60,
              height: 60,
              borderRadius: BorderRadius.all(Radius.circular(18))),
          SizedBox(height: 10),
          CLSkeleton(width: 70, height: 11),
        ],
      ),
    );
  }
}
