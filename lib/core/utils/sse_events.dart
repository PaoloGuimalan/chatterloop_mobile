import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:chatterloop_app/core/calls/call_controller.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/contacts_api.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/requests/notifications_api.dart';
import 'package:chatterloop_app/core/routes/app_router.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/models/call_models/incoming_call_alert_model.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_item_model.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_state_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';

/// One relationship change, pushed by the `profile_relationship_updated` SSE
/// event.
///
/// A CLASS, not a bare String, and deliberately without an `==` override:
/// ValueNotifier only notifies when the new value differs, so two consecutive
/// events about the SAME person - request received, then accepted - would
/// have been silently dropped with a plain String. Identity equality on a
/// fresh instance makes every event fire.
class ProfileRelationshipUpdate {
  final String entityId;
  const ProfileRelationshipUpdate(this.entityId);
}

/// Latest relationship change. A ValueNotifier rather than redux: the only
/// thing that cares is whichever profile screen happens to be mounted, and
/// putting it in the store would be a write-then-read of state nothing else
/// consumes. Listeners MUST compare entityId against the profile they are
/// showing before refetching.
final ValueNotifier<ProfileRelationshipUpdate?> profileRelationshipUpdates =
    ValueNotifier<ProfileRelationshipUpdate?>(null);

/// You have been removed from a realm - a server, a channel, a group.
///
/// A CLASS with identity equality, for the same reason as
/// [ProfileRelationshipUpdate]: being removed from the same realm twice (added
/// back in between) has to fire twice, and a plain String would coalesce them.
class RealmRemoval {
  /// The realm you are no longer a member of.
  final String realmId;

  /// Its kind, straight off the payload - "server", "group", "page", "voice".
  /// A CHANNEL arrives as "group", since that is what a channel is.
  final String type;

  const RealmRemoval(this.realmId, this.type);
}

/// The realm you were most recently removed from.
///
/// A ValueNotifier rather than redux, like profileRelationshipUpdates: the only
/// things that care are whichever screens happen to be showing that realm.
/// Listeners MUST compare realmId against what they are displaying.
final ValueNotifier<RealmRemoval?> realmRemovals =
    ValueNotifier<RealmRemoval?>(null);

/// Pulls the removal out of a `removed_user_notif` payload, or null if it is not
/// one.
///
/// The shape is the Node service's, from routes/realms/index.js:
///
///     {status, auth, onseen, message,
///      result: {realm_id, entityID, type}}
///
/// Top-level and pure so the id contract is pinned by a test rather than by
/// reading it - `realm_id`, not `id`, and the entityID on it is YOURS (the
/// event is published per removed member to `events_<entity_id>`, so it only
/// ever arrives at the person it happened to - which is why nothing downstream
/// checks whether it is about you).
RealmRemoval? realmRemovalFromSseEvent(Map<String, dynamic> parsed) {
  final result = parsed["result"];
  if (result is! Map) return null;
  final realmId = result["realm_id"]?.toString() ?? '';
  if (realmId.isEmpty) return null;
  return RealmRemoval(realmId, result["type"]?.toString() ?? '');
}

/// Refetches page 1 of notifications and puts it in the store.
///
/// Every notification event goes through this instead of reading the payload
/// it arrived with, because MOST OF THEM DON'T HAVE ONE. The Django service
/// publishes `"result": ""` on every notifications event it raises - post
/// reactions, comments, tags, mentions, follows (see user_service's
/// newsfeed/views.py and user/views.py) - and only the Node service signs a
/// real JWT into it. The old code here decoded `result` and read
/// `["notifications"]` off it, which on an empty string is null being
/// assigned to a non-nullable List: it threw, killed the handler before the
/// dispatch, and did it silently. That's the badge sitting at its old count
/// while activity piles up.
///
/// Webapp has never trusted the payload either - both its handlers call
/// NotificationOverrideRequest(1, 10) and ignore `result` entirely (the
/// dispatch of the decoded body is commented out in sse.ts). This is that,
/// with the app's own page size.
Future<void> refreshNotificationsFromSse() async {
  final response = await NotificationsApi().getNotificationsListRequest();
  if (response == null) return;
  final decoded = JwtCodec.decode(response.result);
  final raw = decoded?["notifications"];
  final list = raw is List
      ? raw.map((notif) => NotificationsItemModel.fromJson(notif)).toList()
      : <NotificationsItemModel>[];
  appStore.dispatch(DispatchModel(setNotificationsListT,
      NotificationsStateModel(list, decoded?["totalunread"] ?? 0)));
}

