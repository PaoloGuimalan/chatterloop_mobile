// Single GoRouter config, replacing the old three-tier
// GlobalKey<NavigatorState> / nested-MaterialApp structure in app_routes.dart
// (outer navigatorKey, private privateNavigatorKey, and a third
// navigatorTabKey local to home_view.dart for the bottom tab bar).

import 'package:chatterloop_app/core/auth/auth_controller.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/models/call_models/incoming_call_alert_model.dart';
import 'package:chatterloop_app/views/auth/login_view.dart';
import 'package:chatterloop_app/views/diary/diary_compose_view.dart';
import 'package:chatterloop_app/views/diary/diary_entry_view.dart';
import 'package:chatterloop_app/views/diary/diary_list_view.dart';
import 'package:chatterloop_app/views/auth/setup_view.dart';
import 'package:chatterloop_app/views/calls/active_call_view.dart';
import 'package:chatterloop_app/views/calls/incoming_call_view.dart';
import 'package:chatterloop_app/views/auth/signup_view.dart';
import 'package:chatterloop_app/views/auth/verify_email_view.dart';
import 'package:chatterloop_app/views/home/tabs/contacts_detail_view.dart';
import 'package:chatterloop_app/views/home/tabs/contacts_view.dart';
import 'package:chatterloop_app/views/messages/messages_view.dart';
import 'package:chatterloop_app/views/newsfeed/newsfeed_view.dart';
import 'package:chatterloop_app/views/messages/tabs/conversation_view.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_v2_model.dart';
import 'package:chatterloop_app/views/notifications/notifications_detail_view.dart';
import 'package:chatterloop_app/views/notifications/notifications_view.dart';
import 'package:chatterloop_app/views/profile/profile_edit_view.dart';
import 'package:chatterloop_app/views/profile/realm_profile_view.dart';
import 'package:chatterloop_app/views/realm/realm_manage_view.dart';
import 'package:chatterloop_app/views/profile/user_profile_view.dart';
import 'package:chatterloop_app/views/search/post_preview_view.dart';
import 'package:chatterloop_app/views/search/search_detail_view.dart';
import 'package:chatterloop_app/views/search/search_view.dart';
import 'package:chatterloop_app/views/servers/server_channels_view.dart';
import 'package:chatterloop_app/views/servers/servers_view.dart';
import 'package:chatterloop_app/views/settings/archives_view.dart';
import 'package:chatterloop_app/views/settings/blocked_accounts_view.dart';
import 'package:chatterloop_app/views/settings/credentials_view.dart';
import 'package:chatterloop_app/views/settings/data_privacy_view.dart';
import 'package:chatterloop_app/views/settings/map_feed_view.dart';
import 'package:chatterloop_app/views/settings/device_sessions_view.dart';
import 'package:chatterloop_app/views/settings/personal_information_view.dart';
import 'package:chatterloop_app/views/settings/settings_view.dart';
import 'package:chatterloop_app/views/shell/authenticated_shell.dart';
import 'package:chatterloop_app/views/shell/home_tab_scaffold.dart';
import 'package:chatterloop_app/views/splash/welcome_view.dart';
import 'package:chatterloop_app/views/switching/switching_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Every route below goes through this instead of GoRoute's plain `builder`
/// so pushes/pops get one consistent slide instead of relying on per-platform
/// MaterialPageRoute defaults (Android's ZoomPageTransitions in particular
/// reads as an abrupt cut at normal tap speed).
Page<void> _clPage(GoRouterState state, Widget child) =>
    CLPage(key: state.pageKey, child: child);

/// Deliberately a hand-rolled Page/PageRoute pair rather than go_router's
/// `CustomTransitionPage`, for ONE reason: [CLPageRoute.canTransitionTo].
///
/// Public (rather than private to this file) so the transition rule can be
/// tested directly - see test/redesign_layout_test.dart. It got shipped wrong
/// once, and the symptom only shows on a device.
class CLPage extends Page<void> {
  final Widget child;

  const CLPage({required LocalKey super.key, required this.child});

  @override
  Route<void> createRoute(BuildContext context) => CLPageRoute(page: this);
}

class CLPageRoute extends PageRoute<void> {
  CLPageRoute({required CLPage page}) : super(settings: page);

