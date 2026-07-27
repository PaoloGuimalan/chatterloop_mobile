// Network v2 shapes - the redesigned Contacts screen's data. Mirror
// webapp's NetworkEntityResult / NetworkOverview / GroupShortcut, which in
// turn mirror user_service's entity/network_views.normalize_network_entity()
// and the Node /m/v2/group-shortcuts route.

/// One row shape for BOTH kinds of counterpart (a person and a page render
/// identically), plus the per-section extras that only their own section
/// populates.
class NetworkEntityResult {
  final String entityId;

  /// "user" or "realm" - a realm row gets the small flag marker and never
  /// shows presence (a page is never "active now").
  final String type;
  final String displayName;
  final String handle;
  final String? profile;
  final bool isVerified;

  /// Account pk for users, Realm pk for realms.
  final String id;

  /// Realms only.
  final String? realmType;

  // --- connections only ---
  /// What the message button routes to: `/conversation/<connection_id>`.
  final String? connectionId;
  final int? mutualCount;

  // --- followers only: drives Follow back / Following ---
  final bool? isFollowedBack;

  // --- following only: always true, so the button is always Unfollow ---
  final bool? isFollowed;

  const NetworkEntityResult({
    required this.entityId,
    required this.type,
    required this.displayName,
    required this.handle,
    this.profile,
    required this.isVerified,
    required this.id,
    this.realmType,
    this.connectionId,
    this.mutualCount,
    this.isFollowedBack,
    this.isFollowed,
  });

  bool get isRealm => type == "realm";

  /// Either flag answers "am I following them right now" - follower rows
  /// track is_followed_back, following rows are followed by definition.
  bool get followsRightNow => isFollowedBack == true || isFollowed == true;

  /// Both flags are patched together so an optimistic toggle stays coherent
  /// regardless of which section the row came from.
  NetworkEntityResult copyWithFollow(bool next) => NetworkEntityResult(
        entityId: entityId,
        type: type,
        displayName: displayName,
        handle: handle,
        profile: profile,
        isVerified: isVerified,
        id: id,
        realmType: realmType,
        connectionId: connectionId,
        mutualCount: mutualCount,
        isFollowedBack: next,
        isFollowed: next,
      );

  factory NetworkEntityResult.fromJson(Map<String, dynamic> json) {
    return NetworkEntityResult(
      entityId: (json["entity_id"] ?? "").toString(),
      type: (json["type"] ?? "user").toString(),
      displayName: (json["display_name"] ?? "").toString(),
      handle: (json["handle"] ?? "").toString(),
      profile: json["profile"]?.toString(),
      isVerified: json["is_verified"] == true,
      id: (json["id"] ?? "").toString(),
      realmType: json["realm_type"]?.toString(),
      connectionId: json["connection_id"]?.toString(),
      mutualCount: json["mutual_count"] is num
          ? (json["mutual_count"] as num).toInt()
          : null,
      isFollowedBack:
          json.containsKey("is_followed_back") ? json["is_followed_back"] == true : null,
      isFollowed:
          json.containsKey("is_followed") ? json["is_followed"] == true : null,
    );
  }
}

/// A section preview from the overview call. Unlike the search overview this
/// one DOES carry a total - the jump chips and "See all N" labels show it.
class NetworkOverviewSection {
  final bool hasMore;
  final int total;
  final List<NetworkEntityResult> results;

  const NetworkOverviewSection({
    required this.hasMore,
    required this.total,
    required this.results,
  });

  static const empty =
      NetworkOverviewSection(hasMore: false, total: 0, results: []);

  factory NetworkOverviewSection.fromJson(dynamic data) {
    if (data is! Map) return empty;
    final raw = data["results"];
    return NetworkOverviewSection(
      hasMore: data["has_more"] == true,
      total: data["total"] is num ? (data["total"] as num).toInt() : 0,
      results: raw is List
          ? raw
              .whereType<Map>()
              .map((item) =>
                  NetworkEntityResult.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
    );
  }
}

class NetworkOverview {
  final NetworkOverviewSection connections;
  final NetworkOverviewSection followers;
  final NetworkOverviewSection following;

  const NetworkOverview({
    required this.connections,
    required this.followers,
    required this.following,
  });

  factory NetworkOverview.fromJson(Map<String, dynamic> json) {
    return NetworkOverview(
      connections: NetworkOverviewSection.fromJson(json["connections"]),
      followers: NetworkOverviewSection.fromJson(json["followers"]),
      following: NetworkOverviewSection.fromJson(json["following"]),
    );
  }

  /// Patches a follow flip into all three previews at once - the same entity
  /// can appear in more than one section.
  NetworkOverview patchFollow(String entityId, bool next) {
    NetworkOverviewSection patch(NetworkOverviewSection section) =>
        NetworkOverviewSection(
          hasMore: section.hasMore,
          total: section.total,
          results: section.results
              .map((item) =>
                  item.entityId == entityId ? item.copyWithFollow(next) : item)
              .toList(),
        );
    return NetworkOverview(
      connections: patch(connections),
      followers: patch(followers),
      following: patch(following),
    );
  }
}

/// A group chat shortcut from GET /m/v2/group-shortcuts (Node/Mongo) - a
/// conversation the entity is actually in, NOT a realm directory entry.
class GroupShortcut {
  /// Opens `/conversation/<target_id>`. A group's conversationID IS its
  /// realm_id, so this is the same value as [realmId].
  final String targetId;
  final String realmId;
  final String id;
  final String displayName;
  final String handle;
  final String? profile;
  final bool isVerified;
  final DateTime? lastActivity;

  const GroupShortcut({
    required this.targetId,
    required this.realmId,
    required this.id,
    required this.displayName,
    required this.handle,
    this.profile,
    required this.isVerified,
    this.lastActivity,
  });

  factory GroupShortcut.fromJson(Map<String, dynamic> json) {
    return GroupShortcut(
      targetId: (json["target_id"] ?? "").toString(),
      realmId: (json["realm_id"] ?? "").toString(),
      id: (json["id"] ?? "").toString(),
      displayName: (json["display_name"] ?? "").toString(),
      handle: (json["handle"] ?? "").toString(),
      profile: json["profile"]?.toString(),
      isVerified: json["is_verified"] == true,
      lastActivity: DateTime.tryParse((json["last_activity"] ?? "").toString()),
    );
  }
}

/// One page of group shortcuts. Node's own envelope ({items, total, next}),
/// not DRF's - hence its own type rather than PagedResult.
class GroupShortcutsPage {
  final List<GroupShortcut> items;
  final int total;
  final bool hasNext;

  const GroupShortcutsPage({
    required this.items,
    required this.total,
    required this.hasNext,
  });

  static const empty = GroupShortcutsPage(items: [], total: 0, hasNext: false);

  factory GroupShortcutsPage.fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    final raw = json["items"];
    return GroupShortcutsPage(
      items: raw is List
          ? raw
              .whereType<Map>()
              .map((item) =>
                  GroupShortcut.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
      total: json["total"] is num ? (json["total"] as num).toInt() : 0,
      hasNext: json["next"] == true,
    );
  }
}
