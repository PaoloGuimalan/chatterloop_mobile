// The post feature's logic and layout.
//
// The reaction arithmetic is the part worth pinning: it runs optimistically on
// three surfaces (post card, comment row, and the newsfeed next), and a wrong
// tally is the kind of bug that only shows up as a count that drifts the longer
// you use the app.

import 'package:chatterloop_app/core/design/rails.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_attachments.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_card.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_comments.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_composer.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_item.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_reactions.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_tagging.dart';
import 'package:chatterloop_app/models/post_models/newsfeed_models.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/search_result_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
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

SearchResultUser _searchUser(String name, String entityId) => SearchResultUser(
      id: 'a-$entityId',
      entityId: entityId,
      username: name.toLowerCase(),
      firstName: name,
      middleName: '',
      lastName: '',
      hasConnection: false,
      connectionAccomplished: false,
      isActionByEntity: false,
    );

PostPreviewAuthor _tag(String name, {bool realm = false}) => PostPreviewAuthor(
      entityId: 'e-$name',
      type: realm ? 'realm' : 'user',
      displayName: name,
      handle: name.toLowerCase(),
      isVerified: false,
    );

PostPreview _post({
  List<PostReference> references = const [],
  List<PostReactionCount> reactions = const [],
  String? entityReaction,
  bool isShared = false,
  int comments = 0,
  List<PostPreviewAuthor> tagged = const [],
  bool saved = false,
  bool archived = false,
  String privacy = 'public',
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
      tagged: tagged,
      isSaved: saved,
      isArchived: archived,
      privacyStatus: privacy,
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

  group('tagged entities', () {
    test('parsed off the post payload', () {
      final post = PostPreview.fromJson(<String, dynamic>{
        'post_id': 'p1',
        'caption': '',
        'entity': {
          'id': 'e1',
          'type': 'user',
          'details': {'first_name': 'Paulo', 'username': 'paulo'},
        },
        'tagging': [
          {
            'post_tag_id': 't1',
            'entity': {
              'id': 'e2',
              'type': 'user',
              'details': {'first_name': 'Bea', 'username': 'bea'},
            }
          },
          // A tag whose entity didn't resolve has no name to render.
          {'post_tag_id': 't2', 'entity': null},
        ],
      });
      expect(post.tagged.length, 1);
      expect(post.tagged.single.displayName, 'Bea');
    });

    testWidgets('names up to three, then collapses the rest', (tester) async {
      Future<String> render(List<PostPreviewAuthor> tagged) async {
        late List<InlineSpan> spans;
        await tester.pumpWidget(MaterialApp(
          theme: buildCLTheme(Brightness.light),
          home: Builder(builder: (context) {
            spans = taggingSummarySpans(
              context,
              tagged,
              baseStyle: const TextStyle(),
              linkColor: const Color(0xFF000000),
            );
            return const SizedBox.shrink();
          }),
        ));
        return spans
            .whereType<TextSpan>()
            .map((span) => span.text ?? '')
            .join();
      }

      expect(await render(const []), '');
      expect(await render([_tag('Bea')]), ' is with Bea');
      expect(await render([_tag('Bea'), _tag('Dan')]), ' is with Bea and Dan');
      expect(await render([_tag('Bea'), _tag('Dan'), _tag('Kaye')]),
          ' is with Bea, Dan and Kaye');
      // Past three, the last separator stays "," because the collapse follows.
      expect(
        await render([_tag('Bea'), _tag('Dan'), _tag('Kaye'), _tag('Migs')]),
        ' is with Bea, Dan, Kaye and 1 other',
      );
      expect(
        await render([
          _tag('Bea'),
          _tag('Dan'),
          _tag('Kaye'),
          _tag('Migs'),
          _tag('Ella'),
        ]),
        ' is with Bea, Dan, Kaye and 2 others',
      );
    });
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

    testWidgets('a heavily tagged header wraps instead of overflowing',
        (tester) async {
      await pump(
        tester,
        PostCard(
          post: _post(tagged: [
            _tag('Bartholomew Maximilian'),
            _tag('Marisse Alonzo'),
            _tag('Manila Runners', realm: true),
            _tag('Kaye Sandoval'),
          ]),
        ),
      );
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

    testWidgets('a feed row opens the post from its comments, and only there',
        (tester) async {
      // The row's body is NOT a way in. Tapping a video in a row has to play
      // it, and tapping a link has to follow it - neither can navigate away
      // mid-gesture - so the comment affordances are the only route into the
      // post. Both of them count: the action bar's "Comment" and the "N
      // comments" line above it.
      var opened = 0;
      await pump(
        tester,
        PostItem(
          post: _post(comments: 2, tagged: [_tag('Bea')]),
          onOpen: () => opened++,
        ),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.textContaining('Sunrise run'));
      await tester.pump();
      expect(opened, 0, reason: 'the caption is not a tap target');

      await tester.tap(find.text('Comment'));
      await tester.pump();
      expect(opened, 1);

      await tester.tap(find.text('2 comments'));
      await tester.pump();
      expect(opened, 2);
    });

    testWidgets('a feed row skeleton lays out', (tester) async {
      await pump(tester, const PostItemSkeleton());
      expect(tester.takeException(), isNull);
    });

    testWidgets('the header shows the audience as an icon', (tester) async {
      // Icon only - a word on every post would be noise, since most are public.
      // The icons come from the composer's own table (postPrivacyIcon), so the
      // one on a post always matches the chip that published it.
      for (final (status, icon) in [
        ('public', Icons.public),
        ('connections', Icons.group),
        ('private', Icons.lock_outline),
      ]) {
        await pump(tester, PostCard(post: _post(privacy: status)));
        expect(find.byIcon(icon), findsOneWidget, reason: status);
        expect(tester.takeException(), isNull, reason: status);
      }
    });

    testWidgets('the audience icon is as small as the archived one',
        (tester) async {
      await pump(
        tester,
        PostCard(post: _post(privacy: 'private', archived: true)),
      );
      final privacy = tester.getSize(find.byIcon(Icons.lock_outline));
      final archived = tester.getSize(find.byIcon(Icons.archive_outlined));
      expect(privacy, archived);
    });

    testWidgets('a reacted post shows its own glyph slot', (tester) async {
      await pump(tester, PostCard(post: _post(entityReaction: 'e_like')));
      // Palette hasn't loaded in a test, so glyphFor is null and the action
      // falls back to the icon + "Reacted" - which must still lay out.
      expect(find.text('Reacted'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // Which ⋯ entries each viewer gets. The gate is the ACTING ENTITY id, not the
  // account id, which is what lets a page manage its own posts while you're
  // acting as that page - and what stops your personal account managing them
  // when you switch back. Every one of these would 403 server-side anyway; the
  // point is not to offer a button that can't work.
  group('post and comment options', () {
    setUp(() => ReactionPalette.seed(const []));

    /// Switch the store's acting entity, the way an entity switch does.
    void actAs(String entityId,
        {bool isPrivate = false, ActiveEntity? activeEntity}) {
      appStore.dispatch(DispatchModel(
        setUserAuthT,
        UserAuth(
          true,
          UserAccount('account-1', 'me', 'Me', '', 'Mine', null, true, true,
              null, null, null, null,
              personalEntityId: entityId,
              activeEntity: activeEntity,
              isPrivate: isPrivate),
        ),
      ));
    }

    // Back to signed-out, so a later test never inherits an acting entity.
    tearDown(() => actAs(''));

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

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
    }

    testWidgets('the author gets save, archive and delete', (tester) async {
      actAs(_author.entityId);
      await pump(tester, PostCard(post: _post()));
      await openMenu(tester);

      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Archive'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('anyone else gets save only', (tester) async {
      actAs('somebody-else');
      await pump(tester, PostCard(post: _post()));
      await openMenu(tester);

      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Archive'), findsNothing);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('the labels flip with the post state', (tester) async {
      actAs(_author.entityId);
      await pump(tester, PostCard(post: _post(saved: true)));
      await openMenu(tester);

      expect(find.text('Unsave'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
    });

    testWidgets('an archived post offers no save at all', (tester) async {
      // Saving is a bookmark for something in a feed; an archived post is in
      // nobody's.
      actAs(_author.entityId);
      await pump(tester, PostCard(post: _post(archived: true)));
      await openMenu(tester);

      expect(find.text('Save'), findsNothing);
      expect(find.text('Unsave'), findsNothing);
      expect(find.text('Unarchive'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets("a stranger's archived post has no menu button", (tester) async {
      // Nothing left to offer - so no ⋯ rather than one that opens empty.
      actAs('somebody-else');
      await pump(tester, PostCard(post: _post(archived: true)));
      expect(find.byIcon(Icons.more_horiz), findsNothing);
    });

    testWidgets('a nested shared post carries no options', (tester) async {
      // showEngagement false is the shared-post recursion mode: the embedded
      // original is a quotation, and it can be opened in its own right.
      actAs(_author.entityId);
      await pump(
          tester, PostCard(post: _post(), showEngagement: false));
      expect(find.byIcon(Icons.more_horiz), findsNothing);
    });

    testWidgets('a comment ⋯ appears only on your own', (tester) async {
      final mine = PostComment(
        commentId: 'c1',
        text: 'Mine',
        author: _author,
        createdAt: DateTime.now(),
        reactions: const [],
        replyCount: 0,
      );

      actAs(_author.entityId);
      await pump(
        tester,
        CommentRow(comment: mine, busy: false, onReact: () {}, onDelete: () {}),
      );
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);

      actAs('somebody-else');
      await pump(
        tester,
        CommentRow(comment: mine, busy: false, onReact: () {}, onDelete: () {}),
      );
      expect(find.byIcon(Icons.more_horiz), findsNothing);
    });

    // Writing on someone's profile is a post of YOUR OWN that tags them -
    // there is no "post to their wall" server-side. So the composer opened
    // from a visited profile starts with that profile selected, and the one
    // opened from your own (or anywhere else) starts empty. Removable and
    // fully selectable either way.
    group('composer tagging', () {
      Future<void> openComposer(
        WidgetTester tester, {
        SearchResultUser? autoTag,
      }) async {
        await pump(
          tester,
          ProfileComposerCard(
            placeholder: "Share your thoughts…",
            autoTag: autoTag,
            onPosted: () {},
          ),
        );
        await tester.tap(find.text("Share your thoughts…"));
        await tester.pumpAndSettle();
      }

      testWidgets('a visited profile arrives pre-tagged', (tester) async {
        actAs('me');
        await openComposer(tester, autoTag: _searchUser('Bea', 'e-bea'));

        // The picker's own summary, plus the chip itself.
        expect(find.text("Tagged 1"), findsOneWidget);
        expect(find.text("Bea"), findsOneWidget);
      });

      testWidgets('your own profile starts with nobody tagged',
          (tester) async {
        actAs('me');
        await openComposer(tester);

        expect(find.text("Tag people or pages"), findsOneWidget);
        expect(find.text("Tagged 1"), findsNothing);
      });

      // "Mine" is the entity you are POSTING AS, and nothing else. Managing a
      // page doesn't make its profile yours: while you're on your personal
      // account it's another entity, so it pre-tags like a stranger's would.
      // Anything else would be a lie about where the post lands - the server
      // resolves the author from the acting entity, not from who administers
      // what.
      group('a page is only yours while you are it', () {
        final page = SearchResultUser(
          id: 'r1',
          entityId: 'e-page',
          username: 'manila-runners',
          firstName: 'Manila Runners',
          middleName: '',
          lastName: '',
          hasConnection: false,
          connectionAccomplished: false,
          isActionByEntity: false,
          type: 'realm',
        );

        Future<void> pumpFor(WidgetTester tester) async {
          await pump(
            tester,
            ProfileComposerCard.forProfile(
              profile: page,
              ownPlaceholder: "Publish a post",
              onPosted: () {},
            ),
          );
        }

        testWidgets('an ADMIN on their personal account is a visitor',
            (tester) async {
          // The reported bug: administering the page let you post as it.
          actAs('me');
          await pumpFor(tester);

          expect(find.text("Write on Manila Runners's page…"), findsOneWidget);
          expect(find.text("Publish a post"), findsNothing);

          await tester.tap(find.text("Write on Manila Runners's page…"));
          await tester.pumpAndSettle();
          expect(find.text("Tagged 1"), findsOneWidget);
        });

        testWidgets('switched to the page, it is yours', (tester) async {
          actAs('e-page',
              activeEntity:
                  const ActiveEntity(id: 'e-page', type: 'realm'));
          await pumpFor(tester);

          expect(find.text("Publish a post"), findsOneWidget);

          await tester.tap(find.text("Publish a post"));
          await tester.pumpAndSettle();
          expect(find.text("Tag people or pages"), findsOneWidget);
          expect(find.text("Tagged 1"), findsNothing);
        });
      });

      testWidgets('the Photo button sits on the left, Post on the right',
          (tester) async {
        actAs('me');
        await pump(
          tester,
          ProfileComposerCard(
            placeholder: "Share your thoughts…",
            onPosted: () {},
          ),
        );

        final card = tester.getRect(find.byType(ProfileComposerCard));
        final icon = tester.getRect(find.byIcon(Icons.image_outlined));
        final post = tester.getRect(find.text("Post"));

        // BOTH edges are measured, and both against the card's own edges
        // rather than its centre - each loose comparison passed a layout that
        // was still wrong. A centred Photo sat left of centre anyway (it shared
        // the row with a narrow Post), and a Post pushed inward by a Spacer's
        // leftover slack was still right of centre.
        expect(icon.left - card.left, lessThan(40));
        expect(card.right - post.right, lessThan(40));
        expect(icon.right, lessThan(post.left));
      });

      testWidgets('attachments preview as a scrollable rail of thumbnails',
          (tester) async {
        // Six is past what fits at 360px, which is the case that mattered: the
        // rail scrolls instead of the sheet growing a column of rows.
        await pump(
          tester,
          CLRailSection(
            title: "6 attachments",
            gap: 8,
            children: [
              for (var i = 0; i < 6; i++)
                PostMediaPreviewTile(
                  item: PendingMedia(
                    path: '/tmp/photo$i.jpg',
                    name: 'photo$i.jpg',
                    size: 2 * 1024 * 1024,
                  ),
                  onRemove: () {},
                ),
            ],
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(PostMediaPreviewTile), findsNWidgets(6));
        // A thumbnail each, not a filename each.
        expect(find.text('photo0.jpg'), findsNothing);
        // Removable in place - no need to reopen the picker to drop one.
        expect(find.byIcon(Icons.close), findsNWidgets(6));
      });

      testWidgets('a video attachment shows a play badge and its size',
          (tester) async {
        // The tile now renders the clip's own first frame (VideoFirstFrame)
        // with this badge over it - two picked videos used to be two identical
        // grey squares. No frame is available here, since nothing fakes the
        // video platform in this file, so what's asserted is the part that
        // holds either way: it reads as a video, and the size is shown because
        // that's the number that can hit the upload cap.
        await pump(
          tester,
          CLRailSection(
            title: "1 attachment",
            children: [
              PostMediaPreviewTile(
                item: PendingMedia(
                  path: '/tmp/clip.mp4',
                  name: 'clip.mp4',
                  size: 8 * 1024 * 1024,
                ),
                onRemove: () {},
              ),
            ],
          ),
        );

        expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
        expect(find.text('Video · 8.0 MB'), findsOneWidget);
      });

      // The audience a post starts with, matching what the server would apply
      // anyway when `privacy.status` is absent - so the sheet shows what will
      // actually happen rather than claiming Public and being overridden.
      test('a private profile defaults to contacts only', () {
        actAs('me');
        expect(defaultPostPrivacy(), 'public');

        actAs('me', isPrivate: true);
        expect(defaultPostPrivacy(), 'connections');

        // Profile privacy is a person-level setting; a page has none, so
        // posting AS one is public regardless.
        actAs('me',
            isPrivate: true,
            activeEntity: const ActiveEntity(id: 'e-page', type: 'realm'));
        expect(defaultPostPrivacy(), 'public');
      });
    });

    testWidgets('a comment with no delete handler has no ⋯', (tester) async {
      // A read-only surface (a feed preview) passes no handler even for your
      // own comment.
      actAs(_author.entityId);
      await pump(
        tester,
        CommentRow(
          comment: PostComment(
            commentId: 'c1',
            text: 'Mine',
            author: _author,
            createdAt: DateTime.now(),
            reactions: const [],
            replyCount: 0,
          ),
          busy: false,
          onReact: () {},
        ),
      );
      expect(find.byIcon(Icons.more_horiz), findsNothing);
    });
  });
}
