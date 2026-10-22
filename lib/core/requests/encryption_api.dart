import 'package:dio/dio.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/encryption/passphrase_crypto.dart';

class EncryptionApi {
  EncryptionApi({Dio? dio}) : _dio = dio ?? ApiClient.userService.dio;
  final Dio _dio;
  static const path = '/api/entity/encryption-configurations/personal/';
  Future<Map<String, dynamic>> load({String? purpose}) async {
    if (purpose != null && !PassphraseCrypto.validPurpose(purpose)) {
      throw const FormatException('Invalid passphrase purpose');
    }
    final data = _result((await _dio.get(path,
            queryParameters: purpose == null ? null : {'purpose': purpose}))
        .data);
    PassphraseCrypto.validateProfile(
        Map<String, dynamic>.from(data['supported_profile'] as Map));
    final owner = data['owner'];
    if (owner is! Map ||
        owner['entity_id'] is! String ||
        owner['user_id'] is! String ||
        data['purposes'] is! List) {
      throw const FormatException('Could not load passphrases');
    }
    final groupPurposes = <String>{};
    final activeIds = <String>{};
    for (final group in data['purposes'] as List) {
      if (group is! Map ||
          !PassphraseCrypto.validPurpose(group['purpose']) ||
          !groupPurposes.add(group['purpose'] as String) ||
          (group.containsKey('is_active') && group['is_active'] is! bool) ||
          group['configurations'] is! List ||
          group['scope_version'] is! String) {
        throw const FormatException('Invalid passphrase response');
      }
      for (final c in group['configurations'] as List) {
        PassphraseCrypto.validateConfiguration(
            Map<String, dynamic>.from(c as Map));
        if (!PassphraseCrypto.configurationPurposes(
                Map<String, dynamic>.from(c))
            .contains(group['purpose'])) {
          throw const FormatException('Invalid passphrase use');
        }
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
      if (active.isNotEmpty) activeIds.add(active.single['id'] as String);
    }
    if (activeIds.length > 1) {
      throw const FormatException('Inconsistent active passphrase');
    }
    if (data.containsKey('configurations') ||
        data.containsKey('scope_version')) {
      if (purpose != null ||
          data['configurations'] is! List ||
          data['scope_version'] is! String) {
        throw const FormatException('Invalid passphrase settings');
      }
      final ids = <String>{};
      var activeCount = 0;
      for (final value in data['configurations'] as List) {
        final c = Map<String, dynamic>.from(value as Map);
        PassphraseCrypto.validateConfiguration(c);
        if (!ids.add(c['id'] as String) ||
            c['entity_id'] != owner['entity_id'] ||
            c['user_id'] != owner['user_id'] ||
            PassphraseCrypto.configurationPurposes(c)
                .any((code) => !groupPurposes.contains(code))) {
          throw const FormatException('Invalid passphrase owner or uses');
        }
        if (c['is_active'] == true) activeCount++;
      }
      if (activeCount > 1 || !ids.containsAll(activeIds)) {
        throw const FormatException('Inconsistent active passphrase');
      }
    }
    if (purpose != null &&
        (groupPurposes.length != 1 || !groupPurposes.contains(purpose))) {
      throw const FormatException('Invalid passphrase purpose response');
    }
    return data;
  }

  /// Historical reads are explicitly bound to the current visit's owner.
  Future<Map<String, dynamic>> loadConfiguration(String id,
      {required String purpose, required Map owner}) async {
    if (!PassphraseCrypto.validPurpose(purpose)) {
      throw const FormatException('Invalid passphrase purpose');
    }
    final result = _result(
        (await _dio.get('$path$id/', queryParameters: {'purpose': purpose}))
            .data);
    final c = Map<String, dynamic>.from(result['configuration'] as Map);
    PassphraseCrypto.validateConfiguration(c);
    if (c['id'] != id ||
        c['entity_id'] != owner['entity_id'] ||
        c['user_id'] != owner['user_id']) {
      throw const FormatException('Invalid historical passphrase owner');
    }
    return c;
  }

  Map<String, dynamic> _result(dynamic data) {
    if (data is! Map || data['status'] != true || data['result'] is! Map) {
      throw const FormatException('Could not load passphrases');
    }
    return Map<String, dynamic>.from(data['result'] as Map);
  }

  Future<void> create(Map<String, dynamic> data) async =>
      _result((await _dio.post(path, data: data)).data);
  Future<void> updateUses(String id, List<String> purposes, String version,
          String proof) async =>
      _result((await _dio.post('$path$id/uses/', data: {
        'purposes': purposes,
        'expected_scope_version': version,
        'target_verification_proof': proof
      }))
          .data);
  Future<void> rename(String id, String name, String version,
          {String? purpose}) async =>
      _result((await _dio.patch('$path$id/', data: {
        'name': name.trim(),
        'expected_scope_version': version,
        if (purpose != null) 'purpose': purpose
      }))
          .data);
  Future<void> activate(
          String id, String version, String target, String? active,
          {String? purpose}) async =>
      _result((await _dio.post('$path$id/activate/', data: {
        'expected_scope_version': version,
        'target_verification_proof': target,
        if (purpose != null) 'purpose': purpose,
        if (active != null) 'active_verification_proof': active
      }))
          .data);
  Future<void> disable(String id, String version, String proof,
          {String? purpose}) async =>
      _result((await _dio.post('$path$id/deactivate/', data: {
        'expected_scope_version': version,
        if (purpose != null) 'purpose': purpose,
        'active_verification_proof': proof
      }))
          .data);
}
