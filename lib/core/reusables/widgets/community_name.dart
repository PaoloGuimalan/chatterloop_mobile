import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'package:flutter/material.dart';

/// Inline presentation shared by destinations and future community screens.
List<InlineSpan> communityNameSpans(
  BuildContext context,
  Community community, {
  required TextStyle style,
}) {
  final palette = cl(context);
  TextSpan marker(IconData icon, String label, Color color,
          {double size = 13}) =>
      TextSpan(
        text: String.fromCharCode(icon.codePoint),
        semanticsLabel: label,
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          color: color,
        ),
      );
  return [
    TextSpan(text: community.name, style: style),
    if (community.isVerified) ...[
      const TextSpan(text: '\u00a0\u2060'),
      marker(Icons.verified, 'Verified community', palette.brand),
    ],
    const TextSpan(text: '\u00a0\u2060'),
    marker(Icons.groups_outlined, 'Community', palette.text3, size: 17),
  ];
}
