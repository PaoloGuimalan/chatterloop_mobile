import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/http_requests.dart';
import 'package:chatterloop_app/core/routes/app_routes.dart';
import 'package:chatterloop_app/core/utils/content_validator.dart';
import 'package:chatterloop_app/models/messages_models/messages_list_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_redux/flutter_redux.dart';

class SseEvents {
  void listen(SSEModel event, BuildContext? context, bool mainListener) {
    switch (event.event) {
      case "notificaions":
        return;
      case "notifications_reload":
        return;
      case "istyping_broadcast":
        Map<String, dynamic> parsedresponse = jsonDecode(event.data as String);
        bool isAuth = parsedresponse["auth"] as bool;
        bool status = parsedresponse["status"] as bool;
        if (isAuth) {
          if (status) {
            Map<String, dynamic>? decodedtyper =
                jwt.verifyJwt(parsedresponse["result"], secretKey);
            dynamic rawTyperData = decodedtyper?["istyping"];
            IsTypingMetaData finalTyperData =
                IsTypingMetaData.fromJson(rawTyperData);

            StoreProvider.of<AppState>(context ?? navigatorKey.currentContext!)
                .dispatch(DispatchModel(setIsTypingListT, finalTyperData));

            Future.delayed(Duration(milliseconds: 5000), () {
              StoreProvider.of<AppState>(
                      context ?? navigatorKey.currentContext!)
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
        UserAuth userAuth =
            StoreProvider.of<AppState>(context ?? navigatorKey.currentContext!)
                .state
                .userAuth;
        Map<String, dynamic> parsedresponse = jsonDecode(event.data as String);

        if (mainListener) {
          if (parsedresponse["message"] != userAuth.user.userID) {
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
            jwt.verifyJwt(parsedresponse["result"], secretKey);

        List<dynamic> rawConversationList =
            decodedmessageslist?["conversationslist"];

        List<MessageItem> spreadedConversationList = rawConversationList
            .map((message) => MessageItem.fromJson(message))
            .toList();

        ContentValidator().printer(context);

        StoreProvider.of<AppState>(context ?? navigatorKey.currentContext!)
            .dispatch(
                DispatchModel(setMessagesListT, spreadedConversationList));
        return;
      case "active_users":
        return;
      default:
        break;
    }
  }
}
