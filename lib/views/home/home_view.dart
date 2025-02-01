// ignore_for_file: use_build_context_synchronously, depend_on_referenced_packages

import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/http_requests.dart';
import 'package:chatterloop_app/core/requests/sse_connection.dart';
import 'package:chatterloop_app/core/routes/app_routes.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/messages_models/messages_list_model.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_item_model.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_state_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:restart/restart.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  HomeViewState createState() => HomeViewState();
}

class HomeViewState extends State<HomeView> {
  bool isMessagesInitialized = false;
  bool isContactsInitialized = false;
  bool isNotificationsInitialized = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  final storage = FlutterSecureStorage();

  ButtonStyle _buttonStyle(bool fromHeader) {
    return ElevatedButton.styleFrom(
        backgroundColor: fromHeader ? Colors.white : Colors.white,
        fixedSize: fromHeader ? Size(30, 30) : Size(50, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(60), // Rounded corners if needed
        ),
        elevation: 0,
        padding: EdgeInsets.zero,
        iconColor: Color(0xFF565656),
        overlayColor: Color(0xFF565656));
  }

  Future<void> getConversationListProcess(BuildContext context) async {
    EncodedResponse? getConversationListResponse =
        await APIRequests().getConversationListRequest();

    if (getConversationListResponse != null) {
      Map<String, dynamic>? decodedConversationList =
          jwt.verifyJwt(getConversationListResponse.result, secretKey);

      List<dynamic> rawConversationList =
          decodedConversationList?["conversationslist"];

      List<MessageItem> spreadedConversationList = rawConversationList
          .map((message) => MessageItem.fromJson(message))
          .toList();

      setState(() {
        // messagesList = spreadedConversationList;
        isMessagesInitialized = true;
      });

      StoreProvider.of<AppState>(context)
          .dispatch(DispatchModel(setMessagesListT, spreadedConversationList));

      // if (kDebugMode) {
      //   print(rawConversationList);
      // }
    }
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

  Future<void> getContactsProcess(BuildContext context) async {
    EncodedResponse? getContactsResponse =
        await APIRequests().getContactsRequest();

    if (getContactsResponse != null) {
      Map<String, dynamic>? decodedContactsList =
          jwt.verifyJwt(getContactsResponse.result, secretKey);

      List<dynamic> rawContactsList = decodedContactsList?["contacts"];

      List<UserContacts> spreadedContactsList = rawContactsList
          .map((contact) => UserContacts.fromJson(contact))
          .toList();

      setState(() {
        // contactsList = spreadedContactsList;
        isContactsInitialized = true;
      });

      StoreProvider.of<AppState>(context)
          .dispatch(DispatchModel(setContactsListT, spreadedContactsList));

      if (kDebugMode) {
        print(rawContactsList);
      }
    }
  }

  final GlobalKey<NavigatorState> navigatorTabKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AppState>(builder: (context, state) {
      int unreadTotal = state.messages.isEmpty
          ? 0
          : state.messages
              .map((message) => message.unread)
              .reduce((a, b) => a + b);
      if (!isMessagesInitialized) {
        getConversationListProcess(context);
      }
      if (!isContactsInitialized) {
        getContactsProcess(context);
      }
      if (!isNotificationsInitialized) {
        getNotificationsListProcess(context);
      }
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Container(
              color: Color(0xfff0f2f5),
              width: MediaQuery.of(context).size.width,
              child: Stack(
                children: [
                  Column(
                      mainAxisAlignment: MainAxisAlignment.center,
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
                                top: 30, bottom: 0, left: 10, right: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                Text(
                                  "Chatterloop",
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF565656)),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                          maxWidth: 40, maxHeight: 40),
                                      child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.transparent,
                                              elevation: 0,
                                              padding: EdgeInsets.only(
                                                  top: 0,
                                                  bottom: 0,
                                                  left: 0,
                                                  right: 0)),
                                          onPressed: () {
                                            AppRoutes.privateNavigatorKey
                                                .currentState
                                                ?.pushNamed("/messages");
                                          },
                                          child: Stack(
                                            children: [
                                              Center(
                                                child: Icon(
                                                  color: Color(0xff555555),
                                                  Icons
                                                      .messenger_outline_rounded,
                                                  size: 23,
                                                ),
                                              ),
                                              unreadTotal > 0
                                                  ? Positioned(
                                                      bottom: 5,
                                                      right: 0,
                                                      child: Container(
                                                        decoration: BoxDecoration(
                                                            color: Colors.red,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        10)),
                                                        width: 22,
                                                        height: 17,
                                                        child: Center(
                                                          child: Text(
                                                            unreadTotal > 99
                                                                ? "+99"
                                                                : unreadTotal
                                                                    .toString(),
                                                            style: TextStyle(
                                                                fontSize: 10,
                                                                color: Colors
                                                                    .white),
                                                          ),
                                                        ),
                                                      ))
                                                  : SizedBox(
                                                      height: 0,
                                                    )
                                            ],
                                          )),
                                    ),
                                    SizedBox(
                                      width: 5,
                                    ),
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                          maxWidth: 40, maxHeight: 40),
                                      child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.transparent,
                                              elevation: 0,
                                              padding: EdgeInsets.only(
                                                  top: 0,
                                                  bottom: 0,
                                                  left: 0,
                                                  right: 0)),
                                          onPressed: () {
                                            AppRoutes.privateNavigatorKey
                                                .currentState
                                                ?.pushNamed("/notifications");
                                          },
                                          child: Stack(
                                            children: [
                                              Center(
                                                child: Icon(
                                                  color: Color(0xff555555),
                                                  Icons.notifications_none,
                                                  size: 25,
                                                ),
                                              ),
                                              state.notificationsstate
                                                          .totalunread >
                                                      0
                                                  ? Positioned(
                                                      bottom: 5,
                                                      right: 0,
                                                      child: Container(
                                                        decoration: BoxDecoration(
                                                            color: Colors.red,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        10)),
                                                        width: 22,
                                                        height: 17,
                                                        child: Center(
                                                          child: Text(
                                                            state.notificationsstate
                                                                        .totalunread >
                                                                    99
                                                                ? "+99"
                                                                : state
                                                                    .notificationsstate
                                                                    .totalunread
                                                                    .toString(),
                                                            style: TextStyle(
                                                                fontSize: 10,
                                                                color: Colors
                                                                    .white),
                                                          ),
                                                        ),
                                                      ))
                                                  : SizedBox(
                                                      height: 0,
                                                    )
                                            ],
                                          )),
                                    ),
                                    SizedBox(
                                      width: 5,
                                    ),
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                          maxWidth: 40, maxHeight: 40),
                                      child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.transparent,
                                              elevation: 0,
                                              padding: EdgeInsets.only(
                                                  top: 0,
                                                  bottom: 0,
                                                  left: 0,
                                                  right: 0)),
                                          onPressed: () async {
                                            await storage.delete(key: 'token');
                                            StoreProvider.of<AppState>(context)
                                                .dispatch(DispatchModel(
                                                    setUserAuthT,
                                                    UserAuth(
                                                        false,
                                                        UserAccount(
                                                            "",
                                                            UserFullname(
                                                                "", "", ""),
                                                            "",
                                                            false,
                                                            false,
                                                            null,
                                                            null,
                                                            null,
                                                            null))));
                                            // navigatorKey.currentState
                                            //     ?.popAndPushNamed("/login");
                                            SseConnection().closeConnection();
                                            // navigatorKey.currentState
                                            //     ?.pushNamedAndRemoveUntil(
                                            //         '/login',
                                            //         (Route<dynamic> route) =>
                                            //             false);
                                            restart();
                                          },
                                          child: Center(
                                            child: Icon(
                                              Icons.logout,
                                              size: 23,
                                              color: Colors.red,
                                            ),
                                          )),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                            child: MaterialApp(
                          initialRoute: "/home",
                          navigatorKey: navigatorTabKey,
                          routes: AppRoutes.tabs,
                        )),
                        Container(
                          decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border(
                                  top: BorderSide(
                                      width: 0.5, color: Color(0xffd2d2d2)))),
                          height: 70,
                          padding: EdgeInsets.all(10),
                          width: MediaQuery.of(context).size.width,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              ElevatedButton(
                                onPressed: () {
                                  navigatorTabKey.currentState
                                      ?.pushNamed("/home");
                                },
                                style: _buttonStyle(false),
                                child: Center(
                                  child: Icon(
                                    Icons.home_outlined,
                                    size: 30,
                                  ),
                                ),
                              ),
                              ElevatedButton(
                                  onPressed: () {
                                    navigatorTabKey.currentState
                                        ?.pushNamed("/map");
                                  },
                                  style: _buttonStyle(false),
                                  child: Icon(
                                    Icons.map_outlined,
                                    size: 27,
                                  )),
                              ElevatedButton(
                                  onPressed: () {
                                    navigatorTabKey.currentState
                                        ?.pushNamed("/contacts");
                                  },
                                  style: _buttonStyle(false),
                                  child: Icon(
                                    Icons.contacts_outlined,
                                    size: 25,
                                  )),
                              ElevatedButton(
                                  onPressed: () {
                                    navigatorTabKey.currentState
                                        ?.pushNamed("/servers");
                                  },
                                  style: _buttonStyle(false),
                                  child: Icon(
                                    Icons.dataset_outlined,
                                    size: 27,
                                  )),
                              ElevatedButton(
                                  onPressed: () {
                                    AppRoutes.privateNavigatorKey.currentState
                                        ?.pushNamed("/profile");
                                  },
                                  style: _buttonStyle(false),
                                  child: Icon(
                                    Icons.person_2_sharp,
                                    size: 30,
                                  )),
                            ],
                          ),
                        )
                      ]),
                  // Positioned(
                  //     top: 0,
                  //     height: 60,
                  //     width: MediaQuery.of(context).size.width,
                  //     child: ),
                ],
              ),
            ),
          ),
        ),
      );
    }, converter: (store) {
      return store.state;
    });
  }
}
