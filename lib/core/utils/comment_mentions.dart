// @mentions inside COMMENTS - the composer half and the rendering half.
//
// Same model as mentions in messages: the mention IS the text. "@ana" sits in
// the comment's text like any other characters, nothing travels alongside it,
// and it's re-detected at render time. What the SERVER adds for comments (and
// not for chat) is the notification: newsfeed/services/comment_mentions.py
// parses handles out on write purely to notify them, and persists nothing.
//
// Which is why the pattern below has to stay character-for-character identical
// to the other three implementations - a token this file highlights but the
// server doesn't parse is a mention that visibly did nothing:
//
//   server/reusables/hooks/transformers.js          extractMentionUsernames()
//   user_service/newsfeed/services/comment_mentions.py  MENTION_PATTERN
//   webapp/src/reusables/hooks/mentions.ts          MENTION_SOURCE
//
// The one real difference from chat: chat checks a handle against the
// conversation's members before highlighting it, because a conversation HAS a
// member list. A comment can mention anyone, so every well-formed token is
// highlighted. A handle matching nobody is styled but inert - the same deal
// the server gives it.

import 'package:chatterloop_app/core/utils/chat_mentions.dart';
import 'package:chatterloop_app/core/utils/linkify_text.dart';
import 'package:flutter/material.dart';

/// The leading (^|\s) is what stops "you@example.com" mentioning @example.
///
/// Note the class includes "." and is greedy, so "thanks @ana." captures
/// "ana." - the lookahead is already satisfied by end-of-string with the dot
/// consumed. The server compensates when resolving who to notify by also
/// trying the dot-stripped handle; here it only means the highlight swallows
/// the full stop, which is cosmetic. Left as-is so the parses stay identical.
final RegExp commentMentionPattern =
    RegExp(r'(^|\s)@([A-Za-z0-9._-]{1,30})(?=$|\s|[.,!?;:])');

/// Handles written as "@handle", deduplicated and lowercased - the same set
/// the server will notify. Not sent anywhere; useful for not offering to
/// insert a handle the text already has.
List<String> extractMentionHandles(String text) {
  if (text.isEmpty) return const [];
  final seen = <String>{};
  for (final match in commentMentionPattern.allMatches(text)) {
    final handle = match.group(2);
    if (handle != null && handle.isNotEmpty) seen.add(handle.toLowerCase());
  }
  return seen.toList();
}

/// Split comment text into plain and mention spans, for rendering.
///
/// Reuses [MentionSpan] so a comment and a message can be painted by the same
/// code path - only the rule for what COUNTS as a mention differs.
List<MentionSpan> splitCommentMentionSpans(String text) {
  if (text.isEmpty) return [MentionSpan(text)];

  final spans = <MentionSpan>[];
  var index = 0;

  for (final match in commentMentionPattern.allMatches(text)) {
    // The whitespace the pattern also captured is plain text, not part of the
    // mention.
    final prefix = match.group(1) ?? "";
    final start = match.start + prefix.length;

    if (start > index) spans.add(MentionSpan(text.substring(index, start)));
    spans.add(MentionSpan(text.substring(start, match.end), isMention: true));
    index = match.end;
  }

  if (index < text.length) spans.add(MentionSpan(text.substring(index)));
  return spans.isEmpty ? [MentionSpan(text)] : spans;
}

/// Comment text as spans: mentions highlighted, everything else linkified.
///
/// One helper because the two passes have to run in this order - linkifying
/// first would leave a mention inside a matched URL, and the message renderer
/// splits mentions first for the same reason.
List<InlineSpan> commentTextSpans(
  String text,
  TextStyle baseStyle, {
  required Color mentionColor,
}) {
  final out = <InlineSpan>[];
  for (final span in splitCommentMentionSpans(text)) {
    if (span.isMention) {
      out.add(TextSpan(
        text: span.text,
        style:
            baseStyle.copyWith(color: mentionColor, fontWeight: FontWeight.w700),
      ));
    } else {
      out.addAll(linkifySpans(span.text, baseStyle));
    }
  }
  return out;
}

/// Replace the in-progress "@query" with a finished mention.
///
/// [handle] is the entity's handle - a username for a person, a slug for a
/// page. The backend resolves both namespaces, which is what makes a page
/// mentionable on exactly the same syntax as a person.
({String text, int cursor}) insertCommentMention(
  String text,
  int mentionStart,
  int cursor,
  String handle,
) {
  final mention = "@$handle ";
  final before = text.substring(0, mentionStart);
  final after = text.substring(cursor);
  return (text: "$before$mention$after", cursor: (before + mention).length);
}
