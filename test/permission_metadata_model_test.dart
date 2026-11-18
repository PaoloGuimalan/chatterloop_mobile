import 'package:flutter_test/flutter_test.dart';
import 'package:chatterloop_app/models/user_models/realm_policy_model.dart';
import 'package:chatterloop_app/models/user_models/role_model.dart';

void main() {
  test('legacy catalog entries with blank descriptions retain visible labels',
      () {
    final entry = RealmPermissionEntry.fromJson({
      'permission': 'realm.post.submit',
      'description': '',
      'grantable': true,
    });
    expect(entry.name, 'realm.post.submit');
    expect(entry.permission, 'realm.post.submit');
  });

  test('canonical code identifies a grant independently of its display name',
      () {
    final entry = RealmPermissionEntry.fromJson({
      'code': 'realm.post.submit',
      'permission': 'legacy.alias',
      'name': 'Submit community posts',
      'description': 'Submit posts for review.',
    });
    expect(entry.name, 'Submit community posts');
    expect(entry.permission, 'realm.post.submit');
  });

  test('blank role permission names fall back to the permission code', () {
    final role = RoleDefinition.fromJson({
      'id': 1,
      'name': 'Writers',
      'permissions': ['realm.post.submit'],
      'permission_details': [
        {'code': 'realm.post.submit', 'name': ''}
      ],
    });
    expect(role.summary, 'realm.post.submit');
  });
}
