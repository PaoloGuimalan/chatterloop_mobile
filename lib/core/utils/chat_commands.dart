// "/command" autocomplete in the composer.
//
// SHAPED LIKE MENTIONS, SOURCED DIFFERENTLY
// -----------------------------------------
// chat_mentions.dart filters members the client already holds. A command is a
// row the client has never seen - owned by a bot, with a description and a
// responder - so the menu is FETCHED per conversation rather than derived. The
// query/suggest/insert trio below is deliberately the same shape as mentions,
// because the composer treats them identically once the candidates exist.
//
// WHY THE SERVER SAYS WHAT TO INSERT
// ----------------------------------
// Two bots in one conversation can each own a "summarize". Inserting the bare
// "/summarize" would run BOTH, which is the exact ambiguity the ":handle"
// suffix exists to remove. The server knows every command in the room, so it
// works out per entry whether the bare or targeted form is unambiguous and
// sends it as `insert`. Nothing here second-guesses that.

/// One entry in the conversation's command menu.
class ChatCommand {
  /// The bare name, without the leading slash.
  final String name;
  final String description;

  /// Who answers: "none", "system" or "bot". Shown so somebody can tell a
  /// command that replies from one that quietly does something.
  final String responds;

  /// The owning bot's handle, and its display name for the list.
  final String bot;
  final String botName;

  /// A platform command rather than somebody's bot. The System bot is not a
  /// participant in any conversation and cannot be added to one, so its
  /// commands are offered everywhere.
  final bool isSystem;

  /// Exactly what to put in the composer, decided server-side.
  final String insert;

  const ChatCommand({
    required this.name,
    this.description = "",
    this.responds = "bot",
    this.bot = "",
    this.botName = "",
    this.isSystem = false,
    this.insert = "",
  });

  factory ChatCommand.fromJson(Map<String, dynamic> json) {
    final name = (json["name"] ?? "").toString();
    return ChatCommand(
      name: name,
      description: (json["description"] ?? "").toString(),
      responds: (json["responds"] ?? "bot").toString(),
      bot: (json["bot"] ?? "").toString(),
      botName: (json["bot_name"] ?? json["bot"] ?? "").toString(),
      isSystem: json["is_system"] == true,
      // Falls back to the bare name only if an older server omits the field,
      // so a deploy skew degrades to "might be ambiguous" rather than to an
      // empty composer insert.
      insert: (json["insert"] ?? "/$name").toString(),
    );
  }

  /// What the list shows as the owner. A system command belongs to the
  /// platform, not to a bot anybody added.
  String get ownerLabel => isSystem ? "System" : (botName.isNotEmpty ? botName : bot);
}

/// A "/query" in progress at the cursor, or null.
///
/// ANYWHERE A WORD STARTS, matching the server's parser: "@juanlazy /sum" is
/// the case people actually type, and anchoring this to the start of the
/// message left the menu closed for it. The slash must follow whitespace or
/// begin the message, which is what keeps "and/or" and "/api/v1" from opening
/// anything.
///
/// "//" is the escape hatch for writing a slash literally, and never opens the
/// menu.
///
/// [start] is the index of the slash, so insertCommand replaces from there.
({int start, String query})? activeCommandQuery(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  final before = text.substring(0, cursor);

  final match = RegExp(r"(^|\s)/([A-Za-z0-9-]*)$").firstMatch(before);
  if (match == null) return null;

  final query = match.group(2) ?? "";
  final start = before.length - query.length - 1;
  // The escape hatch: a slash immediately before this one.
  if (start > 0 && before[start - 1] == "/") return null;

  return (start: start, query: query);
}

/// Entries matching the query, capped at 6 like the mention list.
///
/// An empty query lists everything - typing "/" alone should show what is
/// available here, which is the whole point of a discoverable menu.
List<ChatCommand> commandSuggestions(
  List<ChatCommand> commands,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  final matches = commands.where((command) {
    if (normalized.isEmpty) return true;
    return command.name.toLowerCase().contains(normalized) ||
        command.description.toLowerCase().contains(normalized);
  }).toList();

  // A name match beats a description match: somebody typing "/mem" wants
  // /members, not a command that merely mentions members in its description.
  matches.sort((a, b) {
    if (normalized.isEmpty) return 0;
    final aName = a.name.toLowerCase().startsWith(normalized) ? 0 : 1;
    final bName = b.name.toLowerCase().startsWith(normalized) ? 0 : 1;
    return aName != bName ? aName - bName : a.name.compareTo(b.name);
  });

  return matches.length > 6 ? matches.sublist(0, 6) : matches;
}

/// Replace the in-progress "/query" with the picked command.
({String text, int cursor}) insertCommand(
  String text,
  int commandStart,
  int cursor,
  ChatCommand command,
) {
  // A trailing space so arguments can be typed straight away: most commands
  // take them, and the ones that do not are unharmed by it.
  final commandText = "${command.insert} ";
  final before = text.substring(0, commandStart);
  final after = text.substring(cursor.clamp(0, text.length));
  return (
    text: "$before$commandText$after",
    cursor: (before + commandText).length,
  );
}

/// One run of message text: plain, or a `/command` token.
///
/// ANYWHERE A WORD STARTS - the same reach a mention has, and the same reason:
/// people address a bot the way they address a person, so "@juanlazy
/// /summarize the thread" is one thought. `(^|\s)` is what keeps a slash
/// INSIDE a word out, so "and/or" and "/api/v1/users" are still not commands.
///
/// The lookahead is `(?=$|\s)` and deliberately NOT the mention rule's
/// punctuation set: "/summarize." is not a command server-side, so it must not
/// render as one here either.
///
/// "//" is the escape hatch and needs no special case - the second slash is
/// neither a name character nor preceded by whitespace.
final RegExp _commandToken = RegExp(
  r'(^|\s)/([A-Za-z0-9-]{1,32})(?::([A-Za-z0-9._-]{1,50}))?(?=$|\s)',
);

class CommandSpan {
  final String text;
  final bool isCommand;
  const CommandSpan(this.text, {this.isCommand = false});
}

/// Split text into plain and command spans.
///
/// [known] is the command NAMES available in this conversation. Only those are
/// highlighted: a chip on a word nothing will answer is a promise the message
/// cannot keep, and "/lunch tomorrow?" is a sentence. Matching is on the name
/// alone - the menu is already conversation-scoped, and a target only
/// disambiguates between bots that share a name.
///
/// Returns a single plain span when there is nothing to highlight, so callers
/// can render the common case without a special branch.
List<CommandSpan> splitCommandSpans(String content, Set<String> known) {
  if (content.isEmpty || known.isEmpty) return [CommandSpan(content)];

  final spans = <CommandSpan>[];
  var index = 0;

  for (final match in _commandToken.allMatches(content)) {
    final name = (match.group(2) ?? "").toLowerCase();
    if (!known.contains(name)) continue;

    // The leading whitespace the regex captured is plain text, not part of
    // the command.
    final prefix = match.group(1) ?? "";
    final tokenStart = match.start + prefix.length;

    if (tokenStart > index) {
      spans.add(CommandSpan(content.substring(index, tokenStart)));
    }
    spans.add(CommandSpan(content.substring(tokenStart, match.end),
        isCommand: true));
    index = match.end;
  }

  if (index < content.length) {
    spans.add(CommandSpan(content.substring(index)));
  }
  return spans.isEmpty ? [CommandSpan(content)] : spans;
}
