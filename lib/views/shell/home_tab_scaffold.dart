// Chrome around the four bottom-tab branches currently in scope (messages/
// contacts/search/profile): top bar with logout, bottom nav bar, and the
// initial conversations/contacts fetch so badge counts are populated before
// the user visits those screens directly. Replaces home_view.dart's body -
// the tab content itself is now StatefulShellRoute's navigationShell rather
// than a third nested Navigator/MaterialApp.
// ignore_for_file: use_build_context_synchronously

import 'package:chatterloop_app/core/design/theme_provider.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/notifications/push_notification_service.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/contacts_api.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/requests/notifications_api.dart';
import 'package:chatterloop_app/core/requests/sse_connection.dart';
import 'package:chatterloop_app/core/reusables/widgets/user_menu_popover.dart';
import 'package:chatterloop_app/core/notifications/conversation_shortcuts.dart';
import 'package:chatterloop_app/core/notifications/notification_renderer.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/messages_models/messages_list_model.dart';
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
  bool isActiveUsersInitialized = false;

  // Bottom-tab switches go through StatefulNavigationShell.goBranch, which
  // just flips IndexedStack's index (no page route), keeping each branch's
  // Navigator (scroll position/loaded state) alive. On each switch the new
  // content gets a small slide-in nudge (didUpdateWidget below) via
  // AnimatedSlide - a TRANSFORM, so it's ~free on the raster thread. This
  // deliberately replaced an AnimatedOpacity cross-fade that wrapped the whole
  // IndexedStack: animating opacity across all four branches forced a
  // full-screen saveLayer every frame, which was the "clunky screen switch".
  int _lastTabIndex = 0;
  // Rests at zero (no offset). On a tab change the offset jumps to _kTabNudge
  // instantly (duration zero), then animates back to zero - a clean
  // one-directional slide-up. Everything sits on the same scaffold bg, so the
  // briefly-revealed strip is the same colour (no visible gap).
  Offset _tabSlide = Offset.zero;
  Duration _tabSlideDur = Duration.zero;
  static const Offset _kTabNudge = Offset(0, 0.02);
  static const Duration _kTabSlideMs = Duration(milliseconds: 190);

  final GlobalKey _profileButtonKey = GlobalKey();

  // Detected inside the StoreConnector builder below (not didUpdateWidget -
  // this doesn't come from widget's own constructor params, it's Redux
  // state), so the entity-scoped fetches this gates re-fire against the
  // newly active entity after a switch, mirroring webapp's post-switch
  // full reload without an actual app restart.
  String? _lastEntityId;

  @override
  void initState() {
    super.initState();
    // The tab shell only mounts once the user is authenticated, so this is the
    // contextual moment to request notification permission - not on a cold
    // launch (which would burn Android's one-shot dialog before the user has
    // any reason to say yes). No-op on Android < 13 or if already asked.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!PushNotificationService.instance.permissionAlreadyAsked) {
        PushNotificationService.instance.requestPermission();
      }
    });
  }

  @override
  void didUpdateWidget(covariant HomeTabScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = widget.navigationShell.currentIndex;
    if (index == _lastTabIndex) return;
    _lastTabIndex = index;
    // Jump to the start offset with NO animation, then slide back to rest on
    // the next frame - AnimatedSlide animates only the second change, giving a
    // one-directional slide-in (not a down-then-up wobble).
    _tabSlide = _kTabNudge;
    _tabSlideDur = Duration.zero;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _tabSlideDur = _kTabSlideMs;
        _tabSlide = Offset.zero;
      });
    });
  }

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

  /// One-time online-status snapshot for contacts - live updates after
  /// this land via SSE ("active_users" events, see sse_events.dart), which
  /// this app's already-open SSE connection receives regardless of which
  /// tab/screen is showing.
  Future<void> getActiveUsersProcess(BuildContext context) async {
    final result = await ConversationsApi().getActiveContactsRequest();
    if (!mounted) return;
    setState(() => isActiveUsersInitialized = true);
    StoreProvider.of<AppState>(context)
        .dispatch(DispatchModel(setActiveUsersListT, result));
  }

  /// Mirrors webapp's logoutProcess exactly: clearStates() +
  /// CloseSSENotifications() + LogoutRequest, in that order. The clear was
  /// previously done via setUserAuthT, which only merges the new (signed-
  /// out) userAuth into the existing state via copyWith - every other slice
  /// (messages/contacts/notifications/presence/typing/reply-assist) stayed
  /// stale in Redux even after logout. resetAppStateT wholesale-replaces
  /// AppState instead, so it actually clears them, same as EntityApi's
  /// switch flow already does. SSE was previously only closed indirectly
  /// via AuthenticatedShell.dispose() firing once the auth redirect
  /// unmounts that subtree - explicit here too so it's not solely
  /// dependent on that widget teardown timing, matching webapp's own
  /// belt-and-suspenders approach (it calls CloseSSENotifications()
  /// directly from logoutProcess AND separately closes sockets in its
  /// mount effect's cleanup).
  Future<void> _logout(BuildContext context) async {
    // Explicit server logout FIRST, while still authenticated (before the
    // local token is cleared): the /u/logout endpoint nulls THIS device's FCM
    // push token on its session row, so it stops being a push target. The
    // separate status=false half is handled by the SSE close below. Best-
    // effort in a try/catch - a failed logout call must never block sign-out.
    try {
      await ApiClient.instance.dio.post(Endpoints().logout);
    } catch (_) {}
    StoreProvider.of<AppState>(context).dispatch(
        DispatchModel(resetAppStateT, UserAuth(false, UserAccount.empty)));
    SseConnection().closeConnection();
    await ApiClient.instance.clearToken();
    // Clear the tray and every stored push thread - notifications outlive the
    // session, so without this the next account to log in on this device would
    // see the previous one's messages sitting in the notification shade.
    await NotificationRenderer.dismissAll();
    // Shortcuts outlive the session too - without this the next account would
    // see the previous one's contacts in the launcher and the shade.
    await ConversationShortcuts.clearAll();
    if (context.mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    // Persistent shell hosting every tab - previously rebuilt (app bar +
    // bottom nav + unread reduce) on every dispatch app-wide. Narrow to the
    // three slices it reads so it only rebuilds when unread/identity/
    // notifications actually change.
    return StoreConnector<
            AppState,
            ({
              List<MessageItem> messages,
              UserAuth userAuth,
              NotificationsStateModel notificationsstate
            })>(
        distinct: true,
        builder: (context, state) {
          int unreadTotal = state.messages.isEmpty
              ? 0
              : state.messages.map((m) => m.unread).reduce((a, b) => a + b);

          final entityId = state.userAuth.user.entityId;
          if (_lastEntityId != null && _lastEntityId != entityId) {
            isMessagesInitialized = false;
            isContactsInitialized = false;
            isNotificationsInitialized = false;
            isActiveUsersInitialized = false;
          }
          _lastEntityId = entityId;

          if (!isMessagesInitialized) getConversationListProcess(context);
          if (!isContactsInitialized) getContactsProcess(context);
          if (!isNotificationsInitialized) getNotificationsListProcess(context);
          if (!isActiveUsersInitialized) getActiveUsersProcess(context);

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
                            CLIconBtn(
                              icon: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Icons.light_mode_outlined
                                  : Icons.dark_mode_outlined,
                              tooltip: "Toggle theme",
                              onPressed: () => ThemeScope.of(context).toggle(),
                            ),
                            _badgeIconButton(
                              icon: Icons.notifications_none,
                              count: state.notificationsstate.totalunread,
                              onPressed: () => context.push('/notifications'),
                            ),
                            const SizedBox(width: 4),
                            // Logout moved into the user menu (opened from the
                            // bottom-nav menu button) - this now shows whichever
                            // entity is currently active (yourself, or a page
                            // you've switched to). Tapping it goes to that same
                            // active entity's own profile - the personal Profile
                            // tab normally, or the switched-to page's read-only
                            // profile screen while acting as it. The menu's own
                            // "Profile" row (user_menu_popover.dart) mirrors this
                            // exact same entity-aware target.
                            InkWell(
                              onTap: () {
                                final user = state.userAuth.user;
                                if (user.isActingAsEntity) {
                                  context.push(
                                      '/realm/${user.activeEntity?.slug ?? user.activeEntity?.id}');
                                } else {
                                  widget.navigationShell.goBranch(3);
                                }
                              },
                              borderRadius: BorderRadius.circular(CLRadii.pill),
                              child: CLAvatar(
                                id: state.userAuth.user.activeAvatarSeed,
                                name: state.userAuth.user.activeDisplayName,
                                src: state.userAuth.user.activeAvatarSrc,
                                size: 34,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: AnimatedSlide(
                    offset: _tabSlide,
                    duration: _tabSlideDur,
                    curve: Curves.easeOutCubic,
                    child: widget.navigationShell,
                  ),
                ),
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
                            Icons.menu,
                            widget.navigationShell.currentIndex == 3,
                            () => showUserMenuPopover(context,
                                anchorKey: _profileButtonKey,
                                onOpenProfile: () =>
                                    widget.navigationShell.goBranch(3),
                                onLogout: () => _logout(context)),
                            buttonKey: _profileButtonKey),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        converter: (store) => (
              messages: store.state.messages,
              userAuth: store.state.userAuth,
              notificationsstate: store.state.notificationsstate,
            ));
  }

  Widget _navButton(IconData icon, bool active, VoidCallback onPressed,
      {Key? buttonKey}) {
    final p = cl(context);
    return InkWell(
      key: buttonKey,
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
