// Realm invites (Django user_service, community/invites.py) - by email or by
// username, into a group, a server, a conference or a page. The person is
// not added: they get an invite they accept or decline.
//
// Same endpoint and payloads as the webapp's Create/Get/UpdateRealmInvite
// requests.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/reported_action.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/user_models/realm_invite_model.dart';
import 'package:flutter/foundation.dart';

class InvitesApi {
  final _dio = ApiClient.userService.dio;
  final _endpoints = Endpoints();

  static RealmInvite? _inviteFrom(Object? body) {
    if (body is! Map || body['result'] is! Map) return null;
    return RealmInvite.fromJson(Map<String, dynamic>.from(body['result']));
  }

  /// One invite by its token - what the invite screen opens. Null when it
  /// cannot be read; the screen says so rather than repeating why.
  Future<RealmInvite?> getByToken(String token) async {
    try {
      final response = await _dio.get(
        _endpoints.realmInvites,
        queryParameters: {'invite_token': token},
      );
      return _inviteFrom(response.data);
    } catch (e) {
      if (kDebugMode) print('getByToken failed: $e');
      return null;
    }
  }

  /// A realm's invites still waiting for an answer. Empty when there are
  /// none - or when this account may not see them, which is not an error
  /// worth showing.
  Future<List<RealmInvite>> pending(String realmId) async {
    try {
      final response = await _dio.get(
        _endpoints.realmInvites,
        queryParameters: {
          'realm_id': realmId,
          'kind': 'invite',
          'status': 'pending',
        },
      );
      final result = response.data is Map ? response.data['result'] : null;
      if (result is! List) return const [];
      return result
          .whereType<Map>()
          .map((item) => RealmInvite.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (e) {
      if (kDebugMode) print('pending invites failed: $e');
      return const [];
    }
  }

  /// Invites [target] (an email or a username, as typed) or the entity
  /// [targetEntityId] (someone picked from search). Null on failure, with the
  /// server's reason already shown - "No one goes by @x", "They're already a
  /// member".
  ///
  /// `alreadyInvited` is true when an invite was already waiting for them: the
  /// server hands that one back rather than sending another.
  Future<({RealmInvite invite, bool alreadyInvited})?> create({
    required String realmId,
    String? target,
    String? targetEntityId,
    String? purpose,
    String? role,
  }) {
    return reportedRequest(
      () => _dio.post(_endpoints.realmInvites, data: {
        'realm_id': realmId,
        'kind': 'invite',
        if (target != null) 'target': target,
        if (targetEntityId != null) 'target_entity_id': targetEntityId,
        if (purpose != null) 'purpose': purpose,
        if (role != null) 'role': role,
      }),
      failure: "We couldn't send that invite.",
      parse: (response) {
        final invite = _inviteFrom(response.data);
        if (invite == null) return null;
        return (
          invite: invite,
          alreadyInvited:
              response.data is Map && response.data['already_invited'] == true,
        );
      },
    );
  }

  /// Answers an invite (accepted / declined) or withdraws one (revoked).
  /// The settled invite, or null with the reason already shown.
  Future<RealmInvite?> answer(String token, String status) {
    return reportedRequest(
      () => _dio.patch(_endpoints.realmInvites, data: {
        'invite_token': token,
        'status': status,
      }),
      failure: status == 'revoked'
          ? "We couldn't withdraw that invite."
          : "We couldn't answer that invite.",
      parse: (response) => _inviteFrom(response.data),
    );
  }
}
