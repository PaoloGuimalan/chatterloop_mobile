// The markers that follow an entity's display name.
//
// Nineteen call sites draw these now, and what they must agree on is not the
// size (a picker row and a screen title legitimately differ) but the ORDER and
// the MEANING: verified first, then page, then bot - and the bot glyph is
// never the verified check, because that one means a verified human or page
// while the bot glyph says "software". Nine hand-written copies of that rule
// had already drifted into a filled flag here, no badge at all there.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  bool isVerified = false,
  bool isPage = false,
  bool isBot = false,
  double badgeSize = 14,
  double kindSize = 13,
  double gap = 4,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildCLTheme(Brightness.light),
    home: Scaffold(
      body: Builder(
        builder: (context) => Row(
          children: [
            const Flexible(child: Text('Acme')),
            ...clEntityMarkers(
              context,
              isVerified: isVerified,
              isPage: isPage,
              isBot: isBot,
              badgeSize: badgeSize,
              kindSize: kindSize,
              gap: gap,
            ),
          ],
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('nothing follows a plain person', (tester) async {
    await _pump(tester);

    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('verified, then page, then bot - in that order', (tester) async {
    await _pump(tester, isVerified: true, isPage: true, isBot: true);

    final name = tester.getTopRight(find.text('Acme')).dx;
    final verified = tester.getCenter(find.byIcon(Icons.verified)).dx;
    final page = tester.getCenter(find.byIcon(Icons.flag_outlined)).dx;
    final bot = tester.getCenter(find.byIcon(Icons.smart_toy)).dx;

    expect(verified, greaterThan(name));
    expect(page, greaterThan(verified));
    expect(bot, greaterThan(page));
  });

  testWidgets('an unverified bot wears the bot glyph and NOT the check',
      (tester) async {
    await _pump(tester, isBot: true);

    expect(find.byIcon(Icons.smart_toy), findsOneWidget);
    expect(find.byIcon(Icons.verified), findsNothing);
  });

  testWidgets('a verified bot wears both - they are not exclusive',
      (tester) async {
    await _pump(tester, isVerified: true, isBot: true);

    expect(find.byIcon(Icons.verified), findsOneWidget);
    expect(find.byIcon(Icons.smart_toy), findsOneWidget);
  });

  testWidgets('the page flag is the OUTLINED one everywhere', (tester) async {
    // entity_row.dart drew the filled Icons.flag while the other eight copies
    // drew the outlined one. One list looked different from every other list
    // showing the same page.
    await _pump(tester, isPage: true);

    expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
    expect(find.byIcon(Icons.flag), findsNothing);
  });

  testWidgets('kind glyphs say what they are on hover', (tester) async {
    await _pump(tester, isPage: true, isBot: true);

    expect(find.byTooltip('Page'), findsOneWidget);
    expect(find.byTooltip('Bot'), findsOneWidget);
  });

  testWidgets('sizes stay with the caller', (tester) async {
    // A screen title and a 30px-avatar picker row are not the same weight of
    // text - centralising the size would have made this a restyle.
    await _pump(tester,
        isVerified: true, isPage: true, badgeSize: 17, kindSize: 15, gap: 5);

    expect(tester.widget<Icon>(find.byIcon(Icons.verified)).size, 17);
    expect(tester.widget<Icon>(find.byIcon(Icons.flag_outlined)).size, 15);
    expect(tester.getSize(find.byType(SizedBox).first).width, 5);
  });
}
