// Single GoRouter config, replacing the old three-tier
// GlobalKey<NavigatorState> / nested-MaterialApp structure in app_routes.dart
// (outer navigatorKey, private privateNavigatorKey, and a third
// navigatorTabKey local to home_view.dart for the bottom tab bar).

import 'package:chatterloop_app/core/auth/auth_controller.dart';
import 'package:chatterloop_app/models/call_models/incoming_call_alert_model.dart';
import 'package:chatterloop_app/views/auth/login_view.dart';
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
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
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
          return path == '/login' || path == '/signup' || path == '/splash'
              ? '/messages'
              : null;
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
