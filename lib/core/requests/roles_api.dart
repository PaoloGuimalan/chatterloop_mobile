import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/models/user_models/role_model.dart';
import 'package:dio/dio.dart';
import 'package:chatterloop_app/models/user_models/realm_approval_model.dart';

class RolesApi {
  final Dio? client;
  final String? authToken;
  RolesApi({this.client, this.authToken});
  Options? get _options =>
      authToken == null ? null : Options(extra: {'authToken': authToken});

  Future<RealmPermissionSettings> permissions(String realmId) async {
    final response = await (client ?? ApiClient.userService.dio).get(
        '/api/realm/realms/${Uri.encodeComponent(realmId)}/permissions',
        options: _options);
    return RealmPermissionSettings.fromJson(
        Map<String, dynamic>.from(response.data['result']));
  }

  Future<void> savePermissions(
      String realmId, Map<int, List<String>> roles) async {
    await (client ?? ApiClient.userService.dio).put(
        '/api/realm/realms/${Uri.encodeComponent(realmId)}/permissions',
        options: _options,
        data: {
          'roles': roles.entries
              .map((row) => {'role_id': row.key, 'permissions': row.value})
              .toList()
        });
  }

  Future<RoleDefinition> create(String realmId, String name,
      {List<String>? permissions}) async {
    final response = await (client ?? ApiClient.userService.dio)
        .post('/api/entity/roles', options: _options, data: {
      'realm_id': realmId,
      'name': name,
      if (permissions != null) 'permissions': permissions
    });
    return RoleDefinition.fromJson(
        Map<String, dynamic>.from(response.data['result']));
  }

  Future<void> update(String realmId, int roleId,
      {String? name, List<String>? permissions}) async {
    await (client ?? ApiClient.userService.dio)
        .put('/api/entity/roles/$roleId', options: _options, data: {
      'realm_id': realmId,
      if (name != null) 'name': name,
      if (permissions != null) 'permissions': permissions
    });
  }

  Future<void> delete(String realmId, int roleId) async {
    await (client ?? ApiClient.userService.dio).delete(
        '/api/entity/roles/$roleId',
        options: _options,
        queryParameters: {'realm_id': realmId});
  }

  Future<List<RoleDefinition>> list({String? realmId}) async {
    final response = await (client ?? ApiClient.userService.dio).get(
        '/api/entity/roles',
        options: _options,
        queryParameters: realmId == null ? null : {'realm_id': realmId});
    final body = response.data;
    if (body is! Map || body['status'] != true || body['result'] is! List) {
      throw StateError('Could not load roles.');
    }
    return (body['result'] as List)
        .whereType<Map>()
        .map((row) => RoleDefinition.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }
}
