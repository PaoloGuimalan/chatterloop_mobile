// #hashtags in captions and comments.
//
// The parse is the part worth pinning, and the stakes here are higher than for
// mentions: the backends turn these into permanent rows in interests_interest
// at post/comment creation time. A token this app highlights but the server
// does not save is a hashtag that visibly did nothing; a token the server saves
// but this app does not highlight is an interest the author never knew they
// created.
//
// The expectations below are the OUTPUT OF THE OTHER FOUR IMPLEMENTATIONS on
// the same inputs, verified to agree 17/17:
//
//   moderation_service/core/vocabulary.py         hashtags()   <- canonical
//   user_service/interests/services/hashtags.py   extract_hashtags()
//   server/reusables/hooks/hashtags.js            extractHashtags()
//   webapp/src/reusables/hooks/hashtags.ts        extractHashtags()

import 'package:chatterloop_app/core/utils/hashtags.dart';
import 'package:flutter_test/flutter_test.dart';

/// The raw hashtag text of each highlighted span, in order - what the reader
/// actually sees styled, as opposed to the interest name it resolves to.
List<String> highlightedIn(String text) => splitHashtagSpans(text)
    .where((span) => span.isHashtag)
    .map((span) => span.text)
    .toList();

void main() {
  group('cross-implementation contract', () {
    // One case per rule the five implementations share. Each expectation is
    // the readable interest NAME, which is what gets stored.
    const cases = <String, List<String>>{
      'riding at #north-edsa today': ['north edsa'],
      '#docker_swarm and #hiking': ['docker swarm', 'hiking'],
      'didn&#039;t get a chance': [],
      'see https://x.com/a#frag': [],
      '#2024 recap': [],
      '#café culture': ['café'],
      'a#b not a tag': [],
      '(#parens) work': ['parens'],
      '#newsandculture': ['newsandculture'],
      '#a': [],
      '#TwoWords-Here': ['TwoWords Here'],
      'email me@x.com #ok': ['ok'],
      'multi #one #two #one': ['one', 'two'],
      '#under_score_deep': ['under score deep'],
      'trailing #tag.': ['tag'],
      '#123abc': ['123abc'],
      '#_leading': ['leading'],
    };

    cases.forEach((input, expected) {
      test(input, () => expect(extractHashtags(input), expected));
    });
  });

  group('what counts as a hashtag', () {
    test('an HTML numeric entity is not a hashtag', () {
      // This platform stores authored text escaped, so "didn&#039;t" contains
      // "#039". Before the lookbehind existed that was tagged as a declared
      // interest on every conversational document in the corpus.
      expect(extractHashtags('that&#039;s mine &amp; his'), isEmpty);
    });

    test('a URL fragment is an address, not a tag', () {
      expect(extractHashtags('https://example.com/page#section'), isEmpty);
    });

    test('a purely numeric tag is a year or a rank, not an interest', () {
      expect(extractHashtags('#2024 #1 #42'), isEmpty);
    });

    test('accented letters count, because Python\'s \\w matches them', () {
      // Dart's \w does not, which is why the pattern uses \p{L}. Disagreeing
      // here would mean the server saving an interest this app never
      // highlighted.
      expect(extractHashtags('#café #niño'), ['café', 'niño']);
    });
  });

  group('the two name forms', () {
    test('separators become spaces in the readable name', () {
      expect(hashtagDisplayName('north-edsa'), 'north edsa');
      expect(hashtagDisplayName('docker_swarm'), 'docker swarm');
    });

    test('the key removes whitespace entirely and lowercases', () {
      // Mirrors user_service normalize_key(). "#NorthEdsa" typed in a caption
      // and the interest "north edsa" must land on the same row.
      expect(hashtagNormalizeKey('north edsa'), 'northedsa');
      expect(hashtagNormalizeKey('News and Culture'), 'newsandculture');
      expect(hashtagNormalizeKey(hashtagDisplayName('North-Edsa')),
          hashtagNormalizeKey('north edsa'));
    });
  });

  group('rendering', () {
    test('non-hashtag text survives as plain spans', () {
      final spans = splitHashtagSpans('ride at #north-edsa today');
      expect(spans.map((s) => s.text).join(), 'ride at #north-edsa today');
    });

    test('an untaggable "#" is left in the text rather than dropped', () {
      // It must not be highlighted, but it must still be readable - "#2024"
      // vanishing from a caption would be worse than it not being a link.
      final spans = splitHashtagSpans('recap of #2024 here');
      expect(spans.map((s) => s.text).join(), 'recap of #2024 here');
      expect(highlightedIn('recap of #2024 here'), isEmpty);
    });

    test('the highlighted span keeps the "#" the author typed', () {
      // The span shows "#north-edsa" while the interest is "north edsa" - the
      // display form and the stored form are deliberately different.
      expect(highlightedIn('at #north-edsa'), ['#north-edsa']);
    });
  });
}
