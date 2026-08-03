// The post feature's logic and layout.
//
// The reaction arithmetic is the part worth pinning: it runs optimistically on
// three surfaces (post card, comment row, and the newsfeed next), and a wrong
// tally is the kind of bug that only shows up as a count that drifts the longer
// you use the app.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_attachments.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_card.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_reactions.dart';
import 'package:chatterloop_app/models/post_models/newsfeed_models.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _author = PostPreviewAuthor(
  entityId: 'e1',
  type: 'user',
  displayName: 'Bartholomew Maximilian Villaverde-Santos',
  handle: 'bart',
  isVerified: true,
);

PostReference _ref(String id, String type) =>
    PostReference(referenceId: id, reference: 'https://x/$id', mediaType: type);

PostPreview _post({
  List<PostReference> references = const [],
  List<PostReactionCount> reactions = const [],
  String? entityReaction,
  bool isShared = false,
  int comments = 0,
}) =>
    PostPreview(
      postId: 'p1',
      caption: 'Sunrise run before the rain came in.',
      datePosted: DateTime.now().subtract(const Duration(hours: 2)),
      references: references,
      reactions: reactions,
      author: _author,
      likesCount: 0,
      commentsCount: comments,
      isShared: isShared,
      entityReaction: entityReaction,
    );

