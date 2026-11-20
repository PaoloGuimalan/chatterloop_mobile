import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/models/user_models/role_model.dart';
import 'package:chatterloop_app/views/realm/realm_role_assignment_dialog.dart';
import 'package:chatterloop_app/views/realm/realm_sections.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final members in [true, false]) {
    testWidgets(
        members
            ? 'server removal-only manager cannot assign roles'
            : 'page follower removal uses its own grant', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final userDio = ApiClient.userService.dio;
      final mainDio = ApiClient.instance.dio;
      final person = {
        'id': 'other-person',
        'type': 'user',
        'details': {
          'id': 'other-account',
          'first_name': 'Maya',
          'username': 'maya'
        }
      };
      final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'count': 1,
          'next': null,
          'results': [
            {
              'member_id': 'membership',
              'follow_id': 'follow',
              'realm': 'realm',
              'role': 'member',
              'role_id': 3,
              'entity': person,
              'follower': person
            }
          ]
        }));
      });
      userDio.interceptors.insert(0, interceptor);
      mainDio.interceptors.insert(0, interceptor);
      addTearDown(() {
        userDio.interceptors.remove(interceptor);
        mainDio.interceptors.remove(interceptor);
      });
      await tester.pumpWidget(MaterialApp(
          theme: buildCLTheme(Brightness.light),
          home: RealmRosterScreen(
              members: members,
              realm: RealmProfile.fromJson({
                'id': 'realm',
                'name': 'Realm',
                'type': members ? 'server' : 'page',
                'my_role': 'member',
                'capabilities': {
                  'can_view_members': true,
                  'can_remove_members': members,
                  'can_assign_roles': false,
                  'can_remove_followers': !members
                }
              }))));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Options'));
      await tester.pumpAndSettle();
      expect(find.text('Assign different role'), findsNothing);
      expect(find.text('Remove'), findsOneWidget);
    });
  }
  for (final width in [320.0, 390.0]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets(
          'role dialog fits $width pixels in $brightness with large text',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 650));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(
            theme: buildCLTheme(brightness),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!),
            home: Scaffold(
                body: RealmRoleAssignmentDialog(
                    currentRoleId: 2,
                    memberName: 'Maya Chen',
                    roles: const [
                  RoleDefinition(id: 2, name: 'Member'),
                  RoleDefinition(
                      id: 3,
                      name: 'Community editorial review and moderation team')
                ]))));
        await tester.pumpAndSettle();
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Save role'), findsOneWidget);
        await tester.tap(find.byType(DropdownButtonFormField<int>));
        await tester.pumpAndSettle();
        await tester.tap(
            find.text('Community editorial review and moderation team').last);
        await tester.pumpAndSettle();
        expect(
            tester
                .widget<TextButton>(
                    find.widgetWithText(TextButton, 'Save role'))
                .onPressed,
            isNotNull);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'assigning a member role requires Save and Cancel leaves membership unchanged',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    var roleId = 2;
    final updates = <dynamic>[];
    final userDio = ApiClient.userService.dio;
    final mainDio = ApiClient.instance.dio;
    final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      final dynamic data;
      if (request.path.endsWith('/roles')) {
        data = {
          'status': true,
          'result': [
            {
              'id': 1,
              'name': 'Owner',
              'assignable': false,
              'permissions': ['realm.roles.manage']
            },
            {
              'id': 2,
              'name': 'Member',
              'assignable': true,
              'permissions': ['realm.post.submit']
            },
            {
              'id': 3,
              'name': 'Review team',
              'assignable': true,
              'permissions': ['realm.post.review']
            },
          ]
        };
      } else if (request.method == 'PUT') {
        updates.add(request.data);
        roleId = request.data['new_role_id'] as int;
        data = {'status': true};
      } else {
        data = {
          'count': 1,
          'next': null,
          'results': [
            {
              'member_id': 'membership',
              'realm': 'club',
              'role': 'member',
              'role_id': roleId,
              'entity': {
                'id': 'other-person',
                'type': 'user',
                'details': {
                  'id': 'other-account',
                  'first_name': 'Maya',
                  'username': 'maya'
                }
              }
            }
          ]
        };
      }
      handler.resolve(
          Response(requestOptions: request, statusCode: 200, data: data));
    });
    userDio.interceptors.insert(0, interceptor);
    mainDio.interceptors.insert(0, interceptor);
    addTearDown(() {
      userDio.interceptors.remove(interceptor);
      mainDio.interceptors.remove(interceptor);
    });
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.dark),
        home: RealmRosterScreen(
            realm: RealmProfile.fromJson({
              'id': 'club',
              'name': 'Club',
              'type': 'community',
              'my_role': 'owner',
              'capabilities': {
                'can_view_members': true,
                'can_assign_roles': true
              }
            }),
            members: true)));
    await tester.pumpAndSettle();
    Future<void> open() async {
      await tester.tap(find.byTooltip('Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assign different role'));
      await tester.pumpAndSettle();
    }

    await open();
    expect(find.text('realm.post.submit'), findsNothing);
    expect(find.text('Save role'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(updates, isEmpty);
    await open();
    final save = find.widgetWithText(TextButton, 'Save role');
    expect(tester.widget<TextButton>(save).onPressed, isNull);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review team').last);
    await tester.pumpAndSettle();
    expect(updates, isEmpty);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(updates, [
      {'realm_id': 'club', 'member_id': 'membership', 'new_role_id': 3}
    ]);
    expect(find.text('Save role'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
