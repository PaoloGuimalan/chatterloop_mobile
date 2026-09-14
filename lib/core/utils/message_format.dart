/// A message's text, formatted.
///
/// WHY THIS EXISTS
/// ---------------
/// Message bodies were rendered as one flat run of text - mentions and bare
/// URLs picked out, nothing else. That was fine while every message was typed
/// by a person, and stopped being fine when bots started answering in
/// conversations and channels: a bot reply is model prose, which means
/// Markdown, and `**bold**`, fenced code, tables and numbered steps all
/// arrived as literal punctuation in the middle of a wall of text.
///
/// This is the Dart counterpart of webapp's
/// `src/app/tabs/messenger/partials/MessageContent.tsx`, and it deliberately
/// supports the same syntax and nothing more. The two must agree: the same
/// message is read on both clients, and a table that renders on the web and
/// shows its pipes on the phone is worse than neither doing it.
///
/// WIDGETS, NOT A STRING
/// ---------------------
/// Blocks come back as widgets and inline runs as [InlineSpan]s, so message
/// text only ever reaches the tree as a Text child or a validated URL. There
/// is no markup path out of message content at all, which is the same property
/// the web version gets by building React elements rather than an HTML string.
///
/// EMPHASIS IS FLANKING-AWARE, BECAUSE PEOPLE TYPE HERE
/// ----------------------------------------------------
/// This renders human chat, not just model output, so a naive `\*(.+?)\*` is
/// not acceptable: "it cost 5 * 3 * 4 pesos" would come out with " 3 " in
/// italics. Every emphasis rule requires its delimiters to hug non-whitespace,
/// the way CommonMark's flanking rules do. That is the single biggest source
/// of false positives in a chat app and it is worth the extra characters.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:chatterloop_app/core/utils/chat_mentions.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';

/// Protocols we will turn into a real link.
final RegExp _safeLink = RegExp(r'^(https?://|mailto:)', caseSensitive: false);

Future<void> _openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Everything the renderer needs that is not the text itself.
///
/// [base] carries the colour the bubble is drawn in, and every tint below is
/// mixed FROM it rather than being a fixed grey. A bubble is either the theme
/// colour with white text (your own messages) or a surface with `--text`
/// (everyone else's), in either light or dark mode: a grey that reads
/// correctly on white is invisible on the theme colour, and picking per case
/// would mean four conditionals in every rule.
class MessageFormatStyle {
  final TextStyle base;
  final Color mentionColor;

  const MessageFormatStyle({required this.base, required this.mentionColor});

  Color tint(double opacity) =>
      (base.color ?? Colors.black).withValues(alpha: opacity);
}

// ----------------------------------------------------------------- inline --

/// One inline rule: a pattern, and how to turn a match into spans.
class _InlineRule {
  final RegExp pattern;
  final List<InlineSpan> Function(RegExpMatch m, _Ctx ctx) render;

  const _InlineRule(this.pattern, this.render);
}

class _Ctx {
  final MessageFormatStyle style;
  final List<UsersContactPreview> members;
  final TextStyle current;

  const _Ctx(
      {required this.style, required this.members, required this.current});

  _Ctx withStyle(TextStyle next) =>
      _Ctx(style: style, members: members, current: next);
}

