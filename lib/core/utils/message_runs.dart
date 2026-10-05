import 'package:chatterloop_app/models/messages_models/message_content_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';

// Message RUNS - consecutive messages from one sender, drawn as a single block
// in group-like conversations: the sender's avatar and name go on the FIRST
// message of the run, and the rest are indented to line up under it.
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
