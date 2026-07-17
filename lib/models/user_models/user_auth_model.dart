import 'package:chatterloop_app/models/user_models/search_result_model.dart';

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

  /// Django's computed `is_complete` = is_profile_complete() (birthdate AND
  /// gender) AND no pending consents. Gates access after login alongside
  /// isVerified, mirroring webapp's App.tsx routing. The login/tp_auth
  /// response carries the authoritative value; the Node jwtchecker used on
  /// session restore doesn't compute it, so fromNodeJwt approximates it from
  /// birthdate+gender presence (consent state can't be known there).
  final bool isComplete;

  /// Policy document_types the account still has to accept (e.g. "terms",
  /// "privacy") - non-empty means the Setup consent step is still pending.
  final List<String> pendingConsents;
  final String? profile;
  final String? coverphoto;
  final String? gender;
  final UserBirthDate? birthdate;

  /// "MM/DD/YYYY", only ever populated via fromPublicProfile - the JWT
  /// payloads (fromNodeJwt/fromDjangoJwt) don't carry a join date, only
  /// GET /api/user/auth/:username/ does, which profile_view.dart already
  /// round-trips through on every mount to refresh this same object.
  final String? joinedDate;

  /// Same story as joinedDate - only fromPublicProfile populates this.
  final bool isBadged;

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
      this.personalEntityId,
      this.joinedDate,
      this.isBadged = false,
      this.isComplete = true,
      this.pendingConsents = const []});

  static const empty =
      UserAccount("", "", "", "", "", "", false, false, null, null, null, null);

  /// Field-level clone - used to optimistically flip isVerified/isComplete
  /// after the verify-email / setup steps succeed, so the router gate
  /// (which reads the Redux user) lets the account through on the next
  /// navigation without a full re-fetch. Preserves allowedModules/
  /// activeEntity/personalEntityId, which those step responses don't return.
  UserAccount copyWith({
    bool? isVerified,
    bool? isComplete,
    List<String>? pendingConsents,
    UserBirthDate? birthdate,
    String? gender,
  }) {
    return UserAccount(
      id,
      username,
      firstname,
      middlename,
      lastname,
      email,
      isActivated,
      isVerified ?? this.isVerified,
      profile,
      coverphoto,
      gender ?? this.gender,
      birthdate ?? this.birthdate,
      allowedModules: allowedModules,
      activeEntity: activeEntity,
      personalEntityId: personalEntityId,
      joinedDate: joinedDate,
      isBadged: isBadged,
      isComplete: isComplete ?? this.isComplete,
      pendingConsents: pendingConsents ?? this.pendingConsents,
    );
  }

  /// The entity id messages.sender/receivers/seeners are actually keyed by
  /// - distinct from `id`, which is the Django Account row's id. Both
  /// backends' jwtchecker middleware resolves entity_id from the acting
  /// entity (decode.entity / active_entity), never from the account id, so
  /// comparing message ownership against `id` never matches.
  String get entityId => activeEntity?.id ?? personalEntityId ?? id;

  /// Always the account holder's own name, regardless of which entity is
  /// currently active - used for the "switch back to yourself" row in the
  /// entity switcher, which must keep showing your real name even while
  /// acting as a page.
  String get personalDisplayName => [
        firstname,
        if (middlename.isNotEmpty && middlename != "N/A") middlename,
        lastname,
      ].where((part) => part.trim().isNotEmpty).join(" ");

  /// True once switched to a page/realm entity rather than acting as
  /// yourself - matches webapp's UserMenu.tsx isActingAsPage check
  /// (activeEntity.is_switched).
  bool get isActingAsEntity => activeEntity?.type == "realm";

  /// Display identity for whichever entity is currently active - the
  /// account itself when personal, or the switched-to page's own
  /// name/avatar/slug otherwise. Drives the top-bar avatar and user-menu
  /// header; the profile TAB itself still always shows the personal
  /// account (no page-profile screen exists yet to switch it to).
  String get activeDisplayName => isActingAsEntity
      ? (activeEntity?.name ?? personalDisplayName)
      : personalDisplayName;

  String get activeHandle => isActingAsEntity
      ? "@${activeEntity?.slug ?? activeEntity?.id ?? ''}"
      : "@$username";

  String? get activeAvatarSrc => isActingAsEntity
      ? activeEntity?.profile
      : (profile != "none" ? profile : null);

  String get activeAvatarSeed =>
      isActingAsEntity ? (activeEntity?.id ?? id) : id;

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
    // Node's transformUser computes isComplete = birthdate && gender (profile
    // completeness only - it can't know consent state). The strict consent
    // half of the restore gate is layered on in auth_controller from the
    // pending consents persisted at the last authoritative (Django) login.
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
        personalEntityId: personalEntityId,
        isComplete: json["isComplete"] == true);
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
        personalEntityId: personalEntityId,
        // Only gate on an EXPLICIT is_complete:false - a response that omits
        // the field (some Django token shapes) must not be treated as
        // incomplete and bounced to /setup.
        isComplete: json.containsKey("is_complete")
            ? json["is_complete"] == true
            : true,
        pendingConsents: (json["pending_consents"] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const []);
  }

  /// From the GET /api/user/auth/:username/ response (PublicProfile) -
  /// used to refresh the current user's own profile the same way the
  /// webapp always re-fetches via this endpoint, even for your own
  /// profile, rather than only trusting the JWT-cached copy.
  factory UserAccount.fromPublicProfile(PublicProfile publicProfile,
      {List<String> allowedModules = const [],
      ActiveEntity? activeEntity,
      String? personalEntityId}) {
    return UserAccount(
        publicProfile.id,
        publicProfile.username,
        publicProfile.firstName,
        publicProfile.middleName,
        publicProfile.lastName,
        publicProfile.email,
        publicProfile.isActivated,
        publicProfile.isVerified,
        publicProfile.profile,
        publicProfile.coverphoto,
        publicProfile.gender,
        publicProfile.birthDay != null
            ? UserBirthDate(publicProfile.birthMonth ?? "",
                publicProfile.birthDay ?? "", publicProfile.birthYear ?? "")
            : null,
        allowedModules: allowedModules,
        activeEntity: activeEntity,
        personalEntityId: personalEntityId,
        joinedDate: publicProfile.joinedDate,
        isBadged: publicProfile.isBadged);
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
      (json["firstName"] ?? "").toString(),
      (json["middleName"] ?? "").toString(),
      (json["lastName"] ?? "").toString(),
    );
  }
}
