// @mentions in comments.
//
// The parse is the part worth pinning, because drift is SILENT: this file's
// pattern has to agree character-for-character with the server's
// (newsfeed/services/comment_mentions.py MENTION_PATTERN, and Node's
// extractMentionUsernames). A token this app highlights but the server doesn't
// parse renders as a mention and notifies nobody - which looks like a bug in
// notifications, not in a regex.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/utils/chat_mentions.dart';
import 'package:chatterloop_app/core/utils/comment_mentions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The mention text of each highlighted span, in order.
List<String> mentionsIn(String text) => splitCommentMentionSpans(text)
    .where((span) => span.isMention)
    .map((span) => span.text)
    .toList();

void main() {
  group('what counts as a mention', () {
    test('at the start, or after whitespace', () {
      expect(mentionsIn('@ana hello'), ['@ana']);
      expect(mentionsIn('hi @ana'), ['@ana']);
      expect(mentionsIn('hi @ana and @bea'), ['@ana', '@bea']);
    });

    test('an email address is not a mention', () {
      // The whole point of the leading (^|\s) - "you@example.com" must not
      // notify @example.
      expect(mentionsIn('mail me at you@example.com'), isEmpty);
    });

    test('a page is mentioned exactly like a person', () {
      // The backend resolves a handle against usernames AND realm slugs, so
      // there is nothing to distinguish here.
      expect(mentionsIn('ask @manila-runners'), ['@manila-runners']);
    });

    test('handles run to 30 characters and no further', () {
      final ok = 'a' * 30;
      final tooLong = 'a' * 31;
      expect(mentionsIn('hi @$ok'), ['@$ok']);
      // Over-long matches NOTHING rather than being truncated to a different
      // handle - the safe direction, and what the server does.
      expect(mentionsIn('hi @$tooLong'), isEmpty);
    });

    test('a bare @ is not a mention', () {
      expect(mentionsIn('@ '), isEmpty);
      expect(mentionsIn('@'), isEmpty);
    });

    test('punctuation ends a mention, and the dot rule is inherited', () {
      expect(mentionsIn('thanks @ana!'), ['@ana']);
      expect(mentionsIn('cc @ana, @bea'), ['@ana', '@bea']);
      // Documented quirk shared with the server: the class includes "." and is
      // greedy, so a trailing full stop is swallowed. The server compensates
      // when resolving; here it only over-highlights by one character.
      expect(mentionsIn('thanks @ana.'), ['@ana.']);
    });

    test('handles come back deduped and lowercased', () {
      expect(extractMentionHandles('@Ana hi @ana and @BEA'), ['ana', 'bea']);
      expect(extractMentionHandles(''), isEmpty);
    });
  });

  group('composing', () {
    test('the panel opens at @ and closes once the mention is finished', () {
      // activeMentionQuery is shared with chat - same "am I typing a mention"
      // question, so deliberately not a second implementation.
      expect(activeMentionQuery('hi @an', 6)?.query, 'an');
      expect(activeMentionQuery('hi @an', 6)?.start, 3);
      expect(activeMentionQuery('hi @ana ', 8), isNull);
      expect(activeMentionQuery('mail you@ex', 11), isNull);
    });

    test('inserting replaces the query and trails a space', () {
      final result = insertCommentMention('hi @an', 3, 6, 'anabelle');
      expect(result.text, 'hi @anabelle ');
      expect(result.cursor, result.text.length);
    });

    test('inserting mid-sentence keeps what follows, and the caret with it',
        () {
      // The caret landing after the inserted mention rather than at the end is
      // the difference between typing on and hunting for your place.
      final result = insertCommentMention('hi @an, are you free?', 3, 6, 'ana');
      expect(result.text, 'hi @ana , are you free?');
      expect(result.cursor, 'hi @ana '.length);
    });
  });

  group('rendering', () {
    testWidgets('mentions are styled, links still linkify, order preserved',
        (tester) async {
      late List<InlineSpan> spans;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          spans = commentTextSpans(
            'hi @ana see https://example.com ok',
            const TextStyle(fontSize: CLType.body),
            mentionColor: const Color(0xFF1C7DEF),
          );
          return const SizedBox.shrink();
        }),
      ));

      final mention = spans
          .whereType<TextSpan>()
          .firstWhere((span) => span.text == '@ana');
      expect(mention.style?.color, const Color(0xFF1C7DEF));
      expect(mention.style?.fontWeight, FontWeight.w700);

      // The link survived the mention pass - splitting mentions FIRST is what
      // stops a URL swallowing an @ inside it, and vice versa.
      final link = spans
          .whereType<TextSpan>()
          .firstWhere((span) => span.text == 'https://example.com');
      expect(link.style?.decoration, TextDecoration.underline);

      // Nothing dropped on the way through either pass.
      final rebuilt =
          spans.whereType<TextSpan>().map((span) => span.text ?? '').join();
      expect(rebuilt, 'hi @ana see https://example.com ok');
    });

    testWidgets('an unknown handle is styled but inert', (tester) async {
      // Unlike chat, a comment has no member list to check against, so every
      // well-formed token highlights. One that matches nobody is simply text
      // that notifies no one - same deal the server gives it.
      expect(mentionsIn('hi @nobody_at_all'), ['@nobody_at_all']);
    });
  });
}
