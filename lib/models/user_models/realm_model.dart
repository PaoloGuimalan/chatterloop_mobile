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
  final String name;
  final String? slug;
  final String? profile;
  final String? coverPhoto;
  final String? description;
  final String type;
  final int followersCount;
  final bool isAdmin;

  const RealmProfile({
    required this.id,
    required this.name,
    this.slug,
    this.profile,
    this.coverPhoto,
    this.description,
    required this.type,
    required this.followersCount,
    required this.isAdmin,
  });

  factory RealmProfile.fromJson(Map<String, dynamic> json) {
    return RealmProfile(
      id: (json["id"] ?? "").toString(),
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
    );
  }
}
