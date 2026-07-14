class UserAuth {
  final bool? auth;
  final UserAccount user;

  const UserAuth(this.auth, this.user);

  @override
  String toString() {
    return 'UserAuth(auth: $auth, user: $user)';
  }
}

class UserAccount {
  final String id;
  final String username;
  final String firstname;
  final String middlename;
  final String lastname;
  final String? email;
  final bool isActivated;
  final bool isVerified;
  final String? profile;
  final String? coverphoto;
  final String? gender;
  final UserBirthDate? birthdate;

  /// Permission codenames for the currently active entity. Populated from
  /// the sibling `allowed_modules` field returned alongside `usertoken` by
  /// both Node's /auth/jwtchecker and Django's /api/user/auth - not part of
  /// the JWT payload itself. No entity-switcher UI consumes this yet; it's
  /// stored now so the shape doesn't need re-migrating later.
  final List<String> allowedModules;
  final ActiveEntity? activeEntity;
  final String? personalEntityId;

  const UserAccount(
      this.id,
      this.username,
      this.firstname,
      this.middlename,
      this.lastname,
      this.email,
      this.isActivated,
      this.isVerified,
      this.profile,
      this.coverphoto,
      this.gender,
      this.birthdate,
      {this.allowedModules = const [],
      this.activeEntity,
      this.personalEntityId});

  static const empty =
      UserAccount("", "", "", "", "", "", false, false, null, null, null, null);

  @override
  String toString() {
    return 'UserAccount(id: $id, username: $username, firstname: $firstname, middlename: $middlename, lastname: $lastname, email: $email, isActivated: $isActivated, isVerified: $isVerified)';
  }

  /// Decodes the nested-camelCase `usertoken` shape returned by Node's
  /// GET /auth/jwtchecker (`{_id, userID, fullname:{firstName,...}, ...}`).
  factory UserAccount.fromNodeJwt(Map<String, dynamic> json,
      {List<String> allowedModules = const [],
      ActiveEntity? activeEntity,
      String? personalEntityId}) {
    Map<String, dynamic> fullname = json["fullname"] is Map
        ? Map<String, dynamic>.from(json["fullname"])
        : const {};
    return UserAccount(
        (json["_id"] ?? json["userID"] ?? "").toString(),
        (json["userID"] ?? "").toString(),
        (fullname["firstName"] ?? "").toString(),
        (fullname["middleName"] ?? "").toString(),
        (fullname["lastName"] ?? "").toString(),
        json["email"]?.toString(),
        json["isActivated"] == true,
        json["isVerified"] == true,
        json["profile"]?.toString(),
        json["coverphoto"]?.toString(),
        json["gender"]?.toString(),
        json["birthdate"] is Map
            ? UserBirthDate.fromJson(
                Map<String, dynamic>.from(json["birthdate"]))
            : null,
        allowedModules: allowedModules,
        activeEntity: activeEntity,
        personalEntityId: personalEntityId);
  }

  /// Decodes the flat snake_case `usertoken` shape returned by Django's
  /// POST /api/user/auth and POST /api/user/me (AccountSerializer output).
  factory UserAccount.fromDjangoJwt(Map<String, dynamic> json,
      {List<String> allowedModules = const [],
      ActiveEntity? activeEntity,
      String? personalEntityId}) {
    return UserAccount(
        (json["id"] ?? "").toString(),
        (json["username"] ?? "").toString(),
        (json["first_name"] ?? "").toString(),
        (json["middle_name"] ?? "").toString(),
        (json["last_name"] ?? "").toString(),
        json["email"]?.toString(),
        json["is_active"] == true,
        json["is_verified"] == true,
        json["profile"]?.toString(),
        json["coverphoto"]?.toString(),
        json["gender"]?.toString(),
        json["birthdate"] is Map
            ? UserBirthDate.fromJson(
                Map<String, dynamic>.from(json["birthdate"]))
            : null,
        allowedModules: allowedModules,
        activeEntity: activeEntity,
        personalEntityId: personalEntityId);
  }

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
        json["id"],
        json["username"],
        json["firstname"],
        json["middlename"],
        json["lastname"],
        json["email"],
        json["isActivated"],
        json["isVerified"],
        json["profile"],
        json["coverphoto"],
        json["gender"],
        json["birthdate"] is Map
            ? UserBirthDate.fromJson(
                Map<String, dynamic>.from(json["birthdate"]))
            : null);
  }
}

class ActiveEntity {
  final String id;
  final String type;
  final String? realmType;
  final String? realmId;
  final String? name;
  final String? slug;
  final String? profile;

  const ActiveEntity(
      {required this.id,
      required this.type,
      this.realmType,
      this.realmId,
      this.name,
      this.slug,
      this.profile});

  factory ActiveEntity.fromJson(Map<String, dynamic> json) {
    return ActiveEntity(
      id: (json["id"] ?? "").toString(),
      type: (json["type"] ?? "user").toString(),
      realmType: json["realm_type"]?.toString(),
      realmId: json["realm_id"]?.toString(),
      name: json["name"]?.toString(),
      slug: json["slug"]?.toString(),
      profile: json["profile"]?.toString(),
    );
  }
}

class UserBirthDate {
  final String month;
  final String day;
  final String year;

  UserBirthDate(this.month, this.day, this.year);

  factory UserBirthDate.fromJson(Map<String, dynamic> json) {
    return UserBirthDate(
      json["month"],
      json["day"],
      json["year"],
    );
  }
}

class UserFullname {
  final String firstName;
  final String middleName;
  final String lastName;

  const UserFullname(this.firstName, this.middleName, this.lastName);

  @override
  String toString() {
    return 'UserFullname(firstName: $firstName, middleName; $middleName, lastName: $lastName)';
  }

  factory UserFullname.fromJson(Map<String, dynamic> json) {
    return UserFullname(
      json["firstName"],
      json["middleName"],
      json["lastName"],
    );
  }
}
