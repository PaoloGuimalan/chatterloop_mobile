/// Result item from GET /api/user/search/:query/ (Django, AccountSearchSerializer).
/// Note this endpoint's response is NOT wrapped in the usual {status, result}
/// envelope - it's a plain DRF paginated response: {count, next, previous, results}.
class SearchResultUser {
  final String id;

  /// The canonical id for contact actions - connections are entity<->entity,
  /// so the endpoints key on this rather than the account id.
  final String entityId;
  final String username;
  final String firstName;
  final String middleName;
  final String lastName;
  final String? profile;
  final String? gender;
  final bool hasConnection;
  final bool connectionAccomplished;
  final String? connectionId;
  final bool isActionByEntity;

  /// "user" or "realm". Search is entity-generic now, so a result may be a
  /// page - which routes to /realm/:slug rather than /user/:username and has
  /// no contact actions (you open the page and follow from there).
  final String type;

  /// Realm.type ("page", "group", ...) for realm hits; null for people.
  final String? realmType;

  bool get isRealm => type == "realm";

  const SearchResultUser({
    required this.id,
    required this.entityId,
    required this.username,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    this.profile,
    this.gender,
    required this.hasConnection,
    required this.connectionAccomplished,
    this.connectionId,
    required this.isActionByEntity,
    this.type = "user",
    this.realmType,
  });

  String get displayName => [
        firstName,
        if (middleName.isNotEmpty && middleName != "N/A") middleName,
        lastName,
      ].where((part) => part.trim().isNotEmpty).join(" ");

  factory SearchResultUser.fromJson(Map<String, dynamic> json) {
    return SearchResultUser(
      id: (json["id"] ?? "").toString(),
      entityId: (json["entity_id"] ?? "").toString(),
      username: (json["username"] ?? "").toString(),
      firstName: (json["first_name"] ?? "").toString(),
      middleName: (json["middle_name"] ?? "").toString(),
      lastName: (json["last_name"] ?? "").toString(),
      profile: json["profile"]?.toString(),
      gender: json["gender"]?.toString(),
      hasConnection: json["has_connection"] == true,
      connectionAccomplished: json["connection_accomplished"] == true,
      connectionId: json["connection_id"]?.toString(),
      isActionByEntity: json["is_action_by_entity"] == true,
    );
  }

  /// Search v2 (`/api/entity/search/`), which returns users AND pages in one
  /// normalized shape: {entity_id, type, display_name, handle, profile,
  /// is_verified, realm_type} plus connection state for people.
  ///
  /// Mapped onto the same fields the v1 shape used - display_name lands in
  /// firstName with an "N/A" middle and empty last - so `displayName` and
  /// every widget reading these keep working unchanged for both kinds.
  factory SearchResultUser.fromEntityJson(Map<String, dynamic> json) {
    return SearchResultUser(
      // Account id: present for people, null for pages (which are not
      // contact targets). Falls back to the entity id so widget keys and
      // avatars always have something stable.
      id: (json["id"] ?? json["entity_id"] ?? "").toString(),
      entityId: (json["entity_id"] ?? "").toString(),
      username: (json["handle"] ?? "").toString(),
      firstName: (json["display_name"] ?? "").toString(),
      middleName: "N/A",
      lastName: "",
      // v2 already normalizes "none"/"N/A" to null.
      profile: json["profile"]?.toString(),
      gender: null,
      hasConnection: json["has_connection"] == true,
      connectionAccomplished: json["connection_accomplished"] == true,
      connectionId: json["connection_id"]?.toString(),
      isActionByEntity: json["is_action_by_entity"] == true,
      type: (json["type"] ?? "user").toString(),
      realmType: json["realm_type"]?.toString(),
    );
  }
}

