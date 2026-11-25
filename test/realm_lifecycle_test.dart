import 'package:chatterloop_app/core/requests/realm_lifecycle_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/confirm_dialog.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/views/realm/realm_lifecycle_view.dart';
import 'package:chatterloop_app/models/user_models/realm_lifecycle_model.dart';

class LifecycleFixture extends RealmLifecycleApi {
  @override
  Future<RealmLifecycle> get(String id) async => RealmLifecycle.fromJson({
        'realm_id': id,
        'name': 'Example',
        'capabilities': {'can_deactivate_realm': true}
      });
}

class RealtimeMutationFixture extends LifecycleFixture {
  final String? returnServerId;
  RealtimeMutationFixture(this.returnServerId);
  @override
  Future<RealmLifecycle> get(String id) async => RealmLifecycle.fromJson({
        'realm_id': id,
        'name': 'Example',
        'return_server_id': returnServerId,
        'capabilities': {'can_deactivate_realm': true, 'can_delete_realm': true}
      });
  Future<void> changed() async {
    communityChanges.value++;
    // The SSE refresh can finish before the mutation's HTTP response arrives.
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> deactivate(String id) => changed();
  @override
  Future<void> delete(String id, String name) => changed();
}

void main() {
  for (final deleting in [false, true]) {
    for (final stacked in [false, true]) {
      testWidgets(
          'realtime refresh does not suppress successful ${deleting ? 'deletion' : 'deactivation'} navigation (stacked: $stacked)',
          (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        final target = deleting ? '/server/parent' : '/newsfeed';
        final api = RealtimeMutationFixture(deleting ? 'parent' : null);
        final router =
            GoRouter(initialLocation: stacked ? target : '/manage', routes: [
          GoRoute(
              path: '/manage',
              builder: (_, __) => RealmLifecycleView(realmId: 'r', api: api)),
          GoRoute(
              path: target,
              builder: (context, __) => Scaffold(
                      body: Column(children: [
                    const Text('Outside realm'),
                    TextButton(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => RealmLifecycleView(
                                    realmId: 'r', api: api))),
                        child: const Text('Open manager')),
                  ]))),
        ]);
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(
            theme: buildCLTheme(Brightness.light), routerConfig: router));
        await tester.pumpAndSettle();
        if (stacked) {
          await tester.tap(find.text('Open manager'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.widgetWithText(
            CLBtn, deleting ? 'Delete realm' : 'Deactivate realm'));
        await tester.pumpAndSettle();
        if (deleting) {
          await tester.enterText(find.byType(TextField), 'Example');
          await tester.pump();
        }
        await tester.tap(find.widgetWithText(
            TextButton, deleting ? 'Permanently delete' : 'Deactivate'));
        await tester.pumpAndSettle();
        expect(find.text('Outside realm'), findsOneWidget);
        expect(find.byType(RealmLifecycleView), findsNothing);
      });
    }
  }
  testWidgets(
      'refresh while confirmation is open cannot leave controls stuck busy',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: RealmLifecycleView(realmId: 'r', api: LifecycleFixture())));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CLBtn, 'Deactivate realm'));
    await tester.pumpAndSettle();
    communityChanges.value++;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CLBtn>(find.widgetWithText(CLBtn, 'Deactivate realm'))
            .onPressed,
        isNotNull);
  });
  test('lifecycle API keeps exact confirmation and recovery actor', () async {
    final dio = Dio();
    final requests = <RequestOptions>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(Response(requestOptions: request, data: {'result': {}}));
    }));
    final api = RealmLifecycleApi(client: dio, authToken: 'scoped-token');
    await api.delete('realm', 'Exact Name');
    await api.reactivate('realm', 'authorized-page');
    expect(requests[0].data, {'confirm_name': 'Exact Name'});
    expect(requests[1].data, {'actor_entity_id': 'authorized-page'});
    expect(requests[0].extra['authToken'], 'scoped-token');
  });
  testWidgets('typed confirmation disables delete until exact name',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showCLConfirm(context,
                        title: 'Delete realm?',
                        message: 'Permanent',
                        confirmLabel: 'Delete',
                        confirmationName: 'Example'),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Delete'))
            .onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), 'Example');
    await tester.pump();
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Delete'))
            .onPressed,
        isNotNull);
  });
}