void main() {
  group('reaction verb', () {
    test('no reaction yet -> add', () {
      expect(
        reactionMethodFor(currentEmojiId: null, tappedEmojiId: 'e_like'),
        ReactionMethod.add,
      );
      expect(
        reactionMethodFor(currentEmojiId: '', tappedEmojiId: 'e_like'),
        ReactionMethod.add,
      );
    });

    test('tapping a different one -> swap', () {
      expect(
        reactionMethodFor(currentEmojiId: 'e_like', tappedEmojiId: 'e_love'),
        ReactionMethod.swap,
      );
    });

    test('tapping the same one -> remove', () {
      expect(
        reactionMethodFor(currentEmojiId: 'e_like', tappedEmojiId: 'e_like'),
        ReactionMethod.remove,
      );
    });
  });

  group('local reaction tallies', () {
    List<PostReactionCount> counts(Map<String, int> from) => from.entries
        .map((e) => PostReactionCount(emoji: e.key, count: e.value))
        .toList();

    Map<String, int> asMap(List<PostReactionCount> list) => {
          for (final reaction in list) reaction.emoji: reaction.count,
        };

    test('first reaction adds a tally', () {
      final result = applyReactionLocally(
        current: counts({'👍': 2}),
        previousEmojiId: null,
        nextEmojiId: '❤️',
      );
      expect(asMap(result), {'👍': 2, '❤️': 1});
    });

    test('swapping moves one across', () {
      final result = applyReactionLocally(
        current: counts({'👍': 3, '❤️': 1}),
        previousEmojiId: '👍',
        nextEmojiId: '❤️',
      );
      expect(asMap(result), {'👍': 2, '❤️': 2});
    });

    test('removing the last of an emoji drops it entirely', () {
      // Otherwise the row keeps rendering a glyph with a 0 beside it.
      final result = applyReactionLocally(
        current: counts({'👍': 3, '😂': 1}),
        previousEmojiId: '😂',
        nextEmojiId: null,
      );
      expect(asMap(result), {'👍': 3});
    });

    test('tallies come back biggest first', () {
      final result = applyReactionLocally(
        current: counts({'👍': 1, '❤️': 5}),
        previousEmojiId: null,
        nextEmojiId: '😂',
      );
      expect(result.first.emoji, '❤️');
    });

    test('an unknown previous id never drives a count negative', () {
      // A stale entity_reaction (an emoji retired server-side) must not
      // subtract from a tally that never had it.
      final result = applyReactionLocally(
        current: counts({'👍': 1}),
        previousEmojiId: '🤷',
        nextEmojiId: '👍',
      );
      expect(asMap(result), {'👍': 2});
    });
  });

  group('post model', () {
    test('a share exposes the post it points at', () {
      final shared = _post(
        references: [_ref('r1', 'shared_post')],
        isShared: true,
      );
      // The composer stores the original's id as the reference value.
      expect(shared.sharedPostId, 'https://x/r1');
      // ...and it is NOT media, so it must never reach the attachment grid.
      expect(displayableReferences(shared.references), isEmpty);
    });

    test('only image and video references are displayable', () {
      final post = _post(references: [
        _ref('a', 'image/jpeg'),
        _ref('b', 'video/mp4'),
        _ref('c', 'shared_post'),
        _ref('d', 'application/pdf'),
      ]);
      expect(displayableReferences(post.references).length, 2);
    });

    test('reactionTotal sums every emoji', () {
      final post = _post(reactions: const [
        PostReactionCount(emoji: '👍', count: 3),
        PostReactionCount(emoji: '❤️', count: 2),
      ]);
      expect(post.reactionTotal, 5);
    });

    test('copyWith can clear the viewer reaction', () {
      final post = _post(entityReaction: 'e_like');
      expect(post.copyWith(clearEntityReaction: true).entityReaction, isNull);
      // Without the explicit flag, null means "leave it alone" - otherwise
      // every copyWith that didn't mention it would wipe it.
      expect(post.copyWith(commentsCount: 4).entityReaction, 'e_like');
    });
  });

  test('a comment parses its thread and reaction state', () {
    final comment = PostComment.fromJson(<String, dynamic>{
      'comment_id': 'c1',
      'parent_comment': null,
      'text': 'Great shot',
      'created_at': '2026-07-28T09:12:00Z',
      'entity': {
        'id': 'e2',
        'type': 'user',
        'details': {'first_name': 'Bea', 'last_name': 'Cruz', 'username': 'bea'},
      },
      'preview': [
        {'emoji': '👍', 'count': 2}
      ],
      'entity_reaction': 'e_like',
      'reply_count': 3,
    });

    expect(comment.parentId, isNull);
    expect(comment.author.displayName, 'Bea Cruz');
    expect(comment.reactionTotal, 2);
    expect(comment.entityReaction, 'e_like');
    expect(comment.replyCount, 3);
  });

  group('layout at 360px', () {
    // Empty by default so ReactionSummary never reaches for the network from
    // build(); a test that cares about glyphs seeds its own afterwards.
    setUp(() => ReactionPalette.seed(const []));

    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ));
      await tester.pump();
    }

    testWidgets('a post with no media lays out', (tester) async {
      await pump(tester, PostCard(post: _post(comments: 4)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('every attachment grid arrangement lays out', (tester) async {
      // 1 / 2 / 3 / 4+ are four different layouts; the last also draws the
      // "+N" overflow scrim.
      for (final count in [1, 2, 3, 5]) {
        await pump(
          tester,
          PostAttachments(
            references: [
              for (var i = 0; i < count; i++) _ref('r$i', 'image/jpeg'),
            ],
          ),
        );
        expect(tester.takeException(), isNull, reason: '$count attachment(s)');
      }
    });

    testWidgets('a tally renders the GLYPH for its emoji id, never the id',
        (tester) async {
      // preview[].emoji is a ForeignKey, so DRF serializes it as the emoji's
      // PK - a uuid. Rendering it directly is what put uuids where the emoji
      // should be; the glyph has to be resolved through the palette.
      const uuid = 'b3f1c2de-0000-4a11-9c33-5f6a7b8c9d01';
      ReactionPalette.seed(const [
        Emoji(
          emojiId: uuid,
          title: 'like',
          content: '👍',
          theme: '#7d7d7d',
          priority: 0,
        ),
      ]);
      await pump(
        tester,
        PostCard(
          post: _post(
            reactions: const [PostReactionCount(emoji: uuid, count: 4)],
          ),
        ),
      );
      // A second frame for the palette FutureBuilder.
      await tester.pump();

      expect(find.textContaining(uuid), findsNothing);
      expect(find.text('👍'), findsWidgets);
      expect(find.text('4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a zero tally is not rendered', (tester) async {
      // The server keeps a row at zero once an emoji has been used on a post.
      ReactionPalette.seed(const []);
      await pump(
        tester,
        PostCard(
          post: _post(reactions: const [PostReactionCount(emoji: 'e1', count: 0)]),
        ),
      );
      await tester.pump();
      expect(find.text('0'), findsNothing);
    });

    testWidgets('a reacted post shows its own glyph slot', (tester) async {
      await pump(tester, PostCard(post: _post(entityReaction: 'e_like')));
      // Palette hasn't loaded in a test, so glyphFor is null and the action
      // falls back to the icon + "Reacted" - which must still lay out.
      expect(find.text('Reacted'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
