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

/// GET `/api/user/auth/<slug>/` (Django, UserAuthentication.get) when the
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

  /// Set when this realm sits under another one - a group with a parent is a
  /// CHANNEL, which webapp treats as its own kind for the manage form (see
  /// realmFormFields). Nothing else distinguishes the two.
  final String? parent;

  /// Page-only contact address, and group/server privacy. Both are manage-form
  /// fields rather than profile ones, which is why they were absent until the
  /// manage screen needed them.
  final String? email;
  final bool isPrivate;

  final int followersCount;
  final bool isAdmin;

  /// Realm.is_verified - the same blue badge a person's profile gets. Arrives
  /// on every realm payload (RealmSerializer is fields="__all__"); the app
  /// simply wasn't reading it, so verified pages showed no badge anywhere.
  final bool isVerified;

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
    this.parent,
    this.email,
    this.isPrivate = false,
    required this.followersCount,
    required this.isAdmin,
    this.isVerified = false,
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
      parent: json["parent"]?.toString(),
      email: json["email"]?.toString(),
      isPrivate: json["is_private"] == true,
      followersCount: json["followers_count"] is int
          ? json["followers_count"]
          : int.tryParse(json["followers_count"]?.toString() ?? '') ?? 0,
      isAdmin: json["is_admin"] == true,
      isVerified: json["is_verified"] == true,
      isFollower: json["is_follower"] == true,
      hasConnection: connection["is_connection_present"] == true,
      connectionAccomplished: connection["is_connection_handshaked"] as bool?,
      connectionId: connection["connection_id"]?.toString(),
      isConnectionInitiator:
          connection["is_user_connection_initiator"] as bool?,
    );
  }
}

/// One person in a realm's roster - a member or a follower.
///
/// The two endpoints wrap their person differently (a member carries a
/// `entity`/`role`/`member_id`, a follower a `follower`/`follow_id`), but what
/// a ROW needs is identical, so both parse into this. [removalId] is whichever
/// id that list's remove call takes, which is the one place they genuinely
/// differ:
///
///   members   DELETE /realms/remove-user {realm_id, account_ids} - and
///             despite that field name it wants the ENTITY id. Web passes
///             `member.entity.id`, not `member.entity.details.id`. Sending the
///             account id is a request that returns fine and removes nobody.
///   followers DELETE /api/realm/realm-followers {realm_id, follow_id} - the
///             FOLLOW row's id.
class RealmPerson {
  final String entityId;
  final String accountId;
  final String displayName;
  final String handle;
  final String? profile;
  final bool isVerified;

  /// Members only; null for a follower, who has no role. "admin" or "member".
  final String? role;

  /// The MEMBER ROW's id, which the role endpoint takes (member_id). Members
  /// only.
  final String memberId;

  /// The realm id carried ON THE ROW (`member.realm`). Web passes this to both
  /// remove and role rather than the realm the screen was opened with, and so
  /// does this - they are the same value in the normal case, and where they
  /// aren't, the row is the one telling the truth about where it lives.
  final String realmId;

  /// What this list's remove endpoint wants. Empty when the payload didn't
  /// carry it, which is what disables the row's remove action.
  final String removalId;

  const RealmPerson({
    required this.entityId,
    required this.accountId,
    required this.displayName,
    required this.handle,
    this.profile,
    this.isVerified = false,
    this.role,
    this.memberId = '',
    this.realmId = '',
    this.removalId = '',
  });

  bool get isRealmAdmin => role == 'admin';

  /// Both shapes nest the person under `details` - a user contact preview
  /// (id/username/first_name/last_name/profile) for a follower, and the same
  /// under a flexible entity for a member. Everything below is defensive: a
  /// row whose person didn't resolve renders as an unnamed entry rather than
  /// taking the whole list down.
  static ({String id, String name, String handle, String? profile, bool badged})
      _person(dynamic raw) {
    final map =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final details =
        map["details"] is Map ? Map<String, dynamic>.from(map["details"]) : map;

    // A realm has a `name`; a user has first/middle/last. Whichever is
    // present is the display name.
    final realmName = (details["name"] ?? "").toString();
    final name = realmName.isNotEmpty
        ? realmName
        : [
            (details["first_name"] ?? "").toString(),
            (details["middle_name"] ?? "").toString(),
            (details["last_name"] ?? "").toString(),
          ].where((part) => part.isNotEmpty && part != "N/A").join(" ");

    final profile = details["profile"]?.toString();
    return (
      id: (details["id"] ?? "").toString(),
      name: name,
      handle: (details["username"] ?? details["slug"] ?? "").toString(),
      profile: (profile == null || profile.isEmpty || profile == "N/A")
          ? null
          : profile,
      badged: details["is_badged"] == true || details["is_verified"] == true,
    );
  }

  factory RealmPerson.fromMemberJson(Map<String, dynamic> json) {
    final entity = json["entity"];
    final person = _person(entity);
    final entityId = entity is Map ? (entity["id"] ?? "").toString() : "";
    return RealmPerson(
      entityId: entityId,
      accountId: person.id,
      displayName: person.name,
      handle: person.handle,
      profile: person.profile,
      isVerified: person.badged,
      role: json["role"]?.toString(),
      memberId: (json["member_id"] ?? "").toString(),
      realmId: (json["realm"] ?? "").toString(),
      // The ENTITY id, despite the endpoint calling the field `account_ids` -
      // web passes `member.entity.id` there, not `entity.details.id`. Sending
      // the account id instead is a request that succeeds and removes nobody.
      removalId: entityId,
    );
  }

  factory RealmPerson.fromFollowerJson(Map<String, dynamic> json) {
    final follower = json["follower"];
    final person = _person(follower);
    return RealmPerson(
      entityId: (follower is Map ? (follower["id"] ?? "").toString() : ""),
      accountId: person.id,
      displayName: person.name,
      handle: person.handle,
      profile: person.profile,
      isVerified: person.badged,
      removalId: (json["follow_id"] ?? "").toString(),
    );
  }
}