  CLPage get _page => settings as CLPage;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 260);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  /// Only let a route that actually COVERS this one push it aside.
  ///
  /// The parallax below is driven by `secondaryAnimation`, which Navigator only
  /// runs when this returns true for whatever was pushed on top - and the
  /// default (ModalRoute) is true for EVERYTHING. The whole point of drifting
  /// the outgoing page left is that an opaque incoming page hides the gap it
  /// leaves; under a transparent route that gap is just unpainted black down the
  /// right-hand side, with the page visibly shoved off-centre beneath the
  /// overlay.
  ///
  /// `opaque` is the exact property to test, NOT "is it a PageRoute": the
  /// message long-press preview (flutter_chat_reactions' HeroDialogRoute) IS a
  /// PageRoute - it has to be, since Flutter's HeroController only flies heroes
  /// between page routes - it just sets `opaque => false`. Testing for PageRoute
  /// let it straight through.
  ///
  /// Note the parallax only ever applies between two of these pages anyway:
  /// a transition needs BOTH sides to agree (`canTransitionTo` here and
  /// `canTransitionFrom` on the incoming route), and MaterialPageRoute's
  /// `canTransitionFrom` requires the route below to be a Material one. So the
  /// app's few imperative MaterialPageRoute pushes (the policy viewer from
  /// setup/signup, the call screen) never drifted the page below and still
  /// don't - unchanged by this, and not worth becoming a Material route over.
  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) => nextRoute.opaque;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      _page.child;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    // Pure slide (a transform) - deliberately NO FadeTransition. Animating
    // opacity across a whole screen composites the entire incoming page into
    // an offscreen layer (saveLayer) on every frame of the transition, which
    // is a real per-navigation cost and reads as a clunky screen switch. A
    // transform is effectively free on the raster thread. The incoming page
    // slides fully in from the right over the (opaque) outgoing one, which
    // drifts slightly left in parallax so there's never a see-through gap -
    // the standard iOS push, and cheap.
    final incoming = Tween<Offset>(
      begin: const Offset(1.0, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
    final outgoing = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.25, 0),
    ).animate(CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
    return SlideTransition(
      position: outgoing,
      child: SlideTransition(position: incoming, child: child),
    );
  }
}

/// Set once by buildAppRouter, readable from anywhere - needed so
/// sse_events.dart can push the incoming-call screen (M5) in response to
/// an `incomingcall` SSE event, which arrives outside any widget's
/// BuildContext. Same "single instance, no BuildContext needed" pattern as
/// appStore in redux/store.dart.
GoRouter? _appRouter;
GoRouter get appRouter => _appRouter!;

