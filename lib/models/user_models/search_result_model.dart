/// Result item from GET /api/user/search/:query/ (Django, AccountSearchSerializer).
/// Note this endpoint's response is NOT wrapped in the usual {status, result}
/// envelope - it's a plain DRF paginated response: {count, next, previous, results}.
class SearchResultUser {
  final String id;
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

  const SearchResultUser({
    required this.id,
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
  });

  String get displayName => [
        firstName,
        if (middleName.isNotEmpty && middleName != "N/A") middleName,
        lastName,
      ].where((part) => part.trim().isNotEmpty).join(" ");

  factory SearchResultUser.fromJson(Map<String, dynamic> json) {
    return SearchResultUser(
      id: (json["id"] ?? "").toString(),
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
    );
  }
}
