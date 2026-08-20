// Lifted out of sse_events.dart unchanged.
//
// It lives here now because conversations_api.dart has to seed it (a
// conversation payload carries `voice_participants` the same way a channel
// payload does), and sse_events.dart already imports conversations_api - so
// leaving it there would have closed an import cycle. Nothing about the class
// changed in the move.

import 'package:chatterloop_app/models/call_models/voice_participant_model.dart';
import 'package:flutter/foundation.dart';

/// Who is sitting in which voice room, right now - webapp's `previewparticipants`
/// redux slice.
///
/// Keyed by clientId per channel rather than held as a bare count, because
/// that is what the events actually carry: "voice-joined" adds ONE participant
/// and "update_participants" removes ONE by clientId, so a counter could not
/// apply either without double-counting a rejoin or going negative on a
/// duplicate leave.
///
/// The VALUE is a whole [VoiceParticipant] rather than just the id it is keyed
/// by, so a surface can name who is in there ("@alice joined the call") and not
/// only how many. Every source of presence already carries the name; this used
/// to discard it on the way in.
///
/// Seeded from whatever payload carries `voice_participants` - the channels
/// list for a server channel, the conversations list for a DM or group - and
/// then kept live by the two events. Web does exactly this: Channels.tsx and
/// ConversationV2.tsx bulk-set it on fetch, sse.ts patches it in between.
class VoiceRoomPresence {
  VoiceRoomPresence._();
  static final VoiceRoomPresence instance = VoiceRoomPresence._();

  final Map<String, Map<String, VoiceParticipant>> _byChannel = {};

  /// Bumped on every change - listeners rebuild off this rather than off the
  /// map, so the map can stay a plain mutable structure.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  int countFor(String channelId) => _byChannel[channelId]?.length ?? 0;

  /// Who is in there, for a surface that wants to name them. Insertion order,
  /// which for a live room is join order.
  List<VoiceParticipant> participantsFor(String channelId) =>
      _byChannel[channelId]?.values.toList(growable: false) ?? const [];

  /// Replaces one channel's occupancy from a fetched payload. Does NOT touch
  /// other channels, so a server-scoped refetch cannot wipe presence for rooms
  /// it did not include.
  void seedParticipants(
      String channelId, Iterable<VoiceParticipant> participants) {
    final next = <String, VoiceParticipant>{};
    for (final participant in participants) {
      if (participant.clientId.isEmpty) continue;
      // Merged, not overwritten: a snapshot that knows only the clientId must
      // not blank out a username an earlier voice-joined event supplied.
      next[participant.clientId] =
          participant.mergedWith(_byChannel[channelId]?[participant.clientId]);
    }

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
    if (current != null && _sameRoster(current, next)) {
      return; // no change - do not wake listeners
    }
    _byChannel[channelId] = next;
    revision.value++;
  }

  /// Ids-only seed, for a payload parsed before names were kept (the server
  /// channels list). Equivalent to [seedParticipants] with nameless entries -
  /// and because that merges, a name already known survives this.
  void seed(String channelId, Iterable<String> clientIds) {
    seedParticipants(
      channelId,
      clientIds
          .where((id) => id.isNotEmpty)
          .map((id) => VoiceParticipant(clientId: id)),
    );
  }

  /// Compares occupancy AND the details rendered off it, so a participant
  /// whose name arrives later still wakes listeners.
  bool _sameRoster(Map<String, VoiceParticipant> a,
      Map<String, VoiceParticipant> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null) return false;
      if (other.username != entry.value.username) return false;
    }
    return true;
  }

  void add(String channelId, String clientId,
      {String? username, String? entityId, String? profile}) {
    if (channelId.isEmpty || clientId.isEmpty) return;
    final room = _byChannel.putIfAbsent(channelId, () => {});
    final incoming = VoiceParticipant(
      clientId: clientId,
      username: username,
      entityId: entityId,
      profile: profile,
    ).mergedWith(room[clientId]);

    final existing = room[clientId];
    if (existing != null && existing.username == incoming.username) return;

    room[clientId] = incoming;
    revision.value++;
  }

  /// The leave event names only the clientId - not which room it was in - so
  /// this drops it from wherever it is found. Matches web's
  /// REMOVE_PREVIEW_PARTICIPANT, which filters the whole array on clientID.
  void removeClient(String clientId) {
    if (clientId.isEmpty) return;
    var changed = false;
    for (final entry in _byChannel.entries) {
      if (entry.value.remove(clientId) != null) changed = true;
    }
    if (changed) revision.value++;
  }
}
