// How a BOT renders where a person would.
//
// The moderation bot is the first non-human sender on the platform. Left to the
// old fallback it appeared as the initials "CM", which tells a reader nothing -
// and a notification saying their post was removed should visibly come from the
// platform rather than from something that looks like a person.
//
// Pinned here because it is a fallback: it only shows when there is no uploaded
// picture, so it is exactly the path that goes untested and then regresses.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  String? kind,
  String? src,
  String name = 'Chatterloop Moderation',
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildCLTheme(Brightness.light),
    home: Scaffold(
      body: CLAvatar(id: 'e1', name: name, src: src, kind: kind, size: 38),
    ),
  ));
}

void main() {
  testWidgets('a bot with no picture shows the bot glyph, not initials',
      (tester) async {
    await _pump(tester, kind: 'bot');

    expect(find.byIcon(Icons.smart_toy), findsOneWidget);
    expect(find.text('CM'), findsNothing);
  });

  testWidgets('a person with no picture still shows initials', (tester) async {
    await _pump(tester, kind: 'user', name: 'Juan Lazy');

    expect(find.text('JL'), findsOneWidget);
    expect(find.byIcon(Icons.smart_toy), findsNothing);
  });

  testWidgets('an unknown kind falls back to initials', (tester) async {
    // kind is optional - every existing caller omits it, and those must not
    // change behaviour.
    await _pump(tester, kind: null, name: 'Juan Lazy');

    expect(find.text('JL'), findsOneWidget);
    expect(find.byIcon(Icons.smart_toy), findsNothing);
  });

  testWidgets('an uploaded picture wins over the glyph', (tester) async {
    // kind is the FALLBACK, not an override: give the bot a real avatar and
    // that is what should render.
    await _pump(
      tester,
      kind: 'bot',
      src: 'https://example.invalid/moderator.png',
    );

    // No glyph and no initials - the image path took over. (The network image
    // itself cannot load in a test, which is fine; what matters is that the
    // fallback branch was not taken.)
    expect(find.byIcon(Icons.smart_toy), findsNothing);
    expect(find.text('CM'), findsNothing);
  });
}
