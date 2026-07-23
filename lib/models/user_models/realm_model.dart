/// Item from GET /api/realm/my-list (Django, RealmSerializer - fields =
/// "__all__" plus annotated is_admin/is_member/is_follower/followers_count/
/// members). Not wrapped in {status, result} - plain DRF paginated response
/// {count, next, previous, results}, same as SearchResultUser. Only the
/// fields the entity switcher actually needs are modeled here.
class RealmSummary {
  /// Also the value community_realm.realm_id always mirrors (Realm.save()
  /// enforces that invariant) - this is what POST /api/user/entity/switch
  /// expects as `realm_id`, not the realm's own entity id.
  final String id;
  final String name;
  final String? slug;
  final String? profile;
  final String type;
  final bool isAdmin;

  const RealmSummary({
    required this.id,
    required this.name,
    this.slug,
    this.profile,
    required this.type,
    required this.isAdmin,
  });

  factory RealmSummary.fromJson(Map<String, dynamic> json) {
    return RealmSummary(
      id: (json["id"] ?? "").toString(),
      name: (json["name"] ?? "").toString(),
      slug: json["slug"]?.toString(),
      profile: json["profile"]?.toString(),
      type: (json["type"] ?? "page").toString(),
      isAdmin: json["is_admin"] == true,
    );
  }
}

/// GET /api/user/auth/<slug>/ (Django, UserAuthentication.get) when the
/// looked-up account is a realm/page rather than a personal user - same
/// RealmSerializer field shape as RealmSummary above (fields="__all__" plus
/// the annotated counts), just with a few more display fields the read-only
/// realm profile screen wants that the switcher list doesn't need. Response
/// itself is {"data": {...}}, matching PublicProfile's envelope.
class RealmProfile {
  final String id;

  /// The realm's ENTITY id (RealmSerializer's `entity`). This - not `id` -
  /// is what follow and contact actions key on, since both are
  /// entity<->entity operations.
  final String entityId;
  final String name;
  final String? slug;
  final String? profile;
  final String? coverPhoto;
  final String? description;
  final String type;
  final int followersCount;
  final bool isAdmin;

  /// Whether the viewing entity already follows this realm - annotated onto
  /// the serializer alongside is_admin/is_member. Drives which of
  /// Follow/Following the profile shows.
  final bool isFollower;

  /// Connection state between the acting entity and this page. A Connection
  /// is entity<->entity, so a page can be a contact; the backend returns the
  /// same `connection` block the user profile does. All null when there is
  /// no connection (or when viewing your own page).
  final bool hasConnection;
  final bool? connectionAccomplished;
  final String? connectionId;
  final bool? isConnectionInitiator;

  const RealmProfile({
    required this.id,
    required this.entityId,
    required this.name,
    this.slug,
    this.profile,
    this.coverPhoto,
    this.description,
    required this.type,
    required this.followersCount,
    required this.isAdmin,
    this.isFollower = false,
    this.hasConnection = false,
    this.connectionAccomplished,
    this.connectionId,
    this.isConnectionInitiator,
  });

  factory RealmProfile.fromJson(Map<String, dynamic> json) {
    final connection = json["connection"] is Map
        ? Map<String, dynamic>.from(json["connection"])
        : const <String, dynamic>{};
    return RealmProfile(
      id: (json["id"] ?? "").toString(),
      entityId: (json["entity"] ?? "").toString(),
      name: (json["name"] ?? "").toString(),
      slug: json["slug"]?.toString(),
      profile: json["profile"]?.toString(),
      coverPhoto: json["cover_photo"]?.toString(),
      description: json["description"]?.toString(),
      type: (json["type"] ?? "page").toString(),
      followersCount: json["followers_count"] is int
          ? json["followers_count"]
          : int.tryParse(json["followers_count"]?.toString() ?? '') ?? 0,
      isAdmin: json["is_admin"] == true,
      isFollower: json["is_follower"] == true,
      hasConnection: connection["is_connection_present"] == true,
      connectionAccomplished: connection["is_connection_handshaked"] as bool?,
      connectionId: connection["connection_id"]?.toString(),
      isConnectionInitiator:
          connection["is_user_connection_initiator"] as bool?,
    );
  }
}
