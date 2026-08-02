import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/reusables/widgets/message_content_widget.dart';
import 'package:chatterloop_app/models/messages_models/message_item_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ReactionItem r(String emoji, String entity) =>
    ReactionItem("u_$entity", "", emoji, "", false, const [], "", "", entity);

Future<void> pump(WidgetTester tester, List<ReactionItem> reactions) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildCLTheme(Brightness.light),
    home: Builder(
      builder: (context) =>
          Scaffold(body: Center(child: buildReactionPill(reactions, cl(context)))),
    ),
  ));
}

void main() {
  testWidgets('identical emoji collapse to one glyph plus a count',
      (tester) async {
    await pump(tester, [r("👍", "E1"), r("👍", "E2"), r("👍", "E3")]);
    expect(find.text("👍"), findsOneWidget);
    expect(find.text("3"), findsOneWidget);
  });

  testWidgets('a single reaction shows no count', (tester) async {
    await pump(tester, [r("👍", "E1")]);
    expect(find.text("👍"), findsOneWidget);
    expect(find.text("1"), findsNothing);
  });

  testWidgets('distinct emoji each keep their own count', (tester) async {
    await pump(tester, [r("👍", "E1"), r("👍", "E2"), r("❤️", "E3")]);
    expect(find.text("👍"), findsOneWidget);
    expect(find.text("❤️"), findsOneWidget);
    expect(find.text("2"), findsOneWidget);
  });

  testWidgets('same emoji with and without the variation selector groups',
      (tester) async {
    // Both render as a heart; only the trailing U+FE0F differs.
    await pump(tester, [r("\u2764\uFE0F", "E1"), r("\u2764", "E2")]);
    expect(find.text("2"), findsOneWidget);
  });

  testWidgets('skin-tone variants of one emoji group', (tester) async {
    await pump(
        tester, [r("\u{1F44D}\u{1F3FB}", "E1"), r("\u{1F44D}\u{1F3FF}", "E2")]);
    expect(find.text("2"), findsOneWidget);
  });

  testWidgets('past 3 distinct emoji, +N counts remaining REACTIONS',
      (tester) async {
    await pump(tester, [
      r("👍", "E1"),
      r("❤️", "E2"),
      r("😆", "E3"),
      r("😢", "E4"),
      r("😢", "E5"),
      r("😮", "E6"),
    ]);
    expect(find.text("😢"), findsNothing);
    expect(find.text("+3"), findsOneWidget);
  });
}