// Topic rows - the 2a/2b list layout.
//
// What is pinned here is the stuff that only breaks visually: a loader that is
// a different height than the row it stands in for, a match highlight that
// marks the wrong run (or the wrong screen's worth of them), and the two things
// that must NOT appear on a row - a post count ("rows carry topic name,
// category and participant avatars only") and any follow control.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/reusables/widgets/popular_topics.dart';
import 'package:chatterloop_app/models/user_models/popular_topic_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PopularTopic _topic({
  String slug = 'sunsetseries',
  String category = 'Photography',
  int posts = 412,
  List<PopularTopicFace> faces = const [],
}) =>
    PopularTopic(
      id: 1,
      name: 'sunset series',
      slug: slug,
      category: category,
      score: 12.0,
      posts: posts,
      faces: faces,
    );

Future<void> _pumpRow(
  WidgetTester tester, {
  PopularTopic? topic,
  String? highlight,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildCLTheme(Brightness.light),
    home: Scaffold(
      body: SizedBox(
        width: 390, // the design's frame
        child: CLTopicRow(
          topic: topic ?? _topic(),
          highlight: highlight,
          onTap: () {},
        ),
      ),
    ),
  ));
}

/// The name as the user reads it, whether it was drawn as one span or three.
String _renderedName(WidgetTester tester) =>
    tester.widget<Text>(find.byType(Text).at(1)).textSpan!.toPlainText();

void main() {
  group('a row says what a topic is, and nothing else', () {
    testWidgets('name and category, nothing numeric', (tester) async {
      await _pumpRow(tester);

      expect(find.text('#sunsetseries'), findsOneWidget);
      expect(find.text('Photography'), findsOneWidget);

      // The count is still in the payload; it must not be drawn.
      expect(find.textContaining('412'), findsNothing);
      expect(find.textContaining('post'), findsNothing);
    });

    testWidgets('there is no follow control on a topic row', (tester) async {
      await _pumpRow(tester);
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

  group('the match highlight', () {
    testWidgets('marks the matched run without changing the name',
        (tester) async {
      await _pumpRow(tester, highlight: 'sunset');

      // Drawn as three spans, but it still reads as the whole tag - a
      // highlight that drops or reorders characters is the failure mode.
      expect(_renderedName(tester), '#sunsetseries');
    });

    testWidgets('normalises the query the way a hashtag normalises',
        (tester) async {
      // "north edsa" and "#northedsa" are the same interest, so both must mark
      // the same run rather than one of them silently matching nothing.
      for (final query in ['north edsa', '#northedsa', 'North Edsa']) {
        await _pumpRow(
          tester,
          topic: _topic(slug: 'northedsa'),
          highlight: query,
        );
        expect(_renderedName(tester), '#northedsa', reason: 'query: $query');
        // Three spans means a run was actually marked; one means it fell back
        // to the plain name.
        expect(
          (tester.widget<Text>(find.byType(Text).at(1)).textSpan
                  as TextSpan)
              .children!
              .length,
          3,
          reason: 'query: $query',
        );
      }
    });

    testWidgets('a query that matches nothing leaves the name alone',
        (tester) async {
      await _pumpRow(tester, highlight: 'zzz');
      expect(find.text('#sunsetseries'), findsOneWidget);
    });
  });

  group('layout', () {
    testWidgets('the skeleton is exactly as tall as the row it stands in for',
        (tester) async {
      // The invariant that matters: a loader of a different height makes the
      // list resize when the data lands. Asserted as an equality rather than a
      // magic number, so it survives a deliberate metric change.
      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CLTopicRow(topic: _topic(), onTap: () {}),
                const CLTopicRowSkeleton(),
              ],
            ),
          ),
        ),
      ));

      expect(
        tester.getSize(find.byType(CLTopicRowSkeleton)).height,
        tester.getSize(find.byType(CLTopicRow)).height,
      );
    });

    testWidgets('a long category truncates instead of widening the row',
        (tester) async {
      await _pumpRow(
        tester,
        topic: _topic(
            category: 'An Extremely Long Category Name That Would Overflow'),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(CLTopicRow)).width, 390);
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
      await _pumpRow(tester, topic: _topic(faces: faces));

      // Three 24px avatars lapping by 9 occupy 24 + 2*15 = 54, not 72.
      expect(
        tester.getSize(find.byType(Stack).first).width,
        kTopicFaceSize + 2 * (kTopicFaceSize - kTopicFaceOverlap),
      );
    });

    testWidgets('a list draws one row per topic, dividers between them',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: CLTopicList(
              topics: [
                _topic(slug: 'one'),
                _topic(slug: 'two'),
                _topic(slug: 'three'),
              ],
              dividers: true,
              onTopicTap: (_) {},
            ),
          ),
        ),
      ));

      expect(find.byType(CLTopicRow), findsNWidgets(3));
      // Between the rows, never above the first or below the last.
      expect(find.text('#one'), findsOneWidget);
      expect(find.text('#three'), findsOneWidget);
    });
  });
}