GoRouter buildAppRouter(AuthController authController) {
  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: authController,
    // The app had no errorBuilder, so an unmatched location fell through to
    // go_router default screen - which says "page not found" without saying
    // WHICH path, and that is the one fact needed to fix it. This one names the
    // location and logs it.
    errorBuilder: (context, state) {
      if (kDebugMode) {
        print("[router] no route for: ${state.uri}");
        print("[router] error: ${state.error}");
      }
      final p = cl(context);
      return Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(title: const Text('Page not found')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.link_off, size: 34, color: p.text3),
                const SizedBox(height: 12),
                Text('No screen for this link',
                    style: TextStyle(
                        fontSize: CLType.sectionTitle,
                        fontWeight: FontWeight.w700,
                        color: p.text)),
                const SizedBox(height: 6),
                Text('${state.uri}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: CLType.bodySm, color: p.text2)),
                const SizedBox(height: 18),
                CLBtn(
                  label: 'Go home',
                  onPressed: () => context.go('/newsfeed'),
                ),
              ],
            ),
          ),
        ),
      );
    },
    redirect: (context, state) {
      final path = state.matchedLocation;
      switch (authController.status) {
        case AuthStatus.unknown:
          return path == '/splash' ? null : '/splash';
        case AuthStatus.unauthenticated:
          // /verify-email requires an authtoken (issued by login/signup) -
          // an unauthenticated visitor can't use it, so it's not treated
          // as a public path here.
          return path == '/login' || path == '/signup' ? null : '/login';
        case AuthStatus.authenticated:
          final user = appStore.state.userAuth.user;
          // Gate order mirrors webapp's App.tsx: an unverified email is sent
          // to /verify-email; a verified-but-incomplete account (missing
          // birthdate/gender or with pending terms/privacy consents) is sent
          // to /setup; only a verified + complete account reaches the app.
          if (!user.isVerified) {
            return path == '/verify-email' ? null : '/verify-email';
          }
          if (!user.isComplete) {
            return path == '/setup' ? null : '/setup';
          }
          // Fully cleared - never leave them parked on an auth/gate screen.
          const gateScreens = {
            '/login',
            '/signup',
            '/splash',
            '/verify-email',
            '/setup',
          };
          return gateScreens.contains(path) ? '/newsfeed' : null;
      }
    },
    routes: [
      GoRoute(
          path: '/splash',
          pageBuilder: (c, s) => _clPage(s, const WelcomeScreen())),
      GoRoute(
          path: '/login',
          pageBuilder: (c, s) => _clPage(s, const LoginScreen())),
      GoRoute(
          path: '/signup',
          pageBuilder: (c, s) => _clPage(s, const SignupScreen())),
      GoRoute(
          path: '/verify-email',
          pageBuilder: (c, s) => _clPage(s, const VerifyEmailScreen())),
      // Post-verification gate (webapp's <Setup />): collects any missing
      // birthdate/gender and records terms/privacy consent before the app
      // is reachable. Top-level so it replaces the whole UI, like the other
      // auth screens.
      GoRoute(
          path: '/setup',
          pageBuilder: (c, s) => _clPage(s, const SetupScreen())),
      // Top-level (outside the shell) so it replaces the whole visible UI -
      // no bottom nav/top bar while an entity switch + AppState reset is in
      // flight. `extra` carries the actual switch-back/switch-to-page
      // closure from wherever it was triggered (see user_menu_popover.dart).
      GoRoute(
        path: '/switching',
        pageBuilder: (c, s) => _clPage(
            s, SwitchingScreen(perform: s.extra as Future<bool> Function())),
      ),
      // Both top-level (outside the shell) for the same reason as
      // /switching above - a call is a full-screen, no-bottom-nav
      // experience regardless of which tab it was started from.
      GoRoute(
        path: '/call/incoming',
        pageBuilder: (c, s) =>
            _clPage(s, IncomingCallView(alert: s.extra as IncomingCallAlert)),
      ),
      GoRoute(
        path: '/call/active',
        pageBuilder: (c, s) => _clPage(s, const ActiveCallView()),
      ),
      ShellRoute(
        builder: (context, state, child) => AuthenticatedShell(child: child),
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) =>
                HomeTabScaffold(navigationShell: navigationShell),
            branches: [
              // FIRST branch = leftmost tab, and the app's landing screen.
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/newsfeed',
                    pageBuilder: (c, s) => _clPage(s, const NewsfeedView()))
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/messages',
                    pageBuilder: (c, s) => _clPage(s, const MessagesView()))
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/contacts',
                    pageBuilder: (c, s) => _clPage(s, const ContactsView()))
              ]),
              // Servers sits AFTER contacts, so its branch index is 3 - which
              // pushed search's to 4. Anything calling goBranch must use the
              // list order below, not a remembered number.
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/servers',
                    pageBuilder: (c, s) => _clPage(s, const ServersScreen()))
              ]),
              // Search is NOT a branch any more - it moved to the header, so
              // it is pushed like any other screen. Keeping it in the shell
              // would give it a tab's persistent stack while having no tab.
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/search',
                    pageBuilder: (c, s) => _clPage(s, const SearchScreen()))
              ]),
              // No profile branch. Your own profile is not a tab: it pushes
              // /user/<your username> like any other, so one screen renders
              // every profile and self/visitor differences stay in one place
              // (UserProfileScreen._isSelf) instead of drifting across two
              // implementations.
            ],
          ),
          GoRoute(
            path: '/conversation/:conversationId',
            pageBuilder: (c, s) => _clPage(
                s,
                ConversationView(
                  conversationId: s.pathParameters['conversationId']!,
                )),
          ),
          GoRoute(
              path: '/profile/edit',
              pageBuilder: (c, s) => _clPage(s, const ProfileEditScreen())),
          GoRoute(
              path: '/settings',
              pageBuilder: (c, s) => _clPage(s, const SettingsScreen())),
          GoRoute(
              path: '/settings/device-sessions',
              pageBuilder: (c, s) => _clPage(s, const DeviceSessionsScreen())),
          GoRoute(
              path: '/settings/personal-information',
              pageBuilder: (c, s) =>
                  _clPage(s, const PersonalInformationScreen())),
          GoRoute(
              path: '/settings/credentials',
              pageBuilder: (c, s) => _clPage(s, const CredentialsScreen())),
          GoRoute(
              path: '/settings/blocked-accounts',
              pageBuilder: (c, s) => _clPage(s, const BlockedAccountsScreen())),
          GoRoute(
              path: '/settings/data-privacy',
              pageBuilder: (c, s) => _clPage(s, const DataPrivacyScreen())),
          GoRoute(
              path: '/settings/archives',
              pageBuilder: (c, s) => _clPage(s, const ArchivesScreen())),
          GoRoute(
              path: '/settings/map',
              pageBuilder: (c, s) => _clPage(s, const MapFeedSettingsScreen())),
          GoRoute(
              path: '/notifications',
              pageBuilder: (c, s) => _clPage(s, const NotificationsView())),
          // The three redesigned screens each push a "See all" detail view for
          // one section. All of them live OUTSIDE the StatefulShellRoute above
          // (like /conversation and /notifications) so they replace the tab
          // content and its bottom nav - the design gives them their own header
          // with a back button and a total-count pill.
          //
          // An unknown section slug redirects back to its parent screen rather
          // than rendering an empty list, so a stale deep link degrades to
          // something usable.
          GoRoute(
            path: '/notifications/:section',
            redirect: (c, s) => NotificationSectionSlug.fromSlug(
                        s.pathParameters['section']!) ==
                    null
                ? '/notifications'
                : null,
            pageBuilder: (c, s) => _clPage(
                s,
                NotificationsDetailScreen(
                  section: NotificationSectionSlug.fromSlug(
                      s.pathParameters['section']!)!,
                )),
          ),
          GoRoute(
            path: '/contacts/:section',
            redirect: (c, s) => ContactsDetailSectionMeta.fromSlug(
                        s.pathParameters['section']!) ==
                    null
                ? '/contacts'
                : null,
            pageBuilder: (c, s) => _clPage(
                s,
                ContactsDetailScreen(
                  section: ContactsDetailSectionMeta.fromSlug(
                      s.pathParameters['section']!)!,
                )),
          ),
          // ?q= carries the query the section was opened for - the detail
          // screen pages the same search, it doesn't start a new one.
          GoRoute(
            path: '/search/:kind',
            redirect: (c, s) =>
                SearchDetailKindMeta.fromSlug(s.pathParameters['kind']!) == null
                    ? '/search'
                    : null,
            pageBuilder: (c, s) => _clPage(
                s,
                SearchDetailScreen(
                  kind:
                      SearchDetailKindMeta.fromSlug(s.pathParameters['kind']!)!,
                  query: s.uri.queryParameters['q'] ?? '',
                )),
          ),
          GoRoute(
            path: '/post/:postId',
            pageBuilder: (c, s) => _clPage(
                s, PostPreviewScreen(postId: s.pathParameters['postId']!)),
          ),
          // Diary. Gated on module.diary.access, mirroring webapp's
          // ProfileContainer.tsx: while acting as a page the module simply
          // isn't part of that context, so the redirect goes home rather than
          // showing a permission error - it isn't a failure, the feature just
          // doesn't exist there.
          GoRoute(
            path: '/diary',
            redirect: _diaryGuard,
            pageBuilder: (c, s) => _clPage(s, const DiaryListScreen()),
          ),
          GoRoute(
            path: '/diary/new',
            redirect: _diaryGuard,
            pageBuilder: (c, s) => _clPage(s, const DiaryComposeScreen()),
          ),
          GoRoute(
            path: '/diary/entry/:entryId',
            redirect: _diaryGuard,
            pageBuilder: (c, s) => _clPage(
                s, DiaryEntryScreen(entryId: s.pathParameters['entryId']!)),
          ),
          GoRoute(
            path: '/user/:username',
            pageBuilder: (c, s) => _clPage(
                s, UserProfileScreen(username: s.pathParameters['username']!)),
          ),
          GoRoute(
            path: '/realm/:slug',
            pageBuilder: (c, s) =>
                _clPage(s, RealmProfileScreen(slug: s.pathParameters['slug']!)),
          ),
          // Pushed, so the rail and the directory get the whole screen. The
          // TAB at /servers is just the way in.
          // NOT under '/servers'. go_router walks a location segment by segment,
          // so a sub-path of the '/servers' BRANCH resolves against that branch
          // children - and it has none, which is a "page not found" rather than
          // a fallthrough to a same-named sibling. A path outside any existing
          // route avoids the question.
          GoRoute(
            path: '/server-browser',
            pageBuilder: (c, s) => _clPage(s, const ServerScreen()),
          ),
          GoRoute(
            path: '/server/:serverId',
            pageBuilder: (c, s) => _clPage(
                s,
                ServerScreen(
                  serverId: s.pathParameters['serverId']!,
                  serverName: s.uri.queryParameters['name'],
                  serverProfile: s.uri.queryParameters['profile'],
                )),
          ),
          GoRoute(
            path: '/realm/:slug/manage',
            pageBuilder: (c, s) =>
                _clPage(s, RealmManageScreen(slug: s.pathParameters['slug']!)),
          ),
        ],
      ),
    ],
  );
  _appRouter = router;
  return router;
}

/// The module that carries the diary. Absent while acting as a page/realm -
/// entity-switch re-issues allowed_modules for the new context (see
/// entity_api.dart), so this flips without a re-login.
const String _diaryModule = 'module.diary.access';

/// Sends the diary routes home when the current context has no diary, matching
/// ProfileContainer.tsx's `<Navigate to="/" />` for the same case. Read from
/// the global store rather than context: redirect runs before the route's
/// widget exists, so there is no StoreProvider to read from yet.
String? _diaryGuard(BuildContext context, GoRouterState state) {
  final modules = appStore.state.userAuth.user.allowedModules;
  return modules.contains(_diaryModule) ? null : '/newsfeed';
}
