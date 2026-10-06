import 'package:chatterloop_app/models/messages_models/message_content_model.dart';

/// The "unread messages" divider: where reading stopped when the reader
/// opened the conversation.
///
/// Kept in step with the webapp's src/reusables/hooks/unreadDivider.ts - the
/// same rules, so a thread splits at the same message on both clients.
///
/// WHY A FIRST-SIGHT SNAPSHOT
/// --------------------------
/// Unread is not something the thread can just be asked: opening it marks
/// what scrolls into view as seen, the server confirms, the thread refetches -
/// and a divider computed from live `seeners` would vanish a second after it
/// appeared. So each message's status is recorded the FIRST time this visit
/// sees it, and never revised.
///
/// Messages that arrive while the reader is looking are not unread in any
/// sense worth a divider; they are recorded as neutral. Older pages loaded by
/// scrolling up ARE judged - they were sitting there unread all along.
enum FirstSight { unread, read, neutral }

class UnreadVisit {
  final Map<String, FirstSight> sight = {};

  /// The visit's first load has been recorded.
  bool loaded = false;
}

class UnreadDivider {
  /// The OLDEST unread message - the divider sits right above it.
  final String messageID;

  /// Unread messages below the divider.
  final int count;

  const UnreadDivider(this.messageID, this.count);

  @override
  bool operator ==(Object other) =>
      other is UnreadDivider &&
      other.messageID == messageID &&
      other.count == count;

  @override
  int get hashCode => Object.hash(messageID, count);
}

/// Read if you sent it or are among its seeners - under ANY of your ids: the
/// acting entity, your personal entity, and the account id older seeners
/// were recorded with. A system line or a deleted message is neither.
FirstSight firstSightOf(MessageContent message, Set<String> selfIds) {
  if (message.messageType.contains("notif")) return FirstSight.neutral;
  if (message.isDeleted == true) return FirstSight.neutral;
  if (selfIds.contains(message.sender)) return FirstSight.read;
  return message.seeners.any(selfIds.contains)
      ? FirstSight.read
      : FirstSight.unread;
}

/// Records every message this visit has not seen before. [newestFirst] is
/// the thread newest-first. Once the first load is in, a message newer than
/// everything already recorded arrived live - neutral; one older than what is
/// recorded came in with an older page - judged.
void recordFirstSight(Iterable<MessageContent> newestFirst, UnreadVisit visit,
    Set<String> selfIds) {
  var passedKnown = false;
  for (final message in newestFirst) {
    final id = message.messageID;
    if (id.isEmpty) continue;
    if (visit.sight.containsKey(id)) {
      passedKnown = true;
      continue;
    }
    visit.sight[id] = visit.loaded && !passedKnown
        ? FirstSight.neutral
        : firstSightOf(message, selfIds);
  }
  visit.loaded = true;
}

/// Walks back from the newest message over the unread ones until the first
/// read one: the divider goes between the two. Neutral messages are
/// transparent. Null when nothing was unread - or when the walk runs off the
/// loaded messages while older pages remain, because then the boundary is
/// further back, and it appears once that page loads rather than in the
/// wrong place now.
UnreadDivider? unreadDividerOf(Iterable<MessageContent> newestFirst,
    UnreadVisit visit, bool hasOlder) {
  var oldestUnread = "";
  var count = 0;
  for (final message in newestFirst) {
    final sight = visit.sight[message.messageID];
    if (sight == FirstSight.unread) {
      oldestUnread = message.messageID;
      count += 1;
    } else if (sight == FirstSight.read) {
      return count > 0 ? UnreadDivider(oldestUnread, count) : null;
    }
  }
  if (hasOlder || count == 0) return null;
  // The whole conversation is loaded and every message is unread.
  return UnreadDivider(oldestUnread, count);
}

String unreadDividerLabel(int count) =>
    "$count unread message${count == 1 ? "" : "s"}";
