import 'package:chatterloop_app/core/requests/invites_api.dart';
import 'package:chatterloop_app/core/requests/roles_api.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'package:chatterloop_app/models/user_models/realm_invite_model.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/models/user_models/role_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rows = [
    {
      'id': 10,
      'name': 'moderator',
      'is_default': true,
      'permissions': ['posts.review']
    },
    {
      'id': 11,
      'name': 'moderator',
      'is_default': false,
      'permissions': ['posts.delete']
    },
  ];

  test('duplicate names retain exact IDs and explicit default selection',
      () async {
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      expect(request.path, '/api/entity/roles');
      handler.resolve(Response(
          requestOptions: request, data: {'status': true, 'result': rows}));
    }));
    final roles = await RolesApi(client: client).list();
    expect(roles.map((role) => role.id), [10, 11]);
    expect(RoleDefinition.defaultFor(roles, 'moderator')?.id, 10);
    expect(RoleDefinition.defaultFor([roles[1]], 'moderator'), isNull);
    expect(roles[1].label, contains('#11'));
    expect(roles[1].summary, 'posts.delete');
  });

  test(
      'manage invitation writes the chosen role ID and keeps it after answering',
      () async {
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      expect(request.data['role_id'], 11);
      expect(request.data.containsKey('role'), isFalse);
      handler.resolve(Response(requestOptions: request, data: {
        'status': true,
        'result': {'id': 'invite', 'role': 'moderator', 'role_id': 11},
      }));
    }));
    final result = await InvitesApi(client: client).create(
        realmId: 'page',
        target: 'person@example.com',
        purpose: 'manage',
        roleId: 11);
    expect(result?.invite.role, 'moderator');
    expect(result?.invite.roleId, 11);
    expect(result?.invite.withStatus('accepted').roleId, 11);
  });

  test(
      'membership models retain names for hierarchy and numeric role identities',
      () {
    final person = RealmPerson.fromMemberJson({
      'member_id': 'm',
      'role': 'admin',
      'role_id': 12,
      'entity': {'id': 'e'}
    });
    expect(person.role, 'admin');
    expect(person.roleId, 12);
    final realm = RealmProfile.fromJson({'my_role': 'owner', 'my_role_id': 20});
    expect(realm.myRole, 'owner');
    expect(realm.myRoleId, 20);
    final community =
        Community.fromJson({'my_role': 'admin', 'my_role_id': 12});
    expect(community.withMembership(member: true, pending: false).myRoleId, 12);
    expect(community.withMembership(member: false, pending: false).myRoleId,
        isNull);
    expect(RealmInvite.fromJson({'role_id': null}).roleId, isNull);
  });
}
