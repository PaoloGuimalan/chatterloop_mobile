// One avatar + name + subtitle + trailing-action row, shared by every list in
// the redesigned Contacts screen and by Explore's People "See all".
//
// Flutter counterpart of webapp's NetworkRow, with one deliberate difference:
// the trailing action is passed IN rather than derived from a `kind` enum. The
// row is identical across sections and only the action differs - message for a
// connection, Follow back for a follower, Unfollow for someone you follow,
// Follow for a search hit - so each screen builds its own and the row stays
// dumb. That's also what lets Explore feed it a SearchPersonResult while
// Contacts feeds it a NetworkEntityResult, with no shared base model.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:flutter/material.dart';

class CLEntityRow extends StatelessWidget {
  /// Avatar seed - the entity id, so the same person always gets the same
  /// placeholder gradient everywhere.
  final String entityId;
  final String displayName;

  /// The muted second line: "214 mutual · Active now", "@handle · 2 hours ago".
  final String subtitle;
  final String? profile;
  final bool isVerified;

  /// Adds the small flag marker after the name - this counterpart is a page,
  /// not a person.
  final bool isRealm;

  /// Users only; a page is never "active now".
  final bool online;
  final VoidCallback? onOpen;
  final Widget? action;

  const CLEntityRow({
    super.key,
    required this.entityId,
    required this.displayName,
    required this.subtitle,
    this.profile,
    this.isVerified = false,
    this.isRealm = false,
    this.online = false,
    this.onOpen,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return CLCard(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          CLAvatar(
            id: entityId,
            name: displayName,
            src: profile,
            size: 42,
            online: online,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: onOpen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: p.text,
                          ),
                        ),
                      ),
                      if (isVerified) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified, size: 14, color: p.brand),
                      ],
                      if (isRealm) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.flag, size: 13, color: p.text3),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.text3),
                  ),
                ],
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 10),
            action!,
          ],
        ],
      ),
    );
  }
}

/// The 34px square icon action a connection row uses (open the thread) -
/// distinct from CLIconBtn, which is a bare 40px toolbar button with no
/// surface of its own.
class CLRowIconAction extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onPressed;

  const CLRowIconAction({
    super.key,
    required this.icon,
    this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final button = InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(CLRadii.sm),
      child: Opacity(
        opacity: onPressed == null ? 0.55 : 1,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.surface2,
            borderRadius: BorderRadius.circular(CLRadii.sm),
            border: Border.all(color: p.border),
          ),
          child: Icon(icon, size: 18, color: p.brand),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Placeholder shaped like CLEntityRow, for a section whose rows haven't
/// arrived yet.
class CLEntityRowSkeleton extends StatelessWidget {
  const CLEntityRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return CLCard(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          const CLSkeleton(
              width: 42, height: 42, borderRadius: BorderRadius.all(Radius.circular(21))),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                CLSkeleton(width: 130, height: 12),
                SizedBox(height: 7),
                CLSkeleton(width: 84, height: 10),
              ],
            ),
          ),
          const SizedBox(width: 10),
          CLSkeleton(
            width: 64,
            height: 28,
            borderRadius: BorderRadius.circular(CLRadii.sm),
          ),
        ],
      ),
    );
  }
}
