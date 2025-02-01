// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/http_requests.dart';
import 'package:chatterloop_app/core/requests/sse_connection.dart';
import 'package:chatterloop_app/core/routes/app_routes.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_item_model.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_state_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:flutter/foundation.dart';
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
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _eventBusSubscription?.cancel();
    super.dispose();
  }

  Future<void> getNotificationsListProcess(BuildContext context) async {
    EncodedResponse? getNotificationsListResponse =
        await APIRequests().getNotificationsListRequest();

    if (getNotificationsListResponse != null) {
      Map<String, dynamic>? decodedNotificationsList =
          jwt.verifyJwt(getNotificationsListResponse.result, secretKey);

      List<dynamic> rawNotificationsList =
          decodedNotificationsList?["notifications"];

      List<NotificationsItemModel> spreadedNotificationsList =
          rawNotificationsList
              .map((notif) => NotificationsItemModel.fromJson(notif))
              .toList();

      setState(() {
        // messagesList = spreadedNotificationsList;
        isNotificationsInitialized = true;
      });

      StoreProvider.of<AppState>(context).dispatch(DispatchModel(
          setNotificationsListT,
          NotificationsStateModel(spreadedNotificationsList,
              decodedNotificationsList?["totalunread"])));

      if (kDebugMode) {
        print(rawNotificationsList);
      }
    }
  }

  Future<void> readNotificationsProcess() async {
    if (mounted) {
      setState(() {
        isReadNotificationsInitialized = true;
      });
    }

    EncodedResponse? readNotificationsResponse =
        await APIRequests().readNotificationsRequest();

    if (readNotificationsResponse != null) {
      if (kDebugMode) {
        // print(rawContactsList);
        print(readNotificationsResponse);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
      return MaterialApp(
        home: Scaffold(
          body: Center(
              child: Container(
            color: Color(0xfff0f2f5),
            width: MediaQuery.of(context).size.width,
            child: Padding(
              padding: EdgeInsets.only(top: 0, left: 0, right: 0),
              child: Column(
                children: [
                  Container(
                    height: 90,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                            bottom: BorderSide(
                                width: 0.5, color: Color(0xffd2d2d2)))),
                    child: Padding(
                      padding: EdgeInsets.only(
                          top: 30, bottom: 0, left: 5, right: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: 40, maxHeight: 40),
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        elevation: 0,
                                        padding: EdgeInsets.only(
                                            top: 0,
                                            bottom: 0,
                                            left: 0,
                                            right: 0)),
                                    onPressed: () {
                                      AppRoutes.privateNavigatorKey.currentState
                                          ?.pushNamed("/main");
                                    },
                                    child: Center(
                                      child: Icon(
                                        Icons.arrow_back_ios_new_rounded,
                                        color: Color(0xff555555),
                                        size: 20,
                                      ),
                                    )),
                              ),
                              SizedBox(
                                width: 2,
                              ),
                              Icon(
                                Icons.notifications_sharp,
                                size: 30,
                                color: Color(0xfff2a43a),
                              ),
                              SizedBox(
                                width: 5,
                              ),
                              Text("Notifications",
                                  style: TextStyle(
                                      fontSize: 17,
                                      color: Color(0xFF565656),
                                      fontWeight: FontWeight.bold)),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                        padding: EdgeInsets.only(
                            top: 10, bottom: 10, left: 10, right: 10),
                        shrinkWrap: true,
                        // controller: _scrollController,
                        itemCount: notificationslist.length,
                        itemBuilder: (context, index) {
                          NotificationsItemModel notificationItem =
                              notificationslist[index];

                          return Padding(
                            padding: EdgeInsets.only(top: 10, bottom: 10),
                            child: SizedBox(
                              width: MediaQuery.of(context).size.width,
                              child: Column(
                                children: [
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                        maxWidth: 400, minHeight: 60),
                                    child: Center(
                                      child: Row(
                                        children: [
                                          Padding(
                                            padding: EdgeInsets.only(
                                                left: 15, right: 15),
                                            child: Center(
                                              child: ConstrainedBox(
                                                  constraints: BoxConstraints(
                                                      maxHeight: 50,
                                                      maxWidth: 50),
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                        color:
                                                            Color(0xffd2d2d2),
                                                        border: Border.all(
                                                            color: Color(
                                                                0xffd2d2d2),
                                                            width: 1),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(50)),
                                                    child: Padding(
                                                      padding:
                                                          EdgeInsets.all(10),
                                                      child: Image.network(
                                                        notificationItem.fromUser
                                                                        .profile !=
                                                                    "" &&
                                                                notificationItem
                                                                        .fromUser
                                                                        .profile !=
                                                                    "none"
                                                            ? notificationItem
                                                                .fromUser
                                                                .profile
                                                            : 'https://chatterloop.netlify.app/assets/default-e4788211.png',
                                                        fit: BoxFit.cover,
                                                      ),
                                                    ),
                                                  )),
                                            ),
                                          ),
                                          Expanded(
                                              child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                  notificationItem
                                                      .content.headline,
                                                  style: TextStyle(
                                                      fontSize: 14,
                                                      color: Color(0xFF565656),
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              SizedBox(
                                                height: 4,
                                              ),
                                              Text(
                                                  notificationItem
                                                      .content.details,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Color(0xFF565656),
                                                  )),
                                              SizedBox(
                                                height: 2,
                                              ),
                                              Text(
                                                "${notificationItem.date.date} . ${notificationItem.date.time}",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF565656),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              )
                                            ],
                                          ))
                                        ],
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    height: 2,
                                  )
                                ],
                              ),
                            ),
                          );
                        }),
                  )
                ],
              ),
            ),
          )),
        ),
      );
    }, converter: (store) {
      return store.state;
    });
  }
}
