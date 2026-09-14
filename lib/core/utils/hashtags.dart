// #hashtags inside post captions and comments - the rendering half.
//
// Same model as mentions: the hashtag IS the text. "#hiking" sits in the
// caption like any other characters, nothing travels alongside it, and it is
// re-detected at render time.
//
// FIVE implementations have to agree on what counts as a hashtag, and unlike
// mentions the stakes are not only cosmetic: the backends turn these into
// permanent rows in interests_interest at post/comment creation time.
//
//   moderation_service/core/vocabulary.py         hashtags()   <- canonical
//   user_service/interests/services/hashtags.py   extract_hashtags()
//   server/reusables/hooks/hashtags.js            extractHashtags()
//   webapp/src/reusables/hooks/hashtags.ts        HASHTAG_SOURCE
//   this file
//
// A token this file highlights but the server does not save is a hashtag that
// visibly did nothing, which is exactly the mismatch a user reports as a bug.

import 'package:chatterloop_app/core/utils/linkify_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Unicode classes rather than \w, and this is not pedantry: Python's \w
/// matches accented letters and Dart's does not, so "#café" would be saved by
/// the server and left unhighlighted here. `unicode: true` is required for
/// \p{L} to mean anything at all.
///
/// The lookbehind excludes an HTML numeric entity. This platform stores
/// authored text escaped, so "didn&#039;t" contains "#039", which a bare
/// "#\w+" matched well enough to be tagged as a declared interest. A "#"
/// preceded by "&" is punctuation. Excluding a preceding word character also
/// rules out a URL fragment - "example.com/page#section" is an address, not
/// something anybody tagged, which is why this can run alongside linkifying
/// without either corrupting the other.
final RegExp hashtagPattern = RegExp(
  r'(?<![&\p{L}\p{N}_])#([\p{L}\p{N}_-]{2,50})',
  unicode: true,
);

/// Hyphens and underscores inside a hashtag are word separators: "#north-edsa"
/// and "#docker_swarm" mean the multi-word interests they obviously mean.
/// Applied ONLY here - doing it during normalisation would corrupt a
/// legitimately hyphenated interest name such as "e-commerce".
final RegExp _separatorRun = RegExp(r'[-_]+');
final RegExp _whitespaceRun = RegExp(r'\s+');
final RegExp _hasLetter = RegExp(r'\p{L}', unicode: true);

/// The readable form stored in interests_interest.name - spaces kept.
String hashtagDisplayName(String raw) =>
    raw.replaceAll(_separatorRun, ' ').trim().replaceAll(_whitespaceRun, ' ');

/// The key form stored in interests_interest.normalized_name - whitespace
/// removed entirely, lowercased. Mirrors user_service normalize_key() exactly;
/// a key derived differently matches nothing and creates a duplicate of the row
/// it failed to find.
String hashtagNormalizeKey(String value) =>
    value.trim().replaceAll(_whitespaceRun, '').toLowerCase();

/// A hashtag is only a hashtag if it contains a letter. "#2024" is a year and
/// "#1" is a rank; neither is an interest, and the taxonomy should not grow one.
bool _isTaggable(String raw) => _hasLetter.hasMatch(raw);

/// Readable interest names for every hashtag in [text], in order, deduplicated.
///
/// "#north-edsa" gives "north edsa" - the readable form, not the squashed key,
/// because that is the name the backends will store if the tag is new.
List<String> extractHashtags(String text) {
  if (text.isEmpty) return const [];

  final seen = <String>{};
  final names = <String>[];

  for (final match in hashtagPattern.allMatches(text)) {
    final raw = match.group(1);
    if (raw == null || !_isTaggable(raw)) continue;

    final readable = hashtagDisplayName(raw);
    final key = hashtagNormalizeKey(readable);
    if (key.isEmpty || !seen.add(key)) continue;
    names.add(readable);
  }

  return names;
}

/// One run of text, flagged as a hashtag or not.
class HashtagSpan {
  final String text;
  final bool isHashtag;

  const HashtagSpan(this.text, {this.isHashtag = false});
}

/// Split [text] into plain and hashtag runs, for rendering.
List<HashtagSpan> splitHashtagSpans(String text) {
  if (text.isEmpty) return const [HashtagSpan('')];

  final spans = <HashtagSpan>[];
  var index = 0;

  for (final match in hashtagPattern.allMatches(text)) {
    final raw = match.group(1);
    // Left as plain text rather than skipped, or "#2024" would vanish from
    // the caption instead of merely not being a link.
    if (raw == null || !_isTaggable(raw)) continue;

    if (match.start > index) {
      spans.add(HashtagSpan(text.substring(index, match.start)));
    }
    spans.add(
        HashtagSpan(text.substring(match.start, match.end), isHashtag: true));
    index = match.end;
  }

  if (index < text.length) spans.add(HashtagSpan(text.substring(index)));
  return spans.isEmpty ? [HashtagSpan(text)] : spans;
}

/// Text as spans: hashtags tappable, everything else linkified.
///
/// [onHashtagTap] receives the READABLE name ("north edsa"), not the slug -
/// callers search on it, and prose mentions a topic with the spaces in where
/// the squashed key would only match the hashtag spelling.
///
/// The recognizer is created inline and not disposed, matching linkifySpans in
/// this same package. It is a per-render allocation on a short-lived span; the
/// alternative is making every text-rendering widget stateful purely to own
/// them.
List<InlineSpan> hashtagifySpans(
  String text,
  TextStyle baseStyle, {
  required Color hashtagColor,
  required void Function(String name) onHashtagTap,
}) {
  final out = <InlineSpan>[];

  for (final span in splitHashtagSpans(text)) {
    if (span.isHashtag) {
      // The leading "#" is dropped before deriving the name - it is syntax,
      // not part of the interest.
      final name = hashtagDisplayName(span.text.substring(1));
      out.add(TextSpan(
        text: span.text,
        style: baseStyle.copyWith(
          color: hashtagColor,
          fontWeight: FontWeight.w600,
        ),
        recognizer: TapGestureRecognizer()..onTap = () => onHashtagTap(name),
      ));
    } else {
      out.addAll(linkifySpans(span.text, baseStyle));
    }
  }

  return out;
}

/// Open the topic's own feed for a tapped hashtag.
///
/// Addressed by the normalized KEY, not the readable name: it is what the
/// topic endpoint resolves on and what a Popular Topics row links to, so
/// "#North-Edsa" typed in a caption and the row for "north edsa" land on the
/// same screen.
///
/// Pushed rather than switched to, so Back returns to the post the tag was
/// read in instead of stranding the reader elsewhere.
void openHashtagTopic(BuildContext context, String name) {
  final slug = hashtagNormalizeKey(name);
  if (slug.isEmpty) return;
  context.push('/topics/${Uri.encodeComponent(slug)}');
}