/// Order matters. Inline code comes first so backticks win over the emphasis
/// characters inside them - `` `a*b*c` `` is code containing asterisks, not
/// code containing italics - and `**` before `*` so the bold rule claims its
/// own delimiters before the italic rule can eat half of one.
List<_InlineRule> _rules() => [
      _InlineRule(
        RegExp(r'`([^`\n]+)`'),
        (m, ctx) => [
          TextSpan(
            text: m.group(1),
            style: ctx.current.copyWith(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Courier New', 'monospace'],
              fontSize: (ctx.current.fontSize ?? 14) * 0.9,
              // A Paint background rather than a Container in a WidgetSpan: a
              // WidgetSpan is one unbreakable box, so a long code span would
              // refuse to wrap and push the bubble off-screen.
              background: Paint()..color = ctx.style.tint(0.12),
            ),
          )
        ],
      ),
      // `(?!\s)` opens on non-space and `[^\s*]` closes on non-space: the
      // flanking requirement described in the library comment.
      _InlineRule(
        RegExp(r'\*\*(?!\s)([^\n]*?[^\s*])\*\*'),
        (m, ctx) => _inline(m.group(1)!,
            ctx.withStyle(ctx.current.copyWith(fontWeight: FontWeight.w700))),
      ),
      _InlineRule(
        RegExp(r'__(?!\s)([^\n]*?[^\s_])__'),
        (m, ctx) => _inline(m.group(1)!,
            ctx.withStyle(ctx.current.copyWith(fontWeight: FontWeight.w700))),
      ),
      _InlineRule(
        RegExp(r'~~(?!\s)([^\n]*?[^\s~])~~'),
        (m, ctx) => _inline(
            m.group(1)!,
            ctx.withStyle(
                ctx.current.copyWith(decoration: TextDecoration.lineThrough))),
      ),
      // Single `*`. `[^*\n]*[^\s*]` cannot start or end on whitespace, which
      // is what keeps "5 * 3 * 4" out of italics.
      _InlineRule(
        RegExp(r'\*(?!\s)([^*\n]*[^\s*])\*'),
        (m, ctx) => _inline(m.group(1)!,
            ctx.withStyle(ctx.current.copyWith(fontStyle: FontStyle.italic))),
      ),
      // `_italic_` only at a non-word boundary, so snake_case_identifiers -
      // far more common here than underscore emphasis - survive intact. The
      // boundary is CAPTURED and re-emitted rather than matched with a
      // lookbehind, matching the web version character for character.
      _InlineRule(
        RegExp(r'(^|\W)_(?!\s)([^_\n]*[^\s_])_(?=\W|$)'),
        (m, ctx) => [
          TextSpan(text: m.group(1), style: ctx.current),
          ..._inline(m.group(2)!,
              ctx.withStyle(ctx.current.copyWith(fontStyle: FontStyle.italic))),
        ],
      ),
      // [text](href)
      _InlineRule(
        RegExp(r'\[([^\]\n]*)\]\(([^)\s]+)\)'),
        (m, ctx) {
          final text = m.group(1) ?? '';
          final href = m.group(2) ?? '';
          // A `javascript:` or `data:` href is an injection wearing Markdown
          // syntax. Left as the literal text the sender typed.
          if (!_safeLink.hasMatch(href)) {
            return [TextSpan(text: m.group(0), style: ctx.current)];
          }
          return [_linkSpan(text.isEmpty ? href : text, href, ctx.current)];
        },
      ),
      // Bare URLs, matching what the old linkifySpans did.
      _InlineRule(
        RegExp(r'(^|\s)(https?://[^\s<>()]+[^\s<>().,;:!?])'),
        (m, ctx) => [
          TextSpan(text: m.group(1), style: ctx.current),
          _linkSpan(m.group(2)!, m.group(2)!, ctx.current),
        ],
      ),
    ];

/// Links keep the surrounding colour and are marked by the underline alone.
///
/// Deliberately not a link colour: your own messages sit on the theme colour
/// with white text, where a blue link is unreadable.
TextSpan _linkSpan(String text, String href, TextStyle style) => TextSpan(
      text: text,
      style: style.copyWith(decoration: TextDecoration.underline),
      recognizer: TapGestureRecognizer()..onTap = () => _openUrl(href),
    );

/// Inline markup inside one run of text.
///
/// Finds whichever rule matches EARLIEST rather than applying each rule over
/// the whole string in turn. Sequential application would let a later rule
/// reach inside an earlier one's output, which is exactly how a code span
/// containing asterisks ends up italicised.
List<InlineSpan> _inline(String text, _Ctx ctx) {
  if (text.isEmpty) return const [];

  final rules = _rules();
  final out = <InlineSpan>[];
  var rest = text;

  while (rest.isNotEmpty) {
    RegExpMatch? best;
    _InlineRule? bestRule;

    for (final rule in rules) {
      final m = rule.pattern.firstMatch(rest);
      if (m == null) continue;
      if (best == null || m.start < best.start) {
        best = m;
        bestRule = rule;
      }
    }

    if (best == null || bestRule == null) {
      out.addAll(_mentions(rest, ctx));
      break;
    }

    if (best.start > 0) {
      out.addAll(_mentions(rest.substring(0, best.start), ctx));
    }
    out.addAll(bestRule.render(best, ctx));
    rest = rest.substring(best.end);
  }

  return out;
}

/// Mentions are applied to the plain runs only, AFTER the markup rules have
/// taken their pieces out. Running them first would let "@anna" inside a code
/// span light up as a mention.
List<InlineSpan> _mentions(String text, _Ctx ctx) {
  if (text.isEmpty) return const [];
  if (ctx.members.isEmpty) return [TextSpan(text: text, style: ctx.current)];

  final spans = splitMentionSpans(text, ctx.members);
  return [
    for (final span in spans)
      TextSpan(
        text: span.text,
        style: span.isMention
            ? ctx.current.copyWith(
                color: ctx.style.mentionColor, fontWeight: FontWeight.w700)
            : ctx.current,
      )
  ];
}

// ------------------------------------------------------------------ block --

