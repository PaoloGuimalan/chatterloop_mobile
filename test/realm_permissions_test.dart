import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/roles_api.dart';
import 'package:chatterloop_app/models/user_models/realm_policy_model.dart';
import 'package:chatterloop_app/views/realm/realm_permissions_view.dart';

class RolesFixture extends RolesApi {
  final saves = <Map<int, List<String>>>[];
  @override
  Future<RealmPermissionSettings> permissions(String id) async =>
      RealmPermissionSettings.fromJson({
        'capabilities': {'can_manage_permissions': true},
        'roles': [
          {
            'id': 1,
            'name': 'Owner',
            'code': 'owner',
            'is_default': true,
            'editable': false,
            'permissions_editable': false,
            'permissions': ['realm.post.submit']
          },
          {
            'id': 2,
            'name': 'Writers',
            'code': 'writers',
            'editable': true,
            'permissions_editable': true,
            'permissions': []
          },
          {
            'id': 3,
            'name': 'Member',
            'code': 'member',
            'editable': true,
            'permissions_editable': true,
            'permissions': ['realm.member.view']
          }
        ],
        'catalog': [
          {
            'code': 'realm.post.submit',
            'permission': 'realm.post.submit',
            'name': 'Submit community posts',
            'description': 'Submit posts for review when required.',
            'grantable': true
          }
        ]
      });
  @override
  Future<void> savePermissions(String id, Map<int, List<String>> roles) async {
    saves.add(roles);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final brightness in Brightness.values) {
    testWidgets(
        'permission descriptions are smaller secondary text in ${brightness.name}',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: buildCLTheme(brightness),
          home: RealmPermissionsView(realmId: 'r', api: RolesFixture())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Writers'));
      await tester.pumpAndSettle();
      final description = find.text('Submit posts for review when required.');
      final text = tester.widget<Text>(description);
      expect(text.style?.fontSize, CLType.bodySm);
      expect(text.style?.color, cl(tester.element(description)).text2);
    });
  }
  testWidgets(
      'Owner is immutable and configurable role changes are saved explicitly',
      (tester) async {
    final api = RolesFixture();
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.dark),
        home: RealmPermissionsView(realmId: 'r', api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Always allowed all permissions'), findsOneWidget);
    await tester.tap(find.text('Writers'));
    await tester.pumpAndSettle();
    expect(find.text('Submit community posts'), findsOneWidget);
    expect(find.text('Submit posts for review when required.'), findsOneWidget);
    expect(find.text('realm.post.submit'), findsNothing);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(api.saves, isEmpty);
    await tester.tap(find.text('Save permissions'));
    await tester.pumpAndSettle();
    expect(api.saves.single[2], ['realm.post.submit']);
    expect(api.saves.single.keys, [2]);
  });
}
