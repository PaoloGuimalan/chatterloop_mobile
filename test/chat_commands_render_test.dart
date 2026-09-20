import 'package:chatterloop_app/core/utils/chat_commands.dart';
import 'package:flutter_test/flutter_test.dart';

// The rendered highlight has to agree with what the SERVER parses as a
// command, or a message is highlighted as one thing and runs as another.
// The cases below mirror commandGrammar.json, which is the canonical corpus.
void main() {
  const known = {'members', 'summarize', 'help', 'docs', 'stop'};

  String? tokenIn(String text) {
    final spans = splitCommandSpans(text, known);
    for (final span in spans) {
      if (span.isCommand) return span.text;
    }
    return null;
  }

  group('splitCommandSpans — where a command may appear', () {
    test('at the start', () {
      expect(tokenIn('/members'), '/members');
    });

    test('after a mention, which is the case people type', () {
      expect(tokenIn('@juanlazy /summarize the thread'), '/summarize');
    });

    test('after any text, the same reach a mention has', () {
      expect(tokenIn('use the /summarize command'), '/summarize');
    });

    test('a target is part of the token', () {
      expect(tokenIn('hey @ana /summarize:neon now'), '/summarize:neon');
    });

    test('leading whitespace is fine', () {
      expect(tokenIn('  /help'), '/help');
    });
  });

  group('splitCommandSpans — what is not a command', () {
    test('a slash inside a word', () {
      // No whitespace before it, so "and/or" and paths are safe.
      expect(tokenIn('see and/or the docs'), isNull);
      expect(tokenIn('/api/v1/users'), isNull);
      expect(tokenIn('/2026/09/17'), isNull);
    });

    test('the doubled-slash escape hatch, anywhere', () {
      expect(tokenIn('//summarize literal'), isNull);
      expect(tokenIn('write it as //summarize'), isNull);
    });

    test('trailing punctuation is not swallowed into the name', () {
      // "/summarize." is not a command server-side, so it must not render as
      // one either.
      expect(tokenIn('/summarize.'), isNull);
      expect(tokenIn('/summarize, please'), isNull);
    });

    test('a bare or malformed slash', () {
      expect(tokenIn('/'), isNull);
      expect(tokenIn('/ summarize'), isNull);
      expect(tokenIn('ask about / please'), isNull);
    });
  });

  group('only existing commands highlight', () {
    test('a command nobody in the room answers is left alone', () {
      // "/lunch tomorrow?" is a sentence. A chip on it would promise an
      // answer that is never coming.
      expect(tokenIn('/lunch tomorrow?'), isNull);
    });

    test('an empty menu highlights nothing', () {
      expect(splitCommandSpans('/members', const {}).single.isCommand, isFalse);
    });

    test('matching ignores case', () {
      expect(tokenIn('/MEMBERS'), '/MEMBERS');
    });

    test('the surrounding text survives intact', () {
      final spans = splitCommandSpans('@ana /members please', known);
      expect(spans.map((s) => s.text).join(), '@ana /members please');
      expect(spans.where((s) => s.isCommand).length, 1);
    });
  });

  group('activeCommandQuery — when the menu opens', () {
    test('at the start, and after text or a mention', () {
      expect(activeCommandQuery('/', 1)?.start, 0);
      expect(activeCommandQuery('@juanlazy /', 11)?.start, 10);
      expect(activeCommandQuery('@juanlazy /sum', 14)?.query, 'sum');
      expect(activeCommandQuery('hey /su', 7)?.query, 'su');
    });

    test('never inside a word, or on the escape hatch', () {
      expect(activeCommandQuery('and/or', 6), isNull);
      expect(activeCommandQuery('//su', 4), isNull);
      expect(activeCommandQuery('a/b', 3), isNull);
    });

    test('closes once the command is finished', () {
      expect(activeCommandQuery('/sum x', 6), isNull);
    });
  });
}
