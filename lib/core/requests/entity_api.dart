// Entity switching (Django user_service) - list realms/pages this account
// administers, and switch the active acting entity. Mirrors webapp's
// EntitySwitcher.tsx / requests.ts (GetMyRealmsRequest/SwitchEntityRequest/
// SwitchBackToSelfRequest).

import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/auth_api.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:flutter/foundation.dart';

class EntityApi {
  final _dio = ApiClient.userService.dio;
  final _endpoints = Endpoints();

  /// Not wrapped in {status, result} - plain DRF paginated response, same
  /// as SearchApi.searchUsersRequest.
  Future<List<RealmSummary>> getMyRealmsRequest() async {
    try {
      final response = await _dio.get(_endpoints.myRealms, queryParameters: {
        "page": 1,
        "page_size": 20,
        "type": "page",
      });
      final results = response.data["results"];
      if (results is! List) return const [];
      return results
          .whereType<Map>()
          .map((item) => RealmSummary.fromJson(Map<String, dynamic>.from(item)))
          .where((realm) => realm.isAdmin)
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return const [];
    }
  }

  Future<bool> switchEntityRequest(String realmId) async {
    return _switchAndRefresh(
        () => _dio.post(_endpoints.entitySwitch, data: {"realm_id": realmId}));
  }

  Future<bool> switchBackRequest() async {
    return _switchAndRefresh(
        () => _dio.post(_endpoints.entitySwitchBack, data: {}));
  }

  /// Both switch endpoints re-issue the authtoken with a different `entity`
  /// claim in the JWT (same account, different acting identity) rather than
  /// requiring a fresh login. webapp settles this with a full page reload,
  /// since a switch changes almost everything downstream (post authorship,
  /// module gating, permission checks, contact/conversation scoping). This
  /// mirrors that intent without an actual app restart: store the new
  /// token, re-run the same session-restore flow AuthController.resolve()
  /// does at startup so allowed_modules/active_entity/personal_entity_id
  /// all come back fresh from the Node jwtchecker, then dispatch via
  /// resetAppStateT (not setUserAuthT) - a wholesale AppState replace, not
  /// a merge - so messages/contacts/notifications/presence/typing/reply-
  /// assist state all actually clear instead of briefly showing the
  /// previous entity's stale data. HomeTabScaffold separately detects the
  /// entityId change and re-fetches each of those lists fresh.
  Future<bool> _switchAndRefresh(Future<dynamic> Function() request) async {
    try {
      final response = await request();
      if (response.data["status"] == false) return false;
      final authtoken = response.data["result"]?["authtoken"]?.toString();
      if (authtoken == null || authtoken.isEmpty) return false;
      await ApiClient.instance.writeToken(authtoken);

      final refreshed = await AuthApi().jwtCheckerRequest();
      if (refreshed == null) return false;
      final payload = JwtCodec.decode(refreshed.usertoken);
      final account = UserAccount.fromNodeJwt(payload ?? const {},
          allowedModules: refreshed.allowedModules,
          activeEntity: refreshed.activeEntity,
          personalEntityId: refreshed.personalEntityId);
      appStore.dispatch(DispatchModel(resetAppStateT, UserAuth(true, account)));
      return true;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }
}
