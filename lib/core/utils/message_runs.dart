import 'package:chatterloop_app/models/messages_models/message_content_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';

// Message RUNS - consecutive messages from one sender, drawn as a single block
// in group-like conversations: the sender's name goes on the FIRST message of
// the run and their avatar beside the LAST, and every message in it is
// indented to line up with the others.
//
// The webapp makes the same call (src/reusables/hooks/messageRuns.ts) and the
// two must stay in step, or the same thread groups differently on the phone
// and on the web.

/// A pause this long from the same sender starts a new run, so a message
/// picked back up after a break carries its name and avatar again instead of
/// reading as part of a conversation that ended a while ago.
const Duration runBreakGap = Duration(minutes: 10);

/// A message's timestamp, or null when it cannot be read. Messages from the
/// server carry an ISO string (which [ActionDate.fromJson] keeps in `date`
/// with an empty `time`); the older `{date, time}` shape is tried as one
/// string and simply yields null if it does not parse.
DateTime? messageTime(ActionDate date) {
  final raw = date.time.isEmpty ? date.date : '${date.date} ${date.time}';
  return DateTime.tryParse(raw.trim());
}

/// Whether [message] opens a new run, given the item drawn directly ABOVE it
/// (the next older one), or null when it is the oldest one loaded.
///
/// A run breaks when the sender changes, when a system line ("X joined") sits
/// between the two, or after a pause of [runBreakGap]. A deleted message still
/// belongs to its sender's run - it is that person's message, just gone.
/// [older] is untyped because the conversation list mixes in pending sends,
/// which never continue someone else's run.
bool startsSenderRun(MessageContent message, Object? older) {
  if (older is! MessageContent) return true;
  if (older.messageType.contains('notif')) return true;
  if (older.sender != message.sender) return true;

  final at = messageTime(message.messageDate);
  final olderAt = messageTime(older.messageDate);
  if (at != null && olderAt != null && at.difference(olderAt) > runBreakGap) {
    return true;
  }
  return false;
}

/// Whether [message] closes its run, given the item drawn directly BELOW it
/// (the next newer one), or null when it is the newest one loaded. The same
/// rule read from the other side: a run ends wherever the next one starts. A
/// pending send below is always someone new - it is yours.
bool endsSenderRun(MessageContent message, Object? newer) {
  if (newer is! MessageContent) return true;
  return startsSenderRun(newer, message);
}

/// Where each member's "seen" face sits: under the NEWEST message they have
/// seen, as messageID -> entity ids, for an OLDEST-first list.
///
/// EVERY seener gets exactly one face except the viewer - [selfIds], which
/// should hold the active entity, the personal entity and the account id,
/// since a seen is recorded against whichever was acting. That includes the
/// sender: they have seen what they wrote, and the server lists them as a
/// seener of it (counted here too, for older messages stored without that).
///
/// Walks newest to oldest and places each entity the first time it turns up,
/// so the face follows whoever has read furthest down. System lines are
/// skipped as anchors - nobody "reads" a join notice.
///
/// [canonical] maps an id to the one a person is known by. Older messages
/// recorded seeners by ACCOUNT id, and without folding those onto the entity
/// id one member would get two faces - and the viewer could appear as a
/// seener of their own thread. The webapp does the same
/// (hooks/messageRuns.ts' seenAvatarAnchors).
Map<String, List<String>> seenFaceAnchors(
    List<MessageContent> oldestFirst, Iterable<String> selfIds,
    {String Function(String id)? canonical}) {
  String key(String id) => canonical == null ? id : canonical(id);
  final anchors = <String, List<String>>{};
  final placed = {
    for (final id in selfIds)
      if (id.isNotEmpty) key(id)
  };
  for (final message in oldestFirst.reversed) {
    if (message.messageType.contains('notif') || message.messageID.isEmpty) {
      continue;
    }
    for (final raw in [...message.seeners, message.sender]) {
      if (raw.isEmpty) continue;
      final id = key(raw);
      if (!placed.add(id)) continue;
      (anchors[message.messageID] ??= []).add(id);
    }
  }
  return anchors;
}
