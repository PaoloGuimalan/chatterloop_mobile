// Lifted out of sse_events.dart unchanged.
//
// It lives here now because conversations_api.dart has to seed it (a
// conversation payload carries `voice_participants` the same way a channel
// payload does), and sse_events.dart already imports conversations_api - so
// leaving it there would have closed an import cycle. Nothing about the class
// changed in the move.

import 'package:flutter/foundation.dart';

/// Who is sitting in which voice room, right now - webapp's `previewparticipants`
/// redux slice.
///
/// Kept as clientIds per channel rather than a bare count, because that is what
/// the events actually carry: "voice-joined" adds ONE participant and
/// "update_participants" removes ONE by clientId, so a counter could not apply
/// either without double-counting a rejoin or going negative on a duplicate
/// leave.
///
/// Seeded from whatever payload carries `voice_participants` - the channels
/// list for a server channel, the conversations list for a DM or group - and
/// then kept live by the two events. Web does exactly this: Channels.tsx and
/// ConversationV2.tsx bulk-set it on fetch, sse.ts patches it in between.
class VoiceRoomPresence {
  VoiceRoomPresence._();
  static final VoiceRoomPresence instance = VoiceRoomPresence._();

  final Map<String, Set<String>> _byChannel = {};

  /// Bumped on every change - listeners rebuild off this rather than off the
  /// map, so the map can stay a plain mutable structure.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  int countFor(String channelId) => _byChannel[channelId]?.length ?? 0;

  /// Replaces one channel's occupancy from a fetched payload. Does NOT touch
  /// other channels, so a server-scoped refetch cannot wipe presence for rooms
  /// it did not include.
  void seed(String channelId, Iterable<String> clientIds) {
    final next = clientIds.where((id) => id.isNotEmpty).toSet();
    final current = _byChannel[channelId];
    // An EMPTY snapshot never wipes what the events have established.
    //
    // This is the one that made it look like nothing was live: the channels
    // list is refetched on every messages_list signal - i.e. on any message
    // anywhere - and redis fills voice_participants a moment AFTER the
    // voice-joined fan-out, so a refetch landing in that window came back with
    // an empty list and reset the room to nobody. The snapshot is a starting
    // point, not the truth; the truth is the event stream.
    if (next.isEmpty && current != null && current.isNotEmpty) return;
    if (current != null &&
        current.length == next.length &&
        current.containsAll(next)) {
      return; // no change - do not wake listeners
    }
    _byChannel[channelId] = next;
    revision.value++;
  }

  void add(String channelId, String clientId) {
    if (channelId.isEmpty || clientId.isEmpty) return;
    final set = _byChannel.putIfAbsent(channelId, () => <String>{});
    if (set.add(clientId)) revision.value++;
  }

  /// The leave event names only the clientId - not which room it was in - so
  /// this drops it from wherever it is found. Matches web's
  /// REMOVE_PREVIEW_PARTICIPANT, which filters the whole array on clientID.
  void removeClient(String clientId) {
    if (clientId.isEmpty) return;
    var changed = false;
    for (final entry in _byChannel.entries) {
      if (entry.value.remove(clientId)) changed = true;
    }
    if (changed) revision.value++;
  }
}
