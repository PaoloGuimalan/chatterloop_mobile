import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/views/messages/conversation_messages_gate.dart';
import 'package:chatterloop_app/views/messages/messages_gate.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'messages_lock_test.dart' show settings, submit, pumpMessages;

void main() {
  late List<Interceptor> nodeInterceptors, userInterceptors;
  var type = 'single',
      failSetup = false,
      deferSetup = false,
      configurationLoads = 0,
      setupLoads = 0;
  final pendingSetups = <void Function()>[];
  setUp(() {
    type = 'single';
    failSetup = false;
    deferSetup = false;
    pendingSetups.clear();
    configurationLoads = 0;
    setupLoads = 0;
    nodeInterceptors = List.of(ApiClient.instance.dio.interceptors);
    userInterceptors = List.of(ApiClient.userService.dio.interceptors);
    ApiClient.instance.dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (request, handler) {
        expect(request.path, startsWith('/m/conversation/'));
        setupLoads++;
        void resolve() =>
            handler.resolve(Response(requestOptions: request, data: {
              'status': !failSetup,
              'result': {
                'conversationType': type,
                'conversationID': request.path.split('/').last
              }
            }));
        if (deferSetup) {
          pendingSetups.add(resolve);
        } else {
          resolve();
        }
      }));
    ApiClient.userService.dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (request, handler) {
        configurationLoads++;
        expect(request.queryParameters['purpose'], 'messages');
        handler.resolve(Response(
            requestOptions: request,
            data: {'status': true, 'result': settings()}));
      }));
  });
  tearDown(() {
    ApiClient.instance.dio.interceptors
      ..clear(keepImplyContentTypeInterceptor: false)
      ..addAll(nodeInterceptors);
    ApiClient.userService.dio.interceptors
      ..clear(keepImplyContentTypeInterceptor: false)
      ..addAll(userInterceptors);
  });
  Future<GoRouter> mount(WidgetTester tester) async {
    final router = GoRouter(initialLocation: '/conversation/direct', routes: [
      GoRoute(
          path: '/conversation/:id',
          builder: (_, state) => ConversationMessagesGate(
              conversationId: state.pathParameters['id']!,
              builder: (request) => FutureBuilder<Map<String, dynamic>?>(
                  future: request,
                  builder: (_, snapshot) => Text(snapshot.hasData
                      ? 'Visible ${snapshot.data!['conversationType']} ${snapshot.data!['conversationID']}'
                      : 'Normal conversation screen')))),
      GoRoute(
          path: '/messages',
          builder: (_, __) => const MessagesGate(child: Text('Private list'))),
      GoRoute(path: '/newsfeed', builder: (_, __) => const Text('Safe home')),
    ]);
    MessagesGate.observe(router);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    await pumpMessages(tester);
    return router;
  }

  testWidgets(
      'conversation renders its normal screen during setup and beneath the root unlock dialog',
      (tester) async {
    deferSetup = true;
    await mount(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Normal conversation screen'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Conversation'), findsNothing);
    expect(find.textContaining('Visible single'), findsNothing);
    pendingSetups.single();
    await pumpMessages(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Visible single direct'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
  });
  testWidgets(
      'single and group deep links overlay their normal screens with Messages unlock',
      (tester) async {
    final router = await mount(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    expect(find.textContaining('Visible single'), findsOneWidget);
    expect(setupLoads, 1);
    expect(configurationLoads, 1);
    await tester.tap(find.text('Cancel'));
    await pumpMessages(tester);
    type = 'group';
    router.go('/conversation/group');
    await pumpMessages(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    expect(find.textContaining('Visible group'), findsOneWidget);
  });
  testWidgets(
      'server channel, voice and conference bypass the Messages purpose entirely',
      (tester) async {
    type = 'channel';
    final router = await mount(tester);
    expect(find.text('Visible channel direct'), findsOneWidget);
    expect(configurationLoads, 0);
    for (final next in ['server', 'voice', 'conference']) {
      type = next;
      router.go('/conversation/$next');
      await pumpMessages(tester);
      expect(find.text('Visible $next $next'), findsOneWidget);
      expect(configurationLoads, 0);
    }
  });
  testWidgets(
      'unknown and failed conversation classification still require the Messages dialog',
      (tester) async {
    type = 'unknown';
    final router = await mount(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    failSetup = true;
    router.go('/conversation/failed');
    await pumpMessages(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
  });
  testWidgets(
      'entering excluded server conversation ends an unlocked Messages visit',
      (tester) async {
    final router = await mount(tester);
    await submit(tester, 'violet lantern river 你好');
    expect(find.text('Visible single direct'), findsOneWidget);
    type = 'channel';
    router.go('/conversation/channel');
    await pumpMessages(tester);
    expect(find.text('Visible channel channel'), findsOneWidget);
    type = 'single';
    router.go('/messages');
    await pumpMessages(tester);
    expect(find.text('Unlock your Messages'), findsOneWidget);
    expect(find.text('Private list'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
