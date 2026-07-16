import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:chatterloop_app/core/calls/call_controller.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
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

class SseEvents {
  /// A new SseEvents() is constructed per event (see sse_connection.dart),
  /// so per-typer removal timers have to live at module/static scope to be
  /// findable across calls - keyed by "userID|conversationID".
  static final Map<String, Timer> _typingRemovalTimers = {};

  Future<void> listen(SSEModel event, bool mainListener) async {
    switch (event.event) {
      case "notifications":
        Map<String, dynamic> parsedresponse = jsonDecode(event.data as String);
        bool isAuth = parsedresponse["auth"] as bool;
        bool status = parsedresponse["status"] as bool;

        if (isAuth) {
          if (status) {
            Map<String, dynamic>? decodedResult =
                JwtCodec.decode(parsedresponse["result"]);

            List<dynamic> rawNotificationsList =
                decodedResult?["notifications"];

            List<NotificationsItemModel> spreadedNotificationsList =
                rawNotificationsList
                    .map((notif) => NotificationsItemModel.fromJson(notif))
                    .toList();

            AudioPlayer audioPlayer = AudioPlayer();
            audioPlayer.play(AssetSource('sounds/notification_alert.mp3'));

            appStore.dispatch(DispatchModel(
                setNotificationsListT,
                NotificationsStateModel(
                    spreadedNotificationsList, decodedResult?["totalunread"])));
          }
        }
        return;
      case "notifications_reload":
        Map<String, dynamic> parsedresponse = jsonDecode(event.data as String);
        bool isAuth = parsedresponse["auth"] as bool;
        bool status = parsedresponse["status"] as bool;

        if (isAuth) {
          if (status) {
            Map<String, dynamic>? decodedResult =
                JwtCodec.decode(parsedresponse["result"]);

            List<dynamic> rawNotificationsList =
                decodedResult?["notifications"];

            List<NotificationsItemModel> spreadedNotificationsList =
                rawNotificationsList
                    .map((notif) => NotificationsItemModel.fromJson(notif))
                    .toList();

            appStore.dispatch(DispatchModel(
                setNotificationsListT,
                NotificationsStateModel(
                    spreadedNotificationsList, decodedResult?["totalunread"])));
          }
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
          if (senderEntityId != null &&
              senderEntityId != userAuth.user.entityId) {
            if (parsedresponse["onseen"] == true) {
              AudioPlayer audioPlayer = AudioPlayer();
              audioPlayer.play(AssetSource('sounds/seen_alert.mp3'));
            } else {
              AudioPlayer audioPlayer = AudioPlayer();
              audioPlayer.play(AssetSource('sounds/message_alert.mp3'));
            }
          }
        }

        final refreshed = await ConversationsApi().getConversationListRequest();
        if (refreshed != null) {
          appStore.dispatch(DispatchModel(setMessagesListT, refreshed.items));
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