/// Every event on this channel is wrapped as {auth, status, ...}. Both have
/// to be true before the body means anything, and neither is guaranteed to be
/// present - an unparseable frame is a dropped event, never a thrown one.
bool _isAuthedOk(dynamic data) {
  try {
    final parsed = jsonDecode(data as String);
    return parsed is Map && parsed["auth"] == true && parsed["status"] == true;
  } catch (_) {
    return false;
  }
}

/// Bumped on every `messages_list` event - i.e. whenever a message arrives
/// anywhere, in any conversation.
///
/// A counter rather than a bool: two messages in a row must fire twice, and a
/// bool would coalesce them.
///
/// Web achieves the same thing differently: its channels view watches the redux
/// conversation list, and its SSE handler refetches that list using the TYPE
/// carried on the event (see below), so a channel message does move it. This app
/// now does that too - but the signal stays, because it is the direct statement
/// of "a message landed" and does not depend on a list refetch succeeding, or on
/// that list happening to include the conversation in question.
final ValueNotifier<int> messagesListSignals = ValueNotifier<int>(0);

class SseEvents {
  /// A new SseEvents() is constructed per event (see sse_connection.dart),
  /// so per-typer removal timers have to live at module/static scope to be
  /// findable across calls - keyed by "userID|conversationID".
  static final Map<String, Timer> _typingRemovalTimers = {};

