import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/models/user_models/role_model.dart';
import 'package:dio/dio.dart';

class RolesApi {
  final Dio? client;
  RolesApi({this.client});

  Future<List<RoleDefinition>> list() async {
    final response =
        await (client ?? ApiClient.userService.dio).get('/api/entity/roles');
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