final RegExp _fence = RegExp(r'^```(\w*)\s*$');
final RegExp _heading = RegExp(r'^(#{1,6})\s+(.*)$');
final RegExp _bullet = RegExp(r'^\s*[-*+]\s+(.*)$');
final RegExp _numbered = RegExp(r'^\s*(\d+)[.)]\s+(.*)$');
final RegExp _quote = RegExp(r'^>\s?(.*)$');
final RegExp _hr = RegExp(r'^\s*([-*_])(?:\s*\1){2,}\s*$');
final RegExp _tableDivider = RegExp(r'^\s*\|?[\s:|-]+\|[\s:|-]*$');

/// Relative sizes and weights for `#` through `######`, matching the web's
/// HEADING_SIZES. A message is not a document outline, so these are scaled off
/// the bubble's own size rather than being absolute heading steps - which is
/// also why they are exempt from CLType.
const List<({double scale, FontWeight weight})> _headingSteps = [
  (scale: 1.25, weight: FontWeight.w700),
  (scale: 1.15, weight: FontWeight.w700),
  (scale: 1.08, weight: FontWeight.w600),
  (scale: 1.0, weight: FontWeight.w600),
  (scale: 1.0, weight: FontWeight.w600),
  (scale: 0.95, weight: FontWeight.w600),
];

List<String> _splitRow(String line) => line
    .trim()
    .replaceFirst(RegExp(r'^\|'), '')
    .replaceFirst(RegExp(r'\|$'), '')
    .split('|')
    .map((cell) => cell.trim())
    .toList();

/// The formatted message, as a column of blocks.
///
/// Returns a plain [Text.rich] when the text has no block markup at all, which
/// is the overwhelmingly common case - a one-line chat message should not pay
/// for a Column and a list of blocks.
Widget buildFormattedMessage({
  required String source,
  required MessageFormatStyle style,
  required List<UsersContactPreview> members,
  TextAlign align = TextAlign.start,
}) {
  final ctx = _Ctx(style: style, members: members, current: style.base);
  final blocks = _blocks(source, ctx, align);

  if (blocks.length == 1) return blocks.first;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < blocks.length; i++) ...[
        if (i > 0) const SizedBox(height: 6),
        blocks[i],
      ]
    ],
  );
}

List<Widget> _blocks(String source, _Ctx ctx, TextAlign align) {
  final lines = source.replaceAll(RegExp(r'\r\n?'), '\n').split('\n');
  final blocks = <Widget>[];
  var i = 0;

  Widget richText(String text, {TextStyle? override, TextAlign? textAlign}) {
    final inner = override == null ? ctx : ctx.withStyle(override);
    return Text.rich(
      TextSpan(children: _inline(text, inner)),
      textAlign: textAlign ?? align,
    );
  }

  while (i < lines.length) {
    final line = lines[i];

    if (line.trim().isEmpty) {
      i += 1;
      continue;
    }

    // --- fenced code ------------------------------------------------------
    final fence = _fence.firstMatch(line);
    if (fence != null) {
      final body = <String>[];
      i += 1;
      while (i < lines.length && !_fence.hasMatch(lines[i])) {
        body.add(lines[i]);
        i += 1;
      }
      if (i < lines.length) i += 1; // closing fence
      blocks.add(_CodeBlock(code: body.join('\n'), style: ctx.style));
      continue;
    }

    // --- horizontal rule --------------------------------------------------
    if (_hr.hasMatch(line)) {
      blocks.add(Container(
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: 2),
          color: ctx.style.tint(0.25)));
      i += 1;
      continue;
    }

    // --- heading ----------------------------------------------------------
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      final step = _headingSteps[heading.group(1)!.length - 1];
      blocks.add(richText(
        heading.group(2)!,
        override: ctx.current.copyWith(
          fontSize: (ctx.current.fontSize ?? 14) * step.scale,
          fontWeight: step.weight,
        ),
      ));
      i += 1;
      continue;
    }

    // --- table ------------------------------------------------------------
    // Requires the divider row, so a single line that merely contains a pipe
    // is not mistaken for one.
    if (line.contains('|') &&
        i + 1 < lines.length &&
        _tableDivider.hasMatch(lines[i + 1]) &&
        lines[i + 1].contains('|')) {
      final header = _splitRow(line);
      i += 2;
      final rows = <List<String>>[];
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          lines[i].contains('|')) {
        rows.add(_splitRow(lines[i]));
        i += 1;
      }
      blocks.add(_TableBlock(
        header: header,
        rows: rows,
        ctx: ctx,
      ));
      continue;
    }

    // --- blockquote -------------------------------------------------------
    if (_quote.hasMatch(line)) {
      final body = <String>[];
      while (i < lines.length && _quote.hasMatch(lines[i])) {
        body.add(_quote.firstMatch(lines[i])!.group(1)!);
        i += 1;
      }
      blocks.add(Container(
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          border:
              Border(left: BorderSide(color: ctx.style.tint(0.35), width: 3)),
        ),
        child: Opacity(
          opacity: 0.85,
          child: richText(body.join('\n'),
              override: ctx.current.copyWith(fontStyle: FontStyle.italic)),
        ),
      ));
      continue;
    }

    // --- lists ------------------------------------------------------------
    if (_bullet.hasMatch(line) || _numbered.hasMatch(line)) {
      final ordered = !_bullet.hasMatch(line) && _numbered.hasMatch(line);
      final start = ordered
          ? int.tryParse(_numbered.firstMatch(line)!.group(1)!) ?? 1
          : 1;
      final items = <String>[];
      // A list ends at the first line that is not an item of the SAME kind, so
      // a bulleted list right after a numbered one stays two lists.
      while (i < lines.length) {
        final bullet = _bullet.firstMatch(lines[i]);
        final numbered = _numbered.firstMatch(lines[i]);
        if (!ordered && bullet != null) {
          items.add(bullet.group(1)!);
        } else if (ordered && numbered != null) {
          items.add(numbered.group(2)!);
        } else if (items.isNotEmpty &&
            lines[i].startsWith('  ') &&
            lines[i].trim().isNotEmpty) {
          // A wrapped continuation line belongs to the item above it.
          items[items.length - 1] += '\n${lines[i].trim()}';
        } else {
          break;
        }
        i += 1;
      }

      blocks.add(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < items.length; index++)
            Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // A fixed-width marker column, so wrapped lines align under
                  // the text rather than under the bullet.
                  SizedBox(
                    width: ordered ? 22 : 16,
                    child: Text(
                      ordered ? '${start + index}.' : '•',
                      style: ctx.current,
                    ),
                  ),
                  Expanded(child: richText(items[index])),
                ],
              ),
            ),
        ],
      ));
      continue;
    }

    // --- paragraph --------------------------------------------------------
    final body = <String>[];
    while (i < lines.length &&
        lines[i].trim().isNotEmpty &&
        !_fence.hasMatch(lines[i]) &&
        !_heading.hasMatch(lines[i]) &&
        !_bullet.hasMatch(lines[i]) &&
        !_numbered.hasMatch(lines[i]) &&
        !_quote.hasMatch(lines[i]) &&
        !_hr.hasMatch(lines[i])) {
      body.add(lines[i]);
      i += 1;
    }
    blocks.add(richText(body.join('\n')));
  }

  // Nothing parsed out at all - a message that is only whitespace, which the
  // blank-line skip above drops on the floor. Fall back to the raw source
  // rather than an empty bubble: it is what the sender actually sent, and an
  // empty bubble has nothing to long-press for the message menu.
  if (blocks.isEmpty) blocks.add(richText(source));
  return blocks;
}

