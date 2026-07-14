// Chrome around the four bottom-tab branches (home/map/contacts/servers):
// top bar with messenger/notifications/logout icons, bottom nav bar, and
// the initial conversations/contacts/notifications fetch so badge counts
// are populated before the user visits those screens directly. Replaces
// home_view.dart's body - the tab content itself is now StatefulShellRoute's
// navigationShell rather than a third nested Navigator/MaterialApp.
// ignore_for_file: use_build_context_synchronously

import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/http_requests.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/messages_models/messages_list_model.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_item_model.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_state_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

class HomeTabScaffold extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const HomeTabScaffold({super.key, required this.navigationShell});

  @override
  State<HomeTabScaffold> createState() => _HomeTabScaffoldState();
}

class _HomeTabScaffoldState extends State<HomeTabScaffold> {
  bool isMessagesInitialized = false;
  bool isContactsInitialized = false;
  bool isNotificationsInitialized = false;
  final storage = FlutterSecureStorage();

  ButtonStyle _buttonStyle() {
    return ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        fixedSize: Size(50, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(60)),
        elevation: 0,
        padding: EdgeInsets.zero,
        iconColor: Color(0xFF565656),
        overlayColor: Color(0xFF565656));
  }

  Future<void> getConversationListProcess(BuildContext context) async {
    EncodedResponse? res = await APIRequests().getConversationListRequest();
    if (res == null) return;
    Map<String, dynamic>? decoded = jwt.verifyJwt(res.result, secretKey);
    List<dynamic> raw = decoded?["conversationslist"];
    List<MessageItem> list = raw.map((m) => MessageItem.fromJson(m)).toList();
    if (!mounted) return;
    setState(() => isMessagesInitialized = true);
    StoreProvider.of<AppState>(context)
        .dispatch(DispatchModel(setMessagesListT, list));
  }

  Future<void> getNotificationsListProcess(BuildContext context) async {
    EncodedResponse? res = await APIRequests().getNotificationsListRequest();
    if (res == null) return;
    Map<String, dynamic>? decoded = jwt.verifyJwt(res.result, secretKey);
    List<dynamic> raw = decoded?["notifications"];
    List<NotificationsItemModel> list =
        raw.map((n) => NotificationsItemModel.fromJson(n)).toList();
    if (!mounted) return;
    setState(() => isNotificationsInitialized = true);
    StoreProvider.of<AppState>(context).dispatch(DispatchModel(
        setNotificationsListT,
        NotificationsStateModel(list, decoded?["totalunread"])));
  }

  Future<void> getContactsProcess(BuildContext context) async {
    EncodedResponse? res = await APIRequests().getContactsRequest();
    if (res == null) return;
    Map<String, dynamic>? decoded = jwt.verifyJwt(res.result, secretKey);
    List<dynamic> raw = decoded?["contacts"];
    List<UserContacts> list = raw.map((c) => UserContacts.fromJson(c)).toList();
    if (!mounted) return;
    setState(() => isContactsInitialized = true);
    StoreProvider.of<AppState>(context)
        .dispatch(DispatchModel(setContactsListT, list));
  }

  Future<void> _logout(BuildContext context) async {
    await storage.delete(key: 'token');
    StoreProvider.of<AppState>(context).dispatch(
        DispatchModel(setUserAuthT, UserAuth(false, UserAccount.empty)));
    if (context.mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AppState>(builder: (context, state) {
      int unreadTotal = state.messages.isEmpty
          ? 0
          : state.messages.map((m) => m.unread).reduce((a, b) => a + b);
      if (!isMessagesInitialized) getConversationListProcess(context);
      if (!isContactsInitialized) getContactsProcess(context);
      if (!isNotificationsInitialized) getNotificationsListProcess(context);

      return Scaffold(
        body: Container(
          color: Color(0xfff0f2f5),
          width: MediaQuery.of(context).size.width,
          child: Column(
            children: [
              Container(
                height: 90,
                decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                        bottom:
                            BorderSide(width: 0.5, color: Color(0xffd2d2d2)))),
                child: Padding(
                  padding:
                      EdgeInsets.only(top: 30, bottom: 0, left: 10, right: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Text("Chatterloop",
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF565656))),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _badgeIconButton(
                            icon: Icons.messenger_outline_rounded,
                            count: unreadTotal,
                            onPressed: () => context.push('/messages'),
                          ),
                          SizedBox(width: 5),
                          _badgeIconButton(
                            icon: Icons.notifications_none,
                            count: state.notificationsstate.totalunread,
                            onPressed: () => context.push('/notifications'),
                          ),
                          SizedBox(width: 5),
                          ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: 40, maxHeight: 40),
                            child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    elevation: 0,
                                    padding: EdgeInsets.zero),
                                onPressed: () => _logout(context),
                                child: Center(
                                  child: Icon(Icons.logout,
                                      size: 23, color: Colors.red),
                                )),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
              Expanded(child: widget.navigationShell),
              Container(
                decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                        top: BorderSide(width: 0.5, color: Color(0xffd2d2d2)))),
                height: 70,
                padding: EdgeInsets.all(10),
                width: MediaQuery.of(context).size.width,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    ElevatedButton(
                      onPressed: () => widget.navigationShell.goBranch(0),
                      style: _buttonStyle(),
                      child: Icon(Icons.home_outlined, size: 30),
                    ),
                    ElevatedButton(
                      onPressed: () => widget.navigationShell.goBranch(1),
                      style: _buttonStyle(),
                      child: Icon(Icons.map_outlined, size: 27),
                    ),
                    ElevatedButton(
                      onPressed: () => widget.navigationShell.goBranch(2),
                      style: _buttonStyle(),
                      child: Icon(Icons.contacts_outlined, size: 25),
                    ),
                    ElevatedButton(
                      onPressed: () => widget.navigationShell.goBranch(3),
                      style: _buttonStyle(),
                      child: Icon(Icons.dataset_outlined, size: 27),
                    ),
                    ElevatedButton(
                      onPressed: () => context.push('/profile'),
                      style: _buttonStyle(),
                      child: Icon(Icons.person_2_sharp, size: 30),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      );
    }, converter: (store) {
      return store.state;
    });
  }

  Widget _badgeIconButton(
      {required IconData icon,
      required int count,
      required VoidCallback onPressed}) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 40, maxHeight: 40),
      child: ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              elevation: 0,
              padding: EdgeInsets.zero),
          onPressed: onPressed,
          child: Stack(
            children: [
              Center(child: Icon(color: Color(0xff555555), icon, size: 23)),
              count > 0
                  ? Positioned(
                      bottom: 5,
                      right: 0,
                      child: Container(
                        decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10)),
                        width: 22,
                        height: 17,
                        child: Center(
                          child: Text(count > 99 ? "+99" : count.toString(),
                              style:
                                  TextStyle(fontSize: 10, color: Colors.white)),
                        ),
                      ))
                  : SizedBox(height: 0)
            ],
          )),
    );
  }
}
