// Popular Topics - the ranked-list layout (1b).
//
// What is pinned here is the stuff that only breaks visually: a loader that is
// a different height than the row it stands in for, a rank that does not mark
// the leader, and the two things that must NOT appear on a card - a post count
// ("cards carry topic name, category label and participant avatars only") and
// any follow control.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/reusables/widgets/popular_topics.dart';
import 'package:chatterloop_app/models/user_models/popular_topic_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PopularTopic _topic({
  String category = 'Photography',
  int posts = 412,
  List<PopularTopicFace> faces = const [],
}) =>
    PopularTopic(
      id: 1,
      name: 'sunset series',
      slug: 'sunsetseries',
      category: category,
      score: 12.0,
      posts: posts,
      faces: faces,
    );

Future<void> _pumpRow(
  WidgetTester tester, {
  required int rank,
  PopularTopic? topic,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildCLTheme(Brightness.light),
    home: Scaffold(
      body: SizedBox(
        width: 390, // the design's frame
        child: CLPopularTopicsRow(
          topic: topic ?? _topic(),
          rank: rank,
          onTap: () {},
        ),
      ),
    ),
  ));
}

Color _rankColour(WidgetTester tester, String rank) =>
    tester.widget<Text>(find.text(rank)).style!.color!;

void main() {
  group('the chart reads as a chart', () {
    testWidgets('the leader is brand-coloured and the rest are muted',
        (tester) async {
      await _pumpRow(tester, rank: 1);
      final first = _rankColour(tester, '1');

      await _pumpRow(tester, rank: 2);
      final second = _rankColour(tester, '2');

      expect(first, isNot(second),
          reason: 'rank 1 must stand out from the rows below it');
    });

    testWidgets('a row carries name and category, and nothing numeric',
        (tester) async {
      await _pumpRow(tester, rank: 1);

      expect(find.text('#sunsetseries'), findsOneWidget);
      expect(find.text('Photography'), findsOneWidget);

      // The count is still in the payload; it must not be drawn.
      expect(find.textContaining('412'), findsNothing);
      expect(find.textContaining('post'), findsNothing);
    });

    testWidgets('there is no follow control on a topic row', (tester) async {
      await _pumpRow(tester, rank: 1);
      expect(find.textContaining('Follow'), findsNothing);
    });

    testWidgets('the header card carries no follow control either',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(width: 390, child: CLTopicHeaderCard(topic: _topic())),
        ),
      ));

      expect(find.text('#sunsetseries'), findsOneWidget);
      expect(find.text('Photography'), findsOneWidget);
      expect(find.textContaining('Follow'), findsNothing);
    });
  });

  group('layout', () {
    testWidgets('the skeleton is exactly as tall as the row it stands in for',
        (tester) async {
      // The invariant that matters: a loader of a different height makes the
      // card resize when the data lands. Asserted as an equality rather than a
      // magic number, so it survives a deliberate metric change.
      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CLPopularTopicsRow(topic: _topic(), rank: 1, onTap: () {}),
                const CLPopularTopicsRowSkeleton(),
              ],
            ),
          ),
        ),
      ));

      expect(
        tester.getSize(find.byType(CLPopularTopicsRowSkeleton)).height,
        tester.getSize(find.byType(CLPopularTopicsRow)).height,
      );
    });

    testWidgets('the category pill hugs its label instead of filling the row',
        (tester) async {
      // A Container with an `alignment` expands to its bounded constraints
      // rather than sizing to its child - which stretched this pill across the
      // whole row once before, and is invisible in a static read of the tree.
      Future<double> widthFor(String category) async {
        await _pumpRow(tester, rank: 1, topic: _topic(category: category));
        final pill = find.ancestor(
          of: find.text(category),
          matching: find.byType(Container),
        );
        return tester.getSize(pill.first).width;
      }

      final short = await widthFor('Tech');
      final long = await widthFor('Pets and Animals');

      expect(short, lessThan(150));
      expect(long, greaterThan(short),
          reason: 'a longer category must produce a wider pill');
      expect(long, lessThanOrEqualTo(kTopicPillMaxWidth));
    });

    testWidgets('the same category always gets the same colour',
        (tester) async {
      // Hashed, not positional: the colour must not change as the chart
      // reorders, and it must agree with the web for the same category.
      Future<Color> colourFor(String category, int rank) async {
        await _pumpRow(tester, rank: rank, topic: _topic(category: category));
        final pill = tester.widget<Container>(find
            .ancestor(
                of: find.text(category), matching: find.byType(Container))
            .first);
        return (pill.decoration as BoxDecoration).color!;
      }

      expect(await colourFor('Technology', 1), await colourFor('Technology', 5));
      expect(await colourFor('Technology', 1),
          isNot(await colourFor('Food and Drink', 1)));
    });

    testWidgets('a long category truncates instead of widening the row',
        (tester) async {
      await _pumpRow(
        tester,
        rank: 1,
        topic: _topic(
            category: 'An Extremely Long Category Name That Would Overflow'),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(CLPopularTopicsRow)).width, 390);
    });

    testWidgets('avatars lap each other rather than sitting side by side',
        (tester) async {
      final faces = List.generate(
        3,
        (i) => PopularTopicFace(
          entityId: 'e$i',
          name: 'P$i',
          profile: null,
          initials: 'P$i',
        ),
      );
      await _pumpRow(tester, rank: 1, topic: _topic(faces: faces));

      // Three 24px avatars lapping by 9 occupy 24 + 2*15 = 54, not 72.
      expect(
        tester.getSize(find.byType(Stack).first).width,
        kTopicFaceSize + 2 * (kTopicFaceSize - kTopicFaceOverlap),
      );
    });
  });
}
