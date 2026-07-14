// Single GoRouter config, replacing the old three-tier
// GlobalKey<NavigatorState> / nested-MaterialApp structure in app_routes.dart
// (outer navigatorKey, private privateNavigatorKey, and a third
// navigatorTabKey local to home_view.dart for the bottom tab bar).

import 'package:chatterloop_app/core/auth/auth_controller.dart';
import 'package:chatterloop_app/views/auth/login_view.dart';
import 'package:chatterloop_app/views/auth/signup_view.dart';
import 'package:chatterloop_app/views/auth/verify_email_view.dart';
import 'package:chatterloop_app/views/home/tabs/contacts_view.dart';
import 'package:chatterloop_app/views/home/tabs/feed_view.dart';
import 'package:chatterloop_app/views/home/tabs/map_view.dart';
import 'package:chatterloop_app/views/home/tabs/profile_view.dart';
import 'package:chatterloop_app/views/home/tabs/server_view.dart';
import 'package:chatterloop_app/views/messages/messages_view.dart';
import 'package:chatterloop_app/views/messages/tabs/conversation_view.dart';
import 'package:chatterloop_app/views/notifications/notifications_view.dart';
import 'package:chatterloop_app/views/shell/authenticated_shell.dart';
import 'package:chatterloop_app/views/shell/home_tab_scaffold.dart';
import 'package:chatterloop_app/views/splash/welcome_view.dart';
import 'package:go_router/go_router.dart';

GoRouter buildAppRouter(AuthController authController) {
  return GoRouter(
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
              ? '/home'
              : null;
      }
    },
    routes: [
      GoRoute(
          path: '/splash', builder: (context, state) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
          path: '/signup', builder: (context, state) => const SignupScreen()),
      GoRoute(
          path: '/verify-email',
          builder: (context, state) => const VerifyEmailScreen()),
      ShellRoute(
        builder: (context, state, child) => AuthenticatedShell(child: child),
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) =>
                HomeTabScaffold(navigationShell: navigationShell),
            branches: [
              StatefulShellBranch(routes: [
                GoRoute(path: '/home', builder: (c, s) => const FeedView())
              ]),
              StatefulShellBranch(routes: [
                GoRoute(path: '/map', builder: (c, s) => const MapView())
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/contacts', builder: (c, s) => const ContactsView())
              ]),
              StatefulShellBranch(routes: [
                GoRoute(path: '/servers', builder: (c, s) => const ServerView())
              ]),
            ],
          ),
          GoRoute(path: '/messages', builder: (c, s) => const MessagesView()),
          GoRoute(
            path: '/conversation/:conversationId',
            builder: (c, s) => ConversationView(
              conversationId: s.pathParameters['conversationId']!,
              extra: s.extra,
            ),
          ),
          GoRoute(
              path: '/notifications',
              builder: (c, s) => const NotificationsView()),
          GoRoute(path: '/profile', builder: (c, s) => const ProfileView()),
        ],
      ),
    ],
  );
}
