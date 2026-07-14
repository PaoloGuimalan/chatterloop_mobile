// Chrome around the four bottom-tab branches currently in scope (messages/
// contacts/search/profile): top bar with logout, bottom nav bar, and the
// initial conversations/contacts fetch so badge counts are populated before
// the user visits those screens directly. Replaces home_view.dart's body -
// the tab content itself is now StatefulShellRoute's navigationShell rather
// than a third nested Navigator/MaterialApp.
// ignore_for_file: use_build_context_synchronously

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/contacts_api.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/requests/notifications_api.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_item_model.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_state_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

const List<String> _tabTitles = ["Messages", "Contacts", "Search", "Profile"];

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

  Future<void> getConversationListProcess(BuildContext context) async {
    final res = await ConversationsApi().getConversationListRequest();
    if (!mounted) return;
    setState(() => isMessagesInitialized = true);
    if (res == null) return;
    StoreProvider.of<AppState>(context)
        .dispatch(DispatchModel(setMessagesListT, res.items));
  }

  Future<void> getContactsProcess(BuildContext context) async {
    final result = await ContactsApi().getContactsRequest();
    if (!mounted) return;
    setState(() => isContactsInitialized = true);
    StoreProvider.of<AppState>(context)
        .dispatch(DispatchModel(setContactsListT, result.results));
  }

  Future<void> getNotificationsListProcess(BuildContext context) async {
    EncodedResponse? res =
        await NotificationsApi().getNotificationsListRequest();
    if (!mounted) return;
    setState(() => isNotificationsInitialized = true);
    if (res == null) return;
    Map<String, dynamic>? decoded = JwtCodec.decode(res.result);
    List<dynamic> raw = decoded?["notifications"] ?? [];
    List<NotificationsItemModel> list =
        raw.map((n) => NotificationsItemModel.fromJson(n)).toList();
    StoreProvider.of<AppState>(context).dispatch(DispatchModel(
        setNotificationsListT,
        NotificationsStateModel(list, decoded?["totalunread"])));
  }

  Future<void> _logout(BuildContext context) async {
    await ApiClient.instance.clearToken();
    StoreProvider.of<AppState>(context).dispatch(
        DispatchModel(setUserAuthT, UserAuth(false, UserAccount.empty)));
    if (context.mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return StoreConnector<AppState, AppState>(builder: (context, state) {
      int unreadTotal = state.messages.isEmpty
          ? 0
          : state.messages.map((m) => m.unread).reduce((a, b) => a + b);
      if (!isMessagesInitialized) getConversationListProcess(context);
      if (!isContactsInitialized) getContactsProcess(context);
      if (!isNotificationsInitialized) getNotificationsListProcess(context);

      return Scaffold(
        backgroundColor: p.bg,
        body: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
              decoration: BoxDecoration(
                  color: p.surface,
                  border: Border(bottom: BorderSide(color: p.border))),
              child: SafeArea(
                bottom: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_tabTitles[widget.navigationShell.currentIndex],
                        style: TextStyle(
                            color: p.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                    Row(
                      children: [
                        _badgeIconButton(
                          icon: Icons.notifications_none,
                          count: state.notificationsstate.totalunread,
                          onPressed: () => context.push('/notifications'),
                        ),
                        CLIconBtn(
                          icon: Icons.logout,
                          color: p.pink,
                          tooltip: "Logout",
                          onPressed: () => _logout(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: widget.navigationShell),
            Container(
              decoration: BoxDecoration(
                  color: p.surface,
                  border: Border(top: BorderSide(color: p.border))),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SafeArea(
                top: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _badgeNavButton(
                        Icons.chat_bubble_outline,
                        widget.navigationShell.currentIndex == 0,
                        unreadTotal,
                        () => widget.navigationShell.goBranch(0)),
                    _navButton(
                        Icons.contacts_outlined,
                        widget.navigationShell.currentIndex == 1,
                        () => widget.navigationShell.goBranch(1)),
                    _navButton(
                        Icons.search,
                        widget.navigationShell.currentIndex == 2,
                        () => widget.navigationShell.goBranch(2)),
                    _navButton(
                        Icons.person_2_outlined,
                        widget.navigationShell.currentIndex == 3,
                        () => widget.navigationShell.goBranch(3)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }, converter: (store) {
      return store.state;
    });
  }

  Widget _navButton(IconData icon, bool active, VoidCallback onPressed) {
    final p = cl(context);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(CLRadii.pill),
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? p.brandSoft : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 24, color: active ? p.brand : p.text2),
      ),
    );
  }

  Widget _badgeIconButton(
      {required IconData icon,
      required int count,
      required VoidCallback onPressed}) {
    final p = cl(context);
    return SizedBox(
      width: 42,
      height: 42,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(child: CLIconBtn(icon: icon, onPressed: onPressed)),
          if (count > 0)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16),
                decoration: BoxDecoration(
                    color: p.pink, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  count > 99 ? "99+" : count.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _badgeNavButton(
      IconData icon, bool active, int count, VoidCallback onPressed) {
    final p = cl(context);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(CLRadii.pill),
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? p.brandSoft : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, size: 24, color: active ? p.brand : p.text2),
            if (count > 0)
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 16),
                  decoration: BoxDecoration(
                      color: p.pink, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    count > 99 ? "99+" : count.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
