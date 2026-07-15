// Turns URLs inside message text into tappable spans that open externally.
// Same regex as webapp's urlify() (reusables/hooks/reusable.ts) - a bare
// "http(s)://" run of non-whitespace characters, no smarter boundary
// detection than that (matches webapp's own scope: it doesn't trim
// trailing punctuation here either, only in the link-preview URL
// extraction path).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

final RegExp _urlRegex = RegExp(r'https?://[^\s]+');

Future<void> _openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Builds the InlineSpan list for a Text.rich showing `content` with any
/// URLs rendered as tappable, underlined spans - same color as the
/// surrounding text (webapp's urlify() sets style="color: inherit" on its
/// <a> tags too, relying on the underline alone for affordance).
List<InlineSpan> linkifySpans(String content, TextStyle baseStyle) {
  final matches = _urlRegex.allMatches(content);
  if (matches.isEmpty) {
    return [TextSpan(text: content, style: baseStyle)];
  }

  final linkStyle = baseStyle.copyWith(decoration: TextDecoration.underline);
  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in matches) {
    if (match.start > cursor) {
      spans.add(TextSpan(
          text: content.substring(cursor, match.start), style: baseStyle));
    }
    final url = content.substring(match.start, match.end);
    spans.add(TextSpan(
      text: url,
      style: linkStyle,
      recognizer: TapGestureRecognizer()..onTap = () => _openUrl(url),
    ));
    cursor = match.end;
  }
  if (cursor < content.length) {
    spans.add(TextSpan(text: content.substring(cursor), style: baseStyle));
  }
  return spans;
}
