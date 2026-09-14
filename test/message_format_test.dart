import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatterloop_app/core/utils/message_format.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';

const _style = MessageFormatStyle(
  base: TextStyle(fontSize: 14, color: Color(0xFF14161A)),
  mentionColor: Color(0xFF1C7DEF),
);

/// Pumps a formatted message and returns every rendered Text/Text.rich.
Future<List<InlineSpan>> _spans(
  WidgetTester tester,
  String source, {
  List<UsersContactPreview> members = const [],
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 300,
        child: buildFormattedMessage(
            source: source, style: _style, members: members),
      ),
    ),
  ));
  final out = <InlineSpan>[];
  for (final t in tester.widgetList<Text>(find.byType(Text))) {
    if (t.textSpan != null) out.add(t.textSpan!);
    // A plain Text (the code block, a list marker) carries its style on the
    // widget rather than in a span, so re-wrap it to keep one shape here.
    if (t.data != null) out.add(TextSpan(text: t.data, style: t.style));
  }
  return out;
}

/// Flattens to (text, style) pairs so a test can assert on what a run looks
/// like without caring how the spans were nested.
List<({String text, TextStyle? style})> _runs(List<InlineSpan> spans) {
  final out = <({String text, TextStyle? style})>[];
  void walk(InlineSpan s) {
    if (s is TextSpan) {
      if (s.text != null && s.text!.isNotEmpty) {
        out.add((text: s.text!, style: s.style));
      }
      for (final c in s.children ?? const <InlineSpan>[]) {
        walk(c);
      }
    }
  }

  for (final s in spans) {
    walk(s);
  }
  return out;
}

({String text, TextStyle? style})? _run(
        List<({String text, TextStyle? style})> runs, String text) =>
    runs.where((r) => r.text == text).firstOrNull;

void main() {
  group('inline emphasis', () {
    testWidgets('bold, italic and strikethrough render as styles',
        (tester) async {
      final runs = _runs(await _spans(tester, 'a **b** c *d* e ~~f~~'));
      expect(_run(runs, 'b')?.style?.fontWeight, FontWeight.w700);
      expect(_run(runs, 'd')?.style?.fontStyle, FontStyle.italic);
      expect(_run(runs, 'f')?.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('arithmetic is not italics', (tester) async {
      // The single biggest false positive in a chat app: a naive \*(.+?)\*
      // would put " 3 " in italics here.
      final runs = _runs(await _spans(tester, 'it cost 5 * 3 * 4 pesos'));
      expect(runs.length, 1);
      expect(runs.single.text, 'it cost 5 * 3 * 4 pesos');
      expect(runs.single.style?.fontStyle, isNot(FontStyle.italic));
    });

    testWidgets('snake_case survives underscore emphasis', (tester) async {
      final runs = _runs(await _spans(tester, 'call some_long_name here'));
      expect(runs.map((r) => r.text).join(), 'call some_long_name here');
      expect(runs.every((r) => r.style?.fontStyle != FontStyle.italic), isTrue);
    });

    testWidgets('a code span keeps its asterisks literal', (tester) async {
      final runs = _runs(await _spans(tester, 'use `a*b*c` please'));
      final code = _run(runs, 'a*b*c');
      expect(code, isNotNull, reason: 'code span should survive whole');
      expect(code!.style?.fontFamily, 'monospace');
      expect(code.style?.fontStyle, isNot(FontStyle.italic));
    });
  });

  group('links', () {
    testWidgets('a bare URL is underlined and keeps the text colour',
        (tester) async {
      final runs = _runs(await _spans(tester, 'see https://example.com ok'));
      final link = _run(runs, 'https://example.com');
      expect(link?.style?.decoration, TextDecoration.underline);
      expect(link?.style?.color, _style.base.color);
    });

    testWidgets('a javascript: markdown link stays literal text',
        (tester) async {
      const evil = '[tap](javascript:alert(1))';
      final runs = _runs(await _spans(tester, evil));
      // Rendered as the characters the sender typed, with no recognizer.
      expect(runs.map((r) => r.text).join(), contains('[tap](javascript:'));
      expect(
        runs.every((r) => r.style?.decoration != TextDecoration.underline),
        isTrue,
        reason: 'an unsafe scheme must not become a link',
      );
    });
  });

  group('blocks', () {
    testWidgets('a fenced block renders its body verbatim', (tester) async {
      final runs = _runs(
          await _spans(tester, 'before\n```dart\nvar a = 1;\n```\nafter'));
      expect(_run(runs, 'var a = 1;'), isNotNull);
      expect(_run(runs, 'var a = 1;')?.style?.fontFamily, 'monospace');
    });

    testWidgets('a numbered list starts where the sender started it',
        (tester) async {
      await _spans(tester, '3. three\n4. four');
      expect(find.text('3.'), findsOneWidget);
      expect(find.text('4.'), findsOneWidget);
    });

    testWidgets('a bulleted list draws bullets, not dashes', (tester) async {
      await _spans(tester, '- one\n- two');
      expect(find.text('•'), findsNWidgets(2));
    });

    testWidgets('a table needs its divider row', (tester) async {
      // Without the divider this is just a line containing pipes.
      await _spans(tester, 'a | b');
      expect(find.byType(Table), findsNothing);

      await _spans(tester, 'h1 | h2\n--- | ---\nc1 | c2');
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('c1'), findsOneWidget);
    });

    testWidgets('headings scale off the bubble size', (tester) async {
      final runs = _runs(await _spans(tester, '# Big'));
      expect(_run(runs, 'Big')?.style?.fontSize, 14 * 1.25);
      expect(_run(runs, 'Big')?.style?.fontWeight, FontWeight.w700);
    });
  });

  group('messagePreviewText', () {
    test('strips block markup down to one line', () {
      expect(messagePreviewText('# Title\n\n- one\n- two'), 'Title one two');
      expect(messagePreviewText('**ship** it'), 'ship it');
      expect(messagePreviewText('```\nvar a = 1;\n```'), 'code');
      expect(messagePreviewText('> quoted'), 'quoted');
      expect(messagePreviewText('[label](https://x.test)'), 'label');
      expect(messagePreviewText('`code` span'), 'code span');
    });

    test('empty and whitespace-only content collapse to empty', () {
      expect(messagePreviewText(null), '');
      expect(messagePreviewText('   \n  '), '');
    });
  });
}
