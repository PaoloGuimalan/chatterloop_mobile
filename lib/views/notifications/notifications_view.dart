// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/requests/notifications_api.dart';
import 'package:chatterloop_app/core/requests/sse_connection.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_item_model.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_state_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_redux/flutter_redux.dart';

class NotificationsView extends StatefulWidget {
  const NotificationsView({super.key});

  @override
  NotificationsStateView createState() => NotificationsStateView();
}

class NotificationsStateView extends State<NotificationsView> {
  StreamSubscription<SSEModel>? _eventBusSubscription;
  bool isNotificationsInitialized = false;
  bool isReadNotificationsInitialized = false;

  @override
  void dispose() {
    _eventBusSubscription?.cancel();
    super.dispose();
  }

  Future<void> getNotificationsListProcess(BuildContext context) async {
    EncodedResponse? getNotificationsListResponse =
        await NotificationsApi().getNotificationsListRequest();

    if (getNotificationsListResponse != null) {
      Map<String, dynamic>? decodedNotificationsList =
          JwtCodec.decode(getNotificationsListResponse.result);

      List<dynamic> rawNotificationsList =
          decodedNotificationsList?["notifications"];

      List<NotificationsItemModel> spreadedNotificationsList =
          rawNotificationsList
              .map((notif) => NotificationsItemModel.fromJson(notif))
              .toList();

      if (!mounted) return;
      setState(() => isNotificationsInitialized = true);

      StoreProvider.of<AppState>(context).dispatch(DispatchModel(
          setNotificationsListT,
          NotificationsStateModel(spreadedNotificationsList,
              decodedNotificationsList?["totalunread"])));
    }
  }

  Future<void> readNotificationsProcess() async {
    if (mounted) {
      setState(() => isReadNotificationsInitialized = true);
    }
    await NotificationsApi().readNotificationsRequest();
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return StoreConnector<AppState, AppState>(builder: (context, state) {
      List<NotificationsItemModel> notificationslist =
          state.notificationsstate.notificationsList;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isNotificationsInitialized) {
          getNotificationsListProcess(context);
          _eventBusSubscription =
              eventBus.on<SSEModel>().listen((SSEModel event) {
            if (event.event == "notifications") {
              readNotificationsProcess();
            }
          });
        }
        if (!isReadNotificationsInitialized) {
          if (state.notificationsstate.totalunread > 0) {
            readNotificationsProcess();
          }
        }
      });

      return Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(title: const Text("Notifications")),
        body: notificationslist.isEmpty
            ? Center(
                child: Text("No notifications yet",
                    style: TextStyle(color: p.text2)))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: notificationslist.length,
                itemBuilder: (context, index) {
                  final notif = notificationslist[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: CLCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CLAvatar(
                            id: notif.fromUserID,
                            name: notif.content.headline,
                            src: notif.fromUser.profile != "none"
                                ? notif.fromUser.profile
                                : null,
                            size: 46,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(notif.content.headline,
                                    style: TextStyle(
                                        color: p.text,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14)),
                                const SizedBox(height: 3),
                                Text(notif.content.details,
                                    style: TextStyle(
                                        color: p.text2, fontSize: 13)),
                                const SizedBox(height: 4),
                                Text("${notif.date.date} · ${notif.date.time}",
                                    style: TextStyle(
                                        color: p.text3, fontSize: 11)),
                              ],
                            ),
                          ),
                          if (!notif.isRead)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(top: 4),
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle, color: p.brand),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      );
    }, converter: (store) {
      return store.state;
    });
  }
}
