import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/reusables/widgets/user_app_shortcuts.dart';
import 'package:chatterloop_app/views/servers/server_channels_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GoRouter shortcutRouter({String initialLocation = '/account'}) =>
    GoRouter(initialLocation: initialLocation, routes: [
      GoRoute(
          path: '/account',
          builder: (_, __) => Scaffold(
                appBar: AppBar(title: const Text('Account apps')),
                body: UserAppShortcuts(onSettings: () {}),
              )),
      GoRoute(
          path: '/servers',
          builder: (_, __) =>
              const Scaffold(body: Text('Servers welcome tab'))),
      GoRoute(
          path: '/server-browser', builder: (_, __) => const ServerScreen()),
      GoRoute(
          path: '/diary',
          builder: (_, __) => const Scaffold(body: Text('Diary destination'))),
    ]);

void main() {
  late Map<Dio, List<Interceptor>> interceptors;
  setUp(() {
    interceptors = {
      ApiClient.instance.dio: List.of(ApiClient.instance.dio.interceptors),
      ApiClient.userService.dio:
          List.of(ApiClient.userService.dio.interceptors),
    };
    for (final dio in interceptors.keys) {
      dio.interceptors.clear();
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(requestOptions: options, data: {
          'status': false,
          'count': 0,
          'next': null,
          'previous': null,
          'results': [],
        }));
      }));
    }
  });
  tearDown(() {
    for (final entry in interceptors.entries) {
      entry.key.interceptors
        ..clear()
        ..addAll(entry.value);
    }
  });

  testWidgets('Servers shortcut opens the full browser directly',
      (tester) async {
    final router = shortcutRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Servers'));
    await tester.pumpAndSettle();
    expect(find.byType(ServerScreen), findsOneWidget);
    expect(find.text('Servers welcome tab'), findsNothing);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Account apps'), findsOneWidget);
  });
  testWidgets('Server browser back works from the Servers tab', (tester) async {
    final router = shortcutRouter(initialLocation: '/servers');
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    await tester.pumpAndSettle();
    router.push('/server-browser');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Servers welcome tab'), findsOneWidget);
    expect(find.byType(ServerScreen), findsNothing);
  });
  testWidgets('Server browser opened directly has a safe back destination',
      (tester) async {
    final router = shortcutRouter(initialLocation: '/server-browser');
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Servers welcome tab'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Diary is hidden for pages and returns for personal accounts',
      (tester) async {
    Future<void> showApps(bool isActingAsPage) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(
            body: UserAppShortcuts(
                onSettings: () {}, isActingAsPage: isActingAsPage)),
      ));
      await tester.pumpAndSettle();
    }

    await showApps(true);
    expect(find.text('Diary'), findsNothing);
    expect(find.text('Manage realm'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    await showApps(false);
    expect(find.text('Diary'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
  testWidgets('Diary opens and Notes remains unavailable', (tester) async {
    final router = shortcutRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Account apps'), findsOneWidget);
    await tester.tap(find.text('Diary'));
    await tester.pumpAndSettle();
    expect(find.text('Diary destination'), findsOneWidget);
  });
}
