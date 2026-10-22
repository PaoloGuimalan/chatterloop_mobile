import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/views/messages/messages_gate.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'passphrase_mobile_test.dart' show fixtureConfiguration, fixtureData;

Map<String, dynamic> settings({bool enabled = true, bool active = true}) {
  final data = fixtureData();
  final config = {
    ...fixtureConfiguration(active: active),
    'purposes': ['messages']
  };
  data['purposes'] = [
    {
      'purpose': 'messages',
      'label': 'Messages',
      'is_active': enabled,
      'configurations': [config],
      'active_configuration_id': active ? config['id'] : null,
      'scope_version': 'a' * 64,
    }
  ];
  return data;
}

Future<void> submit(WidgetTester tester, String phrase) async {
  await tester.enterText(find.byType(TextField), phrase);
  await tester.tap(find.text('Unlock'));
  await tester.pump();
  for (var i = 0;
      i < 250 && find.text('Verifying…').evaluate().isNotEmpty;
      i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
  }
  await pumpMessages(tester);
}

// Allow route transitions and deferred modal-dismissal callbacks to complete.
Future<void> pumpMessages(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late List<Interceptor> previous;
  late Map<String, dynamic> data;
  var failLoad = false;
  var deferLoad = false;
  var screenTaps = 0;
  final pendingLoads = <void Function()>[];
  setUp(() {
    data = settings();
    failLoad = false;
    deferLoad = false;
    screenTaps = 0;
    pendingLoads.clear();
    final dio = ApiClient.userService.dio;
    previous = List.of(dio.interceptors);
    dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (options, handler) {
        expect(options.queryParameters['purpose'], 'messages');
        if (failLoad) {
          handler.reject(
              DioException(requestOptions: options, message: 'offline'));
        } else {
          void resolve() => handler.resolve(Response(
              requestOptions: options, data: {'status': true, 'result': data}));
          if (deferLoad) {
            pendingLoads.add(resolve);
          } else {
            resolve();
          }
        }
      }));
  });
  tearDown(() {
    ApiClient.userService.dio.interceptors
      ..clear()
      ..addAll(previous);
  });
  Future<GoRouter> mount(WidgetTester tester,
      {String initial = '/conversation/direct'}) async {
    Widget screen(String label) => Scaffold(
        body: Center(
            child:
                TextButton(onPressed: () => screenTaps++, child: Text(label))));
    final router = GoRouter(initialLocation: initial, routes: [
      GoRoute(
          path: '/messages',
          builder: (_, __) => MessagesGate(child: screen('Private list'))),
      GoRoute(
          path: '/conversation/:id',
          builder: (_, __) =>
              MessagesGate(child: screen('Private conversation'))),
      GoRoute(
          path: '/new-message',
          builder: (_, __) => MessagesGate(child: screen('Private composer'))),
      GoRoute(
          path: '/previous',
          builder: (_, __) =>
              const Scaffold(body: Text('Actual previous page'))),
      GoRoute(
          path: '/newsfeed',
          builder: (_, __) => const Scaffold(body: Text('Safe home'))),
    ]);
    MessagesGate.observe(router);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    await pumpMessages(tester);
    return router;
  }

  testWidgets(
      'Messages keeps its normal screen under a blocking root dialog and Back cancels',
      (tester) async {
    final router = await mount(tester, initial: '/previous');
    router.push('/messages');
    await pumpMessages(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Unlock Messages to continue.'), findsNothing);
    expect(find.text('Private list'), findsOneWidget);
    await tester.tap(find.text('Private list'), warnIfMissed: false);
    expect(screenTaps, 0);
    // The root modal also absorbs taps outside its card.
    await tester.tapAt(const Offset(5, 5));
    await pumpMessages(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await pumpMessages(tester);
    expect(find.text('Actual previous page'), findsOneWidget);
    expect(find.text('Unlock your Messages'), findsNothing);
    expect(find.text('Unlock Messages to continue.'), findsNothing);
  });
  testWidgets('conversation keeps its normal screen under the unlock dialog',
      (tester) async {
    await mount(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Unlock Messages to continue.'), findsNothing);
  });
  testWidgets('Messages tab Back restores the prior tab without a lock screen',
      (tester) async {
    final router = GoRouter(initialLocation: '/newsfeed', routes: [
      StatefulShellRoute.indexedStack(
          builder: (_, __, shell) => Scaffold(
                body: shell,
                bottomNavigationBar: NavigationBar(
                    selectedIndex: shell.currentIndex,
                    onDestinationSelected: shell.goBranch,
                    destinations: const [
                      NavigationDestination(
                          icon: Icon(Icons.home), label: 'Home'),
                      NavigationDestination(
                          icon: Icon(Icons.chat), label: 'Messages tab'),
                    ]),
              ),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/newsfeed',
                  builder: (_, __) => const Text('Home tab content')),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/messages',
                  builder: (_, __) =>
                      const MessagesGate(child: Text('Private list'))),
            ]),
          ]),
    ]);
    MessagesGate.observe(router);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    await pumpMessages(tester);
    await tester.tap(find.text('Messages tab'));
    await pumpMessages(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Home'), warnIfMissed: false);
    await pumpMessages(tester);
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1);
    await tester.binding.handlePopRoute();
    await pumpMessages(tester);
    expect(find.text('Home tab content'), findsOneWidget);
    expect(find.text('Unlock your Messages'), findsNothing);
    expect(find.text('Unlock Messages to continue.'), findsNothing);
    await tester.tap(find.text('Messages tab'));
    await pumpMessages(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    expect(find.text('Private list'), findsOneWidget);
  });
  testWidgets(
      'direct conversation stays blocked under the dialog; wrong phrase stays inline and retries',
      (tester) async {
    await mount(tester);
    expect(find.text('Private conversation'), findsOneWidget);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    await submit(tester, 'wrong phrase');
    expect(find.textContaining('Check your passphrase'), findsOneWidget);
    expect(find.text('Private conversation'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    await submit(tester, 'violet lantern river 你好');
    expect(find.text('Private conversation'), findsOneWidget);
    await tester.tap(find.text('Private conversation'));
    expect(screenTaps, 1);
  }, timeout: const Timeout(Duration(minutes: 3)));
  testWidgets(
      'disabled purpose bypasses; inactive membership has no setup prompt',
      (tester) async {
    data = settings(enabled: false);
    final router = await mount(tester);
    expect(find.text('Private conversation'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    router.go('/previous');
    await pumpMessages(tester);
    data = settings(active: false);
    router.go('/messages');
    await pumpMessages(tester);
    expect(find.text('Private list'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    router.go('/previous');
    await pumpMessages(tester);
    data['purposes'][0]['configurations'] = [];
    router.go('/messages');
    await pumpMessages(tester);
    expect(find.text('Private list'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
  testWidgets(
      'list and conversation share visit; leaving for pushed page and system back relocks',
      (tester) async {
    final router = await mount(tester, initial: '/messages');
    await submit(tester, 'violet lantern river 你好');
    router.push('/conversation/one');
    await pumpMessages(tester);
    expect(find.text('Private conversation'), findsOneWidget);
    expect(find.text('Unlock your Messages'), findsNothing);
    router.push('/previous');
    await pumpMessages(tester);
    router.pop();
    await pumpMessages(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    expect(find.text('Private conversation'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 3)));
  testWidgets(
      'cancel restores prior route and direct entry safely falls back home',
      (tester) async {
    final router = await mount(tester, initial: '/previous');
    router.push('/conversation/direct');
    await pumpMessages(tester);
    await tester.tap(find.text('Cancel'));
    await pumpMessages(tester);
    expect(find.text('Actual previous page'), findsOneWidget);
    router.go('/messages');
    await pumpMessages(tester);
    await tester.tap(find.text('Cancel'));
    await pumpMessages(tester);
    expect(find.text('Actual previous page'), findsOneWidget);
  });
  testWidgets('load error stays closed and offers retry and cancel',
      (tester) async {
    failLoad = true;
    await mount(tester);
    expect(find.text('Private conversation'), findsOneWidget);
    expect(find.textContaining('Could not load Messages protection'),
        findsOneWidget);
    failLoad = false;
    await tester.tap(find.text('Try again'));
    await pumpMessages(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await pumpMessages(tester);
    expect(find.text('Safe home'), findsOneWidget);
  });
  testWidgets('leaving during a prompt dismisses it and reentry prompts again',
      (tester) async {
    final router = await mount(tester);
    await tester.enterText(find.byType(TextField), 'temporary secret');
    router.go('/previous');
    await pumpMessages(tester);
    expect(find.byType(TextField), findsNothing);
    router.go('/conversation/another');
    await pumpMessages(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    expect(find.text('Private conversation'), findsOneWidget);
  });
  testWidgets(
      'Back from a direct conversation ends visit before immediate reopening',
      (tester) async {
    final router = await mount(tester, initial: '/previous');
    router.push('/conversation/direct');
    await pumpMessages(tester);
    await submit(tester, 'violet lantern river 你好');
    router.pop();
    await pumpMessages(tester);
    router.push('/conversation/direct');
    await pumpMessages(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    expect(find.text('Private conversation'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await pumpMessages(tester);
    router.push('/messages');
    await pumpMessages(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    expect(find.text('Private list'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 3)));
  testWidgets(
      'account change cancels prompt secrets and starts a fresh locked visit',
      (tester) async {
    final previousAuth = appStore.state.userAuth;
    addTearDown(
        () => appStore.dispatch(DispatchModel(setUserAuthT, previousAuth)));
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'previous account secret');
    appStore.dispatch(DispatchModel(
        setUserAuthT,
        const UserAuth(
            true,
            UserAccount('other-user', '', '', '', '', '', true, true, null,
                null, null, null))));
    await pumpMessages(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    expect(find.text('Private conversation'), findsOneWidget);
  });
  testWidgets('late bypass response after leaving cannot unlock the next visit',
      (tester) async {
    final router = await mount(tester, initial: '/previous');
    deferLoad = true;
    data = settings(active: false);
    router.push('/conversation/old');
    await tester.pump();
    await tester.pump();
    expect(find.text('Private conversation'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await pumpMessages(tester);
    await tester.tap(find.text('Private conversation'), warnIfMissed: false);
    expect(screenTaps, 0);
    router.pop();
    await pumpMessages(tester);
    router.push('/conversation/new');
    await tester.pump();
    await tester.pump();
    pendingLoads.removeAt(0)();
    await tester.pump();
    expect(find.text('Private conversation'), findsOneWidget);
    data = settings();
    deferLoad = false;
    for (final resolve in pendingLoads) {
      resolve();
    }
    pendingLoads.clear();
    await pumpMessages(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    expect(find.text('Private conversation'), findsOneWidget);
  });
  testWidgets(
      'same-pattern replacement while locked leaves the new route unlockable',
      (tester) async {
    final router = await mount(tester);
    router.go('/conversation/replacement');
    await pumpMessages(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    expect(find.text('Private conversation'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await pumpMessages(tester);
    expect(find.text('Safe home'), findsOneWidget);
  });
  testWidgets(
      'same-pattern replacement during configuration loading can retry and cancel',
      (tester) async {
    final router = await mount(tester, initial: '/previous');
    deferLoad = true;
    router.go('/conversation/first');
    await tester.pump();
    await tester.pump();
    router.go('/conversation/second');
    await tester.pump();
    await tester.pump();
    deferLoad = false;
    for (final resolve in List.of(pendingLoads)) {
      resolve();
    }
    pendingLoads.clear();
    await pumpMessages(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    expect(find.text('Private conversation'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await pumpMessages(tester);
    expect(find.text('Actual previous page'), findsOneWidget);
  });
}