  Future<void> listen(SSEModel event, bool mainListener) async {
    switch (event.event) {
      case "notifications":
        // Raised for anything that earns you a notification: reactions,
        // comments, comment reactions, tags, mentions, contact requests,
        // follows. The alert tone belongs here and not on the reload event -
        // this is the one that means something NEW happened.
        if (_isAuthedOk(event.data)) {
          AudioPlayer audioPlayer = AudioPlayer();
          audioPlayer.play(AssetSource('sounds/notification_alert.mp3'));
          await refreshNotificationsFromSse();
        }
        return;
      case "notifications_reload":
        // Same refetch, no tone: this one fires when an EXISTING notification
        // changed out from under you - a request you were shown got cancelled
        // or answered elsewhere - so the count has to move but nothing new
        // arrived to announce.
        if (_isAuthedOk(event.data)) {
          await refreshNotificationsFromSse();
        }
        return;
      case "istyping_broadcast":
        Map<String, dynamic> parsedresponse = jsonDecode(event.data as String);
        bool isAuth = parsedresponse["auth"] as bool;
        bool status = parsedresponse["status"] as bool;
        if (isAuth) {
          if (status) {
            Map<String, dynamic>? decodedtyper =
                JwtCodec.decode(parsedresponse["result"]);
            dynamic rawTyperData = decodedtyper?["istyping"];
            IsTypingMetaData finalTyperData =
                IsTypingMetaData.fromJson(rawTyperData);

            appStore.dispatch(DispatchModel(setIsTypingListT, finalTyperData));

            // Debounced per (userID, conversationID) - a person actively
            // typing re-broadcasts every few seconds, and each broadcast
            // used to schedule its own independent 5s removal with nothing
            // cancelling earlier ones. An earlier broadcast's timer firing
            // after a newer one arrived would clear the indicator while
            // they were still typing (then the newer broadcast's own timer
            // would fire later and no-op) - looked like the indicator
            // randomly disappearing/reappearing. Cancel any pending
            // removal for this pair before scheduling the new one, so only
            // the most recent broadcast's timer ever actually fires.
            final key =
                "${finalTyperData.userID}|${finalTyperData.conversationID}";
            _typingRemovalTimers[key]?.cancel();
            _typingRemovalTimers[key] =
                Timer(const Duration(milliseconds: 5000), () {
              _typingRemovalTimers.remove(key);
              appStore
                  .dispatch(DispatchModel(removeIsTypingListT, finalTyperData));
            });
          }
        }
        return;
      case "incomingcall":
        // JWT-wrapped like notifications/active_users - decodedResult's
        // `callmetadata` field is exactly whatever the caller's device
        // signed into its own /u/call token (server/reusables/hooks/
        // sse.js's ReachCallRecepients relays it through unchanged), so
        // IncomingCallAlert.fromJson doubles as both the outgoing request
        // shape and this incoming decode.
        Map<String, dynamic> parsedresponse = jsonDecode(event.data as String);
        bool isAuth = parsedresponse["auth"] as bool? ?? false;
        bool status = parsedresponse["status"] as bool? ?? false;
        if (isAuth && status) {
          Map<String, dynamic>? decodedResult =
              JwtCodec.decode(parsedresponse["result"]);
          final rawCallMetadata = decodedResult?["callmetadata"];
          if (rawCallMetadata is Map) {
            final alert = IncomingCallAlert.fromJson(
                Map<String, dynamic>.from(rawCallMetadata));
            // Busy-handling (auto-decline while already in a call) lives in
            // IncomingCallView's initState, not here - this just surfaces
            // the ring signal into Redux and pushes the full-screen alert.
            // appRouter (not a BuildContext) since this fires outside any
            // widget's tree.
            appStore.dispatch(DispatchModel(setPendingIncomingCallT, alert));
            appRouter.push('/call/incoming', extra: alert);
          }
        }
        return;
      case "callreject":
        // Two different decodedToken shapes arrive on this same event,
        // both wrapped as {rejectdata: decodedToken} (server/reusables/
        // hooks/sse.js's CallRejectNotif):
        //   - from /rejectcall: {conversationID, rejectedBy} - the callee
        //     (single calls only) declined our outgoing call.
        //   - from /endcall: {conversationID, endedBy} - the caller ended
        //     the call for everyone else.
        // Both mean the same thing from this device's perspective: the
        // call for that conversationID is over - dismiss any still-ringing
        // alert AND tear down an active call, whichever applies.
        Map<String, dynamic> parsedresponse = jsonDecode(event.data as String);
        bool isAuth = parsedresponse["auth"] as bool? ?? false;
        bool status = parsedresponse["status"] as bool? ?? false;
        if (isAuth && status) {
          Map<String, dynamic>? decodedResult =
              JwtCodec.decode(parsedresponse["result"]);
          final rawRejectData = decodedResult?["rejectdata"];
          if (kDebugMode) {
            print("[SSE] callreject received: rejectdata=$rawRejectData "
                "currentCall=${appStore.state.currentCall?.conversationID}");
          }
          if (rawRejectData is Map) {
            final conversationID = rawRejectData["conversationID"]?.toString();
            if (conversationID != null) {
              final pending = appStore.state.pendingIncomingCall;
              if (pending != null && pending.conversationID == conversationID) {
                appStore
                    .dispatch(DispatchModel(clearPendingIncomingCallT, null));
              }
              final current = appStore.state.currentCall;
              if (current != null && current.conversationID == conversationID) {
                await CallController.instance.leaveCall();
                appStore.dispatch(DispatchModel(clearCurrentCallT, null));
              }
            }
          }
        }
        return;
      case "contactslist":
        // Was a no-op, which is why a contact request or acceptance left both
        // the contacts list and an open profile showing stale state until
        // something else happened to refetch them.
        //
        // Two jobs, in webapp's order - the relay FIRST, so a failure in the
        // refetch can't swallow it:
        //  1. relay result.entity_id, which user/views.py builds per
        //     recipient and is therefore the OTHER party from this device's
        //     point of view. A profile screen matches it against what it's
        //     showing; an event without one names no subject and is relayed
        //     to nobody, because "reload whatever is open" is worse than a
        //     missed refresh.
        //  2. refetch the contacts list into the store.
        try {
          final parsed = jsonDecode(event.data as String);
          if (parsed is Map &&
              parsed["auth"] == true &&
              parsed["status"] == true) {
            final entityId = parsed["result"] is Map
                ? parsed["result"]["entity_id"]?.toString()
                : null;
            if (entityId != null && entityId.isNotEmpty) {
              profileRelationshipUpdates.value =
                  ProfileRelationshipUpdate(entityId);
            }
            final contacts = await ContactsApi().getContactsRequest();
            appStore
                .dispatch(DispatchModel(setContactsListT, contacts.results));
          }
        } catch (_) {
          // Malformed payload is not worth tearing the SSE loop down for.
        }
        return;
      case "profile_relationship_updated":
        // Someone answered a request we sent - contact accept/decline/remove,
        // or a follow-request approval. Carries result.entity_id: the OTHER
        // party from THIS recipient's point of view.
        //
        // Published after commit server side, so refetching on it reads
        // settled rows. An open profile screen listens on this notifier and
        // refreshes only when the id matches the profile it is showing -
        // reacting to it unconditionally would reload whatever screen happens
        // to be open.
        try {
          final parsed = jsonDecode(event.data as String);
          if (parsed is Map &&
              parsed["auth"] == true &&
              parsed["status"] == true) {
            final entityId = parsed["result"] is Map
                ? parsed["result"]["entity_id"]?.toString()
                : null;
            if (entityId != null && entityId.isNotEmpty) {
              profileRelationshipUpdates.value =
                  ProfileRelationshipUpdate(entityId);
            }
          }
        } catch (_) {
          // Malformed payload is not worth tearing the SSE loop down for.
        }
        return;
      case "messages_list":
        // This event carries no actual data - server's MessagesTrigger
        // (reusables/hooks/sse.js) always publishes result: "" and
        // message: {conversationID, entityID: sender} (an object, not the
        // plain string this used to compare against userAuth.user.entityId).
        // It's a pure "something changed, go refetch" signal - matches the
        // comment on the server's own reuse of this channel for link
        // previews: webapp's listener dispatches a "reload" CustomEvent
        // that just calls GetConversation() again, it doesn't try to
        // extract a conversation list out of the event itself. The old
        // code here tried to JwtCodec.decode an empty string and read a
        // "conversationslist" key (copied from the unrelated, dead
        // /u/initConversationList response shape) - that decode failed
        // silently every time, so this whole case threw before ever
        // reaching the dispatch, which is also why the sound alerts below
        // never played and the messages list never live-updated anywhere
        // that didn't already have its own conversation-scoped refetch
        // (e.g. the open conversation screen refetches independently of
        // this handler entirely).
        UserAuth userAuth = appStore.state.userAuth;
        Map<String, dynamic> parsedresponse = jsonDecode(event.data as String);

        if (mainListener) {
          final details = parsedresponse["message"];
          final senderEntityId =
              details is Map ? details["entityID"]?.toString() : null;
          // Non-null only for the receivers the message actually @mentioned -
          // the server evaluates that per receiver and nulls it for everyone
          // else (routes/users/index.js's sendMessage), so its presence alone
          // means "this one is about you".
          final isMentioned = details is Map && details["mentioner"] is Map;
          if (senderEntityId != null &&
              senderEntityId != userAuth.user.entityId) {
            AudioPlayer audioPlayer = AudioPlayer();
            if (parsedresponse["onseen"] == true) {
              audioPlayer.play(AssetSource('sounds/seen_alert.mp3'));
            } else if (isMentioned) {
              // The mention tone, matching both the mention PUSH (which rides
              // the Activity channel, sound notification_alert) and webapp,
              // which plays this same file for a mention rather than its
              // ordinary message tone. A push can't cover this case: pushes
              // only target sessions with status:false, and an app with a live
              // SSE connection is by definition not one of those - so without
              // this branch being mentioned while the app is OPEN is silent.
              audioPlayer.play(AssetSource('sounds/notification_alert.mp3'));
            } else {
              audioPlayer.play(AssetSource('sounds/message_alert.mp3'));
            }
          }
        }

        // The type comes from the EVENT, not a fixed "common" - web does the
        // same (InitConversationListRequest reads `value.messages.type` and
        // only falls back to "common"). Refetching the common list after a
        // channel message asks for a list that cannot contain the thing that
        // just changed, so nothing moves.
        final eventType = parsedresponse["message"] is Map
            ? parsedresponse["message"]["type"]?.toString()
            : null;
        final refreshed = await ConversationsApi().getConversationListRequest(
            type: (eventType == null || eventType.isEmpty)
                ? "common"
                : eventType);
        if (refreshed != null) {
          appStore.dispatch(DispatchModel(setMessagesListT, refreshed.items));
        }
        // Announce it regardless of whether the conversation list moved - see
        // messagesListSignals. A channel message changes nothing in that list.
        messagesListSignals.value++;
        return;
      case "removed_user_notif":
        // An admin removed you from a realm. Published only to the removed
        // member's own channel (routes/realms/index.js publishes per entity id
        // in account_ids), so its arrival IS the fact - there is nobody else's
        // removal to filter out.
        //
        // Two halves, matching webapp's sse.ts: refetch the conversation list,
        // because the thread you just lost is still in it and nothing else will
        // ever move it again (messages_list only fires on messages you no
        // longer receive), and announce it so the screens showing that realm can
        // get out of it.
        if (_isAuthedOk(event.data)) {
          final removal = realmRemovalFromSseEvent(
              jsonDecode(event.data as String) as Map<String, dynamic>);
          if (removal == null) return;
          final refreshed =
              await ConversationsApi().getConversationListRequest();
          if (refreshed != null) {
            appStore.dispatch(DispatchModel(setMessagesListT, refreshed.items));
          }
          // The channels list lives outside that list entirely (it comes from
          // initserverchannels), so it needs the generic signal to refetch -
          // this is how losing ONE channel of a server you are still in
          // disappears from the list.
          messagesListSignals.value++;
          realmRemovals.value = removal;
        }
        return;
      case "active_users":
        // server/reusables/hooks/sse.js's UpdateContactswSessionStatus -
        // fired at every contact of whoever just connected/disconnected
        // their SSE stream. JWT-wrapped as {user: {_id, sessionStatus,
        // sessiondate}}, matches the /u/activecontacts snapshot's row
        // shape (see ConversationsApi.getActiveContactsRequest) other
        // than arriving one entity at a time instead of as a full list.
        Map<String, dynamic> parsedresponse = jsonDecode(event.data as String);
        bool isAuth = parsedresponse["auth"] as bool? ?? false;
        bool status = parsedresponse["status"] as bool? ?? false;
        if (isAuth && status) {
          Map<String, dynamic>? decodedResult =
              JwtCodec.decode(parsedresponse["result"]);
          final rawUser = decodedResult?["user"];
          if (rawUser is Map) {
            final entityId = rawUser["_id"]?.toString();
            final isOnline = rawUser["sessionStatus"] == true;
            if (entityId != null && entityId.isNotEmpty) {
              final sessiondate = rawUser["sessiondate"] is Map
                  ? rawUser["sessiondate"] as Map
                  : null;
              // A disconnect event's own arrival time is a reasonable
              // "last seen" fallback on the rare chance the date string
              // doesn't parse - better than showing no time at all.
              final lastSeen = isOnline
                  ? null
                  : (parseServerTimestamp(sessiondate?["date"]?.toString()) ??
                      DateTime.now());
              appStore.dispatch(DispatchModel(updateActiveUserT,
                  ActiveUserUpdate(entityId, isOnline, lastSeen)));
            }
          }
        }
        return;
      default:
        break;
    }
  }
}
