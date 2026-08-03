// Chat mentions - Flutter counterpart of the webapp's ConversationV2 composer
// + partials/ContentHandler.tsx rendering.
//
// Mentions in chat are PURELY TEXTUAL. Nothing is sent alongside the message:
// picking a suggestion just inserts "@label " into the text, and rendering
// re-detects them by matching against the conversation's own members. That is
// exactly what the webapp does - there is no mention payload on the chat send
// path (unlike newsfeed comments, which do resolve entities server side).
//
// Both halves live here so the label used when INSERTING and the label matched
// when RENDERING can never disagree - a mismatch would insert a mention that
// then failed to highlight.

import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';

/// The handle a mention is written with.
///
/// Falls back through userID -> first name -> "someone", matching the
/// webapp's getMemberMentionLabel.
String mentionLabelFor(UsersContactPreview member) {
  if (member.userID.isNotEmpty) return member.userID;
  final first = member.fullname.firstName.trim();
  return first.isNotEmpty ? first : "someone";
}

/// Full name used only for SEARCHING the suggestion list - you can type part
/// of someone's real name to find their handle.
String mentionFullNameFor(UsersContactPreview member) {
  final full = [
    member.fullname.firstName.trim(),
    member.fullname.lastName.trim(),
  ].where((part) => part.isNotEmpty).join(" ").trim();
  return full.isNotEmpty ? full : "Someone";
}

/// Members that can be mentioned: everyone in the conversation except
/// yourself, de-duplicated.
///
/// A "single" conversation is capped at one, matching the webapp - there is
/// only ever one other participant, and duplicates in the payload would
/// otherwise show them twice.
/// Everyone whose @handle should HIGHLIGHT when it appears in a message -
/// which is every participant, including yourself.
///
/// Deliberately not [mentionableMembers]. That one answers "who can I mention",
/// so it drops you (you don't @ yourself) and caps a DM at the other person.
/// Rendering asks a different question, and using the suggestion list for it
/// meant the one mention that matters most - your own name - was the only one
/// that never lit up.
List<UsersContactPreview> mentionHighlightMembers(
  List<UsersContactPreview> members,
) {
  final seen = <String>{};
  final result = <UsersContactPreview>[];
  for (final member in members) {
    if (!seen.add(member.entityID)) continue;
    result.add(member);
  }
  return result;
}

/// Who the composer offers when you type "@" - everyone BUT you, deduped, and
/// capped at one for a DM.
List<UsersContactPreview> mentionableMembers(
  List<UsersContactPreview> members, {
  required String currentEntityId,
  required String conversationType,
}) {
  final seen = <String>{};
  final result = <UsersContactPreview>[];

  for (final member in members) {
    if (member.entityID == currentEntityId) continue;
    if (!seen.add(member.entityID)) continue;
    result.add(member);
  }

  if (conversationType == "single" && result.length > 1) {
    return result.sublist(0, 1);
  }
  return result;
}

/// The active "@..." query immediately before the cursor, or null when the
/// cursor is not in one.
///
/// Mirrors the webapp's /(^|\s)@([^\s@]*)$/ - a mention starts at the very
/// beginning or after whitespace, so an email address does not open the
/// suggestion list.
({int start, String query})? activeMentionQuery(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  final beforeCursor = text.substring(0, cursor);
  final match = RegExp(r'(^|\s)@([^\s@]*)$').firstMatch(beforeCursor);
  if (match == null) return null;

  // start = the '@' itself, not the whitespace the regex also captured.
  final start = match.start + (match.group(1)?.length ?? 0);
  return (start: start, query: match.group(2) ?? "");
}

/// Suggestions for the current query, capped at 6 like the webapp. An empty
/// query lists everyone - typing "@" alone should show who is available.
List<UsersContactPreview> mentionSuggestions(
  List<UsersContactPreview> members,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  final matches = members.where((member) {
    if (normalized.isEmpty) return true;
    return mentionLabelFor(member).toLowerCase().contains(normalized) ||
        mentionFullNameFor(member).toLowerCase().contains(normalized);
  }).toList();

  return matches.length > 6 ? matches.sublist(0, 6) : matches;
}

/// Replace the in-progress "@query" with a complete mention, returning the new
/// text and where the cursor should land.
({String text, int cursor}) insertMention(
  String text,
  int mentionStart,
  int cursor,
  UsersContactPreview member,
) {
  final mentionText = "@${mentionLabelFor(member)} ";
  final before = text.substring(0, mentionStart);
  final after = text.substring(cursor);
  return (
    text: "$before$mentionText$after",
    cursor: (before + mentionText).length,
  );
}

/// A span of message text, flagged when it is a mention so the renderer can
/// style it.
class MentionSpan {
  final String text;
  final bool isMention;
  const MentionSpan(this.text, {this.isMention = false});
}

/// Split message text into plain and mention spans.
///
/// Labels are matched LONGEST FIRST so "@annabelle" is not clipped to "@anna"
/// when both are in the conversation. A mention must be followed by
/// whitespace, punctuation or end-of-string, which stops "@ann" matching
/// inside "@annabelle" - same rule as the webapp's buildMentionRegex.
///
/// Returns a single plain span when there is nothing to highlight, so callers
/// can render the common case without a special branch.
List<MentionSpan> splitMentionSpans(
  String content,
  List<UsersContactPreview> members,
) {
  if (content.isEmpty || members.isEmpty) {
    return [MentionSpan(content)];
  }

  final labels = members
      .map(mentionLabelFor)
      .where((label) => label.isNotEmpty)
      .toSet()
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));

  if (labels.isEmpty) return [MentionSpan(content)];

  final alternation = labels.map(RegExp.escape).join("|");
  final pattern = RegExp('(^|\\s)@($alternation)(?=\\s|[.,!?;:]|\$)');

  final spans = <MentionSpan>[];
  var index = 0;

  for (final match in pattern.allMatches(content)) {
    // The leading whitespace the regex captured is plain text, not part of
    // the mention.
    final prefix = match.group(1) ?? "";
    final mentionStart = match.start + prefix.length;

    if (mentionStart > index) {
      spans.add(MentionSpan(content.substring(index, mentionStart)));
    }
    spans.add(MentionSpan(content.substring(mentionStart, match.end),
        isMention: true));
    index = match.end;
  }

  if (index < content.length) {
    spans.add(MentionSpan(content.substring(index)));
  }

  return spans.isEmpty ? [MentionSpan(content)] : spans;
}
