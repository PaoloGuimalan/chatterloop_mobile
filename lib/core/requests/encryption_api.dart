import 'package:dio/dio.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/encryption/passphrase_crypto.dart';

class EncryptionApi {
  EncryptionApi({Dio? dio}) : _dio = dio ?? ApiClient.userService.dio;
  final Dio _dio;
  static const path = '/api/entity/encryption-configurations/personal/';
  Future<Map<String, dynamic>> load() async {
    final data = _result((await _dio.get(path)).data);
    PassphraseCrypto.validateProfile(
        Map<String, dynamic>.from(data['supported_profile'] as Map));
    final owner = data['owner'];
    if (owner is! Map ||
        owner['entity_id'] is! String ||
        owner['user_id'] is! String ||
        data['purposes'] is! List) {
      throw const FormatException('Could not load passphrases');
    }
    for (final group in data['purposes'] as List) {
      if (group is! Map ||
          group['configurations'] is! List ||
          group['scope_version'] is! String) {
        throw const FormatException('Invalid passphrase response');
      }
      for (final c in group['configurations'] as List) {
        PassphraseCrypto.validateConfiguration(
            Map<String, dynamic>.from(c as Map));
        if (c['entity_id'] != owner['entity_id'] ||
            c['user_id'] != owner['user_id']) {
          throw const FormatException('Invalid passphrase owner');
        }
      }
      final active = (group['configurations'] as List)
          .where((c) => c['is_active'] == true)
          .toList();
      if (active.length > 1 ||
          (active.isEmpty ? null : active.single['id']) !=
              group['active_configuration_id']) {
        throw const FormatException('Inconsistent active passphrase');
      }
    }
    if (!(data['purposes'] as List).any((g) => g['purpose'] == 'diary')) {
      throw const FormatException('Diary protection unavailable');
    }
    return data;
  }

  Map<String, dynamic> _result(dynamic data) {
    if (data is! Map || data['status'] != true || data['result'] is! Map) {
      throw const FormatException('Could not load passphrases');
    }
    return Map<String, dynamic>.from(data['result'] as Map);
  }

  Future<void> create(Map<String, dynamic> data) async =>
      _result((await _dio.post(path, data: data)).data);
  Future<void> rename(String id, String name, String version) async =>
      _result((await _dio.patch('$path$id/',
              data: {'name': name.trim(), 'expected_scope_version': version}))
          .data);
  Future<void> activate(
          String id, String version, String target, String? active) async =>
      _result((await _dio.post('$path$id/activate/', data: {
        'expected_scope_version': version,
        'target_verification_proof': target,
        if (active != null) 'active_verification_proof': active
      }))
          .data);
  Future<void> disable(String id, String version, String proof) async =>
      _result((await _dio.post('$path$id/deactivate/', data: {
        'expected_scope_version': version,
        'active_verification_proof': proof
      }))
          .data);
}
