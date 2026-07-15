import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/models/messages_models/messages_list_model.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_item_model.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_state_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';

class SseEvents {
  void listen(SSEModel event, bool mainListener) {
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

            Future.delayed(Duration(milliseconds: 5000), () {
              appStore
                  .dispatch(DispatchModel(removeIsTypingListT, finalTyperData));
            });
          }
        }
        return;
      case "incomingcall":
        return;
      case "callreject":
        return;
      case "contactslist":
        return;
      case "messages_list":
        UserAuth userAuth = appStore.state.userAuth;
        Map<String, dynamic> parsedresponse = jsonDecode(event.data as String);

        if (mainListener) {
          if (parsedresponse["message"] != userAuth.user.entityId) {
            // play message ringtone
            if (parsedresponse["onseen"]) {
              // play seen ringtone
              AudioPlayer audioPlayer = AudioPlayer();
              audioPlayer.play(AssetSource('sounds/seen_alert.mp3'));
            } else {
              AudioPlayer audioPlayer = AudioPlayer();
              audioPlayer.play(AssetSource('sounds/message_alert.mp3'));
            }
          }
        }

        Map<String, dynamic>? decodedmessageslist =
            JwtCodec.decode(parsedresponse["result"]);

        List<dynamic> rawConversationList =
            decodedmessageslist?["conversationslist"];

        List<MessageItem> spreadedConversationList = rawConversationList
            .map((message) => MessageItem.fromJson(message))
            .toList();

        appStore.dispatch(
            DispatchModel(setMessagesListT, spreadedConversationList));
        return;
      case "active_users":
        return;
      default:
        break;
    }
  }
}