/// A fenced code block.
///
/// Scrolls sideways rather than wrapping: a wrapped line of code is harder to
/// read than a scrolled one, and a bubble is narrow enough that almost any
/// real snippet would wrap.
class _CodeBlock extends StatelessWidget {
  final String code;
  final MessageFormatStyle style;

  const _CodeBlock({required this.code, required this.style});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: style.tint(0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            code,
            style: style.base.copyWith(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Courier New', 'monospace'],
              fontSize: (style.base.fontSize ?? 14) * 0.9,
              height: 1.4,
            ),
          ),
        ),
      );
}

class _TableBlock extends StatelessWidget {
  final List<String> header;
  final List<List<String>> rows;
  final _Ctx ctx;

  const _TableBlock(
      {required this.header, required this.rows, required this.ctx});

  @override
  Widget build(BuildContext context) {
    final border = ctx.style.tint(0.22);

    TableRow row(List<String> cells, {required bool head}) => TableRow(
          children: [
            for (var c = 0; c < header.length; c++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Text.rich(
                  TextSpan(
                    children: _inline(
                      c < cells.length ? cells[c] : '',
                      head
                          ? ctx.withStyle(
                              ctx.current.copyWith(fontWeight: FontWeight.w700))
                          : ctx,
                    ),
                  ),
                ),
              ),
          ],
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        // Sideways scroll for a wide table, but a narrow one should not be
        // squeezed into its own text width either.
        constraints: const BoxConstraints(minWidth: 180),
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: border, width: 1),
          children: [
            row(header, head: true),
            for (final r in rows) row(r, head: false),
          ],
        ),
      ),
    );
  }
}

/// A message stripped to one readable line.
///
/// For the places a message is QUOTED rather than shown - the strip above the
/// composer, the quoted bubble on a reply, the conversation list's last-message
/// line - where the box is a clipped line or two and a heading or a code fence
/// reads as debris.
///
/// Mirrors webapp's `partials/messagepreview.ts` rule for rule, so the same
/// message is summarised identically on both clients.
String messagePreviewText(String? content) {
  if (content == null || content.trim().isEmpty) return '';
  return content
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' code ')
      .replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m.group(1)!)
      .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!)
      .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'(\*\*|__|~~)'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
