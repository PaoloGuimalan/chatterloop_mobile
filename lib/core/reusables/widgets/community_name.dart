import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'package:flutter/material.dart';

/// Inline presentation shared by destinations and future community screens.
List<InlineSpan> communityNameSpans(
  BuildContext context,
  Community community, {
  required TextStyle style,
  VoidCallback? onTap,
}) {
  final palette = cl(context);
  return [
    // One inline placeholder moves the destination as a unit. The name gives
    // up width before either badge, including at larger accessibility sizes.
    WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(community.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ),
            if (community.isVerified) ...[
              const SizedBox(width: 3),
              Icon(Icons.verified,
                  semanticLabel: 'Verified community',
                  size: 13,
                  color: palette.brand),
            ],
            const SizedBox(width: 3),
            Icon(Icons.groups_outlined,
                semanticLabel: 'Community', size: 17, color: palette.text3),
          ],
        ),
      ),
    ),
  ];
}
