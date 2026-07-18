// Single GoRouter config, replacing the old three-tier
// GlobalKey<NavigatorState> / nested-MaterialApp structure in app_routes.dart
// (outer navigatorKey, private privateNavigatorKey, and a third
// navigatorTabKey local to home_view.dart for the bottom tab bar).

import 'package:chatterloop_app/core/auth/auth_controller.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/models/call_models/incoming_call_alert_model.dart';
import 'package:chatterloop_app/views/auth/login_view.dart';
import 'package:chatterloop_app/views/auth/setup_view.dart';
import 'package:chatterloop_app/views/calls/active_call_view.dart';
import 'package:chatterloop_app/views/calls/incoming_call_view.dart';
import 'package:chatterloop_app/views/auth/signup_view.dart';
import 'package:chatterloop_app/views/auth/verify_email_view.dart';
import 'package:chatterloop_app/views/home/tabs/contacts_view.dart';
import 'package:chatterloop_app/views/home/tabs/profile_view.dart';
import 'package:chatterloop_app/views/messages/messages_view.dart';
import 'package:chatterloop_app/views/messages/tabs/conversation_view.dart';
import 'package:chatterloop_app/views/notifications/notifications_view.dart';
import 'package:chatterloop_app/views/profile/profile_edit_view.dart';
import 'package:chatterloop_app/views/profile/realm_profile_view.dart';
import 'package:chatterloop_app/views/profile/user_profile_view.dart';
import 'package:chatterloop_app/views/search/search_view.dart';
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
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Every route below goes through this instead of GoRoute's plain `builder`
/// so pushes/pops get one consistent slide+fade instead of relying on
/// per-platform MaterialPageRoute defaults (Android's ZoomPageTransitions
/// in particular reads as an abrupt cut at normal tap speed).
CustomTransitionPage<void> _clPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
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
    },
  );
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
          return gateScreens.contains(path) ? '/messages' : null;
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
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/search',
                    pageBuilder: (c, s) => _clPage(s, const SearchScreen()))
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/profile',
                    pageBuilder: (c, s) => _clPage(s, const ProfileView()))
              ]),
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
              pageBuilder: (c, s) =>
                  _clPage(s, const DeviceSessionsScreen())),
          GoRoute(
              path: '/settings/personal-information',
              pageBuilder: (c, s) =>
                  _clPage(s, const PersonalInformationScreen())),
          GoRoute(
              path: '/settings/credentials',
              pageBuilder: (c, s) => _clPage(s, const CredentialsScreen())),
          GoRoute(
              path: '/settings/blocked-accounts',
              pageBuilder: (c, s) =>
                  _clPage(s, const BlockedAccountsScreen())),
          GoRoute(
              path: '/settings/data-privacy',
              pageBuilder: (c, s) => _clPage(s, const DataPrivacyScreen())),
          GoRoute(
              path: '/settings/archives',
              pageBuilder: (c, s) => _clPage(s, const ArchivesScreen())),
          GoRoute(
              path: '/settings/map',
              pageBuilder: (c, s) =>
                  _clPage(s, const MapFeedSettingsScreen())),
          GoRoute(
              path: '/notifications',
              pageBuilder: (c, s) => _clPage(s, const NotificationsView())),
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
        ],
      ),
    ],
  );
  _appRouter = router;
  return router;
}
