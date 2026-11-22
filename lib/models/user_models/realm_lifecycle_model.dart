import 'realm_policy_model.dart';

class RealmLifecycle {
  final String? returnServerId;
  final String id, name, kind;
  final RealmCapabilities capabilities;
  final int childCount, blockerCount;
  final List<String> blockers;
  RealmLifecycle.fromJson(Map<String, dynamic> json)
      : returnServerId = json['return_server_id']?.toString(),
        id = (json['realm_id'] ?? '').toString(),
        name = (json['name'] ?? '').toString(),
        kind = (json['kind'] ?? '').toString(),
        capabilities = RealmCapabilities.fromJson(json['capabilities']),
        childCount = (json['child_count'] as num?)?.toInt() ?? 0,
        blockerCount =
            (json['owned_realm_blocker_count'] as num?)?.toInt() ?? 0,
        blockers = (json['owned_realm_blockers'] as List? ?? [])
            .whereType<Map>()
            .map((r) => (r['name'] ?? '').toString())
            .toList();
}

class RecoveryActor {
  final String id, name;
  final bool isPersonal;
  RecoveryActor.fromJson(Map json)
      : id = (json['entity_id'] ?? '').toString(),
        name = (json['name'] ?? '').toString(),
        isPersonal = json['is_personal'] == true;
}

class RecoveryRealm {
  final String? profile;
  final DateTime? deactivatedAt;
  final String id, name, kind;
  final bool blockedByParent;
  final String? parentRecoveryId;
  final List<RecoveryActor> actors;
  RecoveryRealm.fromJson(Map json)
      : profile = json['profile']?.toString(),
        deactivatedAt =
            DateTime.tryParse((json['deactivated_at'] ?? '').toString()),
        id = (json['realm_id'] ?? '').toString(),
        name = (json['name'] ?? '').toString(),
        kind = (json['kind'] ?? '').toString(),
        blockedByParent = json['blocked_by_parent'] == true,
        parentRecoveryId = json['parent_recovery_realm_id']?.toString(),
        actors = (json['actors'] as List? ?? [])
            .whereType<Map>()
            .map(RecoveryActor.fromJson)
            .toList();
}

class RecoveryPage {
  final List<RecoveryRealm> items;
  final String? nextCursor;
  RecoveryPage.fromJson(Map json)
      : items = (json['items'] as List? ?? [])
            .whereType<Map>()
            .map(RecoveryRealm.fromJson)
            .toList(),
        nextCursor = json['next_cursor']?.toString();
}
