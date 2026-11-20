import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/views/realm/realm_manage_view.dart';
import 'package:chatterloop_app/views/communities/community_requests_view.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:chatterloop_app/views/profile/realm_profile_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(CLAlerts.clear);
  for (final kind in [
    'community',
    'page',
    'server',
    'group',
    'channel',
    'voice',
    'conference'
  ]) {
    testWidgets('$kind exposes Permissions to a capable custom manager',
        (tester) async {
      final dio = ApiClient.userService.dio;
      final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'data': {
            'id': 'realm',
            'name': 'Realm',
            'type': kind,
            'is_admin': false,
            'capabilities': {'can_manage': true, 'can_manage_roles': true}
          }
        }));
      });
      dio.interceptors.insert(0, interceptor);
      addTearDown(() => dio.interceptors.remove(interceptor));
      await tester.pumpWidget(MaterialApp(
          theme: buildCLTheme(Brightness.light),
          home: const RealmManageScreen(slug: 'realm')));
      await tester.pumpAndSettle();
      expect(find.text('Permissions'), findsOneWidget);
      if (kind != 'community') {
        expect(find.text('Approvals'), findsNothing);
        expect(find.text('Archived'), findsNothing);
        expect(find.text('Notifications'), findsNothing);
      }
    });
  }

  testWidgets(
      'failed review queue shows Retry rather than claiming no pending work',
      (tester) async {
    final dio = ApiClient.userService.dio;
    final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      handler.reject(DioException(
          requestOptions: request,
          type: DioExceptionType.badResponse,
          response: Response(
              requestOptions: request,
              statusCode: 403,
              data: {'message': 'Access was revoked.'})));
    });
    dio.interceptors.insert(0, interceptor);
    addTearDown(() => dio.interceptors.remove(interceptor));
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const CommunityRequestsView(realmId: 'server')));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('You’re all caught up'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a personal page role manager can reach Manage without acting as the page',
      (tester) async {
    final userDio = ApiClient.userService.dio;
    final mainDio = ApiClient.instance.dio;
    final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: request.path.contains('/auth/')
              ? {
                  'data': {
                    'id': 'page',
                    'entity': 'page-entity',
                    'name': 'Page',
                    'type': 'page',
                    'slug': 'page',
                    'is_admin': false,
                    'capabilities': {
                      'can_manage': true,
                      'can_manage_roles': true
                    }
                  }
                }
              : {'count': 0, 'next': null, 'results': []}));
    });
    userDio.interceptors.insert(0, interceptor);
    mainDio.interceptors.insert(0, interceptor);
    addTearDown(() {
      userDio.interceptors.remove(interceptor);
      mainDio.interceptors.remove(interceptor);
    });
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const RealmProfileScreen(slug: 'page')));
    await tester.pumpAndSettle();
    expect(find.text('Manage realm'), findsOneWidget);
    expect(find.text("You're posting as this page"), findsNothing);
  });
}
