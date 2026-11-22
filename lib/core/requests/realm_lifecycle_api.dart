import 'package:dio/dio.dart';
import 'api_client.dart';
import 'package:chatterloop_app/models/user_models/realm_lifecycle_model.dart';

class RealmLifecycleApi {
  final Dio? client;
  final String? authToken;
  RealmLifecycleApi({this.client, this.authToken});
  Dio get _dio => client ?? ApiClient.userService.dio;
  Options? get _options =>
      authToken == null ? null : Options(extra: {'authToken': authToken});
  String _url(String id, String action) =>
      '/api/realm/realms/${Uri.encodeComponent(id)}/$action';
  Future<RealmLifecycle> get(String id) async {
    final response = await _dio.get(_url(id, 'lifecycle'), options: _options);
    return RealmLifecycle.fromJson(
        Map<String, dynamic>.from(response.data['result']));
  }

  Future<void> deactivate(String id) async {
    await _dio.post(_url(id, 'deactivate'), data: {}, options: _options);
  }

  Future<void> delete(String id, String name) async {
    await _dio.post(_url(id, 'delete'),
        data: {'confirm_name': name}, options: _options);
  }

  Future<void> reactivate(String id, String actorId) async {
    await _dio.post(_url(id, 'reactivate'),
        data: {'actor_entity_id': actorId}, options: _options);
  }

  Future<RecoveryPage> deactivated({String? cursor}) async {
    final response = await _dio.get('/api/realm/realms/deactivated',
        queryParameters: {if (cursor != null) 'cursor': cursor},
        options: _options);
    return RecoveryPage.fromJson(
        Map<String, dynamic>.from(response.data['result']));
  }
}