/// Response of GET /api/user/auth/:username/ (Django, `UserAuthentication.get`)
/// - a third, distinct JSON shape from either UserAccount factory: nested
/// `fullname` like the Node jwtchecker shape, but with its own field casing,
/// wrapped in a top-level {"data": {...}} envelope (no "status" field), and
/// the confusingly-named "userID" key actually holds the *username* string,
/// not an ID (kept as-is here since that's what the backend sends).
class PublicProfile {
  final String id;
  final String entityId;
  final String username;
  final String firstName;
  final String middleName;
  final String lastName;
  final String? profile;
  final String? coverphoto;
  final String? gender;
  final String? email;
  final bool isActivated;
  final bool isVerified;
  final bool isBadged;

  /// null when viewing your own profile (backend returns null in that case).
  final bool? hasConnection;
  final bool? connectionAccomplished;
  final String? connectionId;
  final bool? isConnectionInitiator;

  /// Following is entity->entity now, so a person can be followed just like
  /// a page. Drives the Follow/Following button on the user profile.
  final bool isFollower;

  /// Raw parts from the response's "birthdate": {month, day, year} - month
  /// is already a full name (Django's birthdate.strftime("%B")), not a
  /// number, unlike joinedDate below. Null when the account has none set.
  final String? birthMonth;
  final String? birthDay;
  final String? birthYear;

  /// "dateCreated.date" as sent by the server, "MM/DD/YYYY" - matches
  /// webapp's Profile.tsx, which feeds this exact string into
  /// formattedDateToWords for the "Joined" line.
  final String? joinedDate;

  const PublicProfile({
    required this.id,
    required this.entityId,
    required this.username,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    this.profile,
    this.coverphoto,
    this.gender,
    this.email,
    required this.isActivated,
    required this.isVerified,
    required this.isBadged,
    this.hasConnection,
    this.connectionAccomplished,
    this.connectionId,
    this.isConnectionInitiator,
    this.isFollower = false,
    this.birthMonth,
    this.birthDay,
    this.birthYear,
    this.joinedDate,
  });

  String get displayName => [
        firstName,
        if (middleName.isNotEmpty && middleName != "N/A") middleName,
        lastName,
      ].where((part) => part.trim().isNotEmpty).join(" ");

  factory PublicProfile.fromJson(Map<String, dynamic> json) {
    final fullname = json["fullname"] is Map
        ? Map<String, dynamic>.from(json["fullname"])
        : const <String, dynamic>{};
    final connection = json["connection"] is Map
        ? Map<String, dynamic>.from(json["connection"])
        : const <String, dynamic>{};
    final birthdate = json["birthdate"] is Map
        ? Map<String, dynamic>.from(json["birthdate"])
        : null;
    final dateCreated = json["dateCreated"] is Map
        ? Map<String, dynamic>.from(json["dateCreated"])
        : const <String, dynamic>{};
    return PublicProfile(
      id: (json["id"] ?? "").toString(),
      entityId: (json["entityID"] ?? "").toString(),
      username: (json["userID"] ?? "").toString(),
      firstName: (fullname["firstName"] ?? "").toString(),
      middleName: (fullname["middleName"] ?? "").toString(),
      lastName: (fullname["lastName"] ?? "").toString(),
      profile: json["profile"]?.toString(),
      coverphoto: json["coverphoto"]?.toString(),
      gender: json["gender"]?.toString(),
      email: json["email"]?.toString(),
      isActivated: json["isActivated"] == true,
      isVerified: json["isVerified"] == true,
      isBadged: json["isBadged"] == true,
      hasConnection: connection["is_connection_present"] as bool?,
      connectionAccomplished: connection["is_connection_handshaked"] as bool?,
      connectionId: connection["connection_id"]?.toString(),
      isConnectionInitiator:
          connection["is_user_connection_initiator"] as bool?,
      isFollower: json["is_follower"] == true,
      birthMonth: birthdate?["month"]?.toString(),
      birthDay: birthdate?["day"]?.toString(),
      birthYear: birthdate?["year"]?.toString(),
      joinedDate: dateCreated["date"]?.toString(),
    );
  }
}
