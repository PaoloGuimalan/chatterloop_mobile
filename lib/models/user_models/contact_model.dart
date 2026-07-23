// Matches the actual Django /api/user/contacts response shape (verified
// against webapp/src/app/tabs/feed/Contacts.tsx + interfaces.ts's IContact)
// - NOT the old Node /u/getContacts shape user_contacts_model.dart holds,
// which is a different, legacy endpoint not used by the current webapp.

class ContactPersonDetails {
  final String id;
  final String username;
  final String firstName;
  final String middleName;
  final String lastName;
  final String? profile;
  final String? gender;
  final bool isBadged;

  const ContactPersonDetails({
    required this.id,
    required this.username,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    this.profile,
    this.gender,
    required this.isBadged,
  });

  String get displayName => [
        firstName,
        if (middleName.isNotEmpty && middleName != "N/A") middleName,
        lastName,
      ].where((part) => part.trim().isNotEmpty).join(" ");

  factory ContactPersonDetails.fromJson(Map<String, dynamic> json) {
    return ContactPersonDetails(
      id: (json["id"] ?? "").toString(),
      username: (json["username"] ?? "").toString(),
      firstName: (json["first_name"] ?? "").toString(),
      middleName: (json["middle_name"] ?? "").toString(),
      lastName: (json["last_name"] ?? "").toString(),
      profile: json["profile"]?.toString(),
      gender: json["gender"]?.toString(),
      isBadged: json["is_badged"] == true,
    );
  }
}

class ContactEntity {
  final String id;
  final String type;
  final ContactPersonDetails details;

  const ContactEntity(
      {required this.id, required this.type, required this.details});

  factory ContactEntity.fromJson(Map<String, dynamic> json) {
    return ContactEntity(
      id: (json["id"] ?? "").toString(),
      type: (json["type"] ?? "").toString(),
      details: ContactPersonDetails.fromJson(json["details"] is Map
          ? Map<String, dynamic>.from(json["details"])
          : const {}),
    );
  }
}

class Contact {
  final String id;
  final ContactEntity actionBy;
  final ContactEntity involvedEntity;
  final String connectionId;
  final String? nickname;
  final bool status;
  final String actionDate;
  final String type;

  const Contact({
    required this.id,
    required this.actionBy,
    required this.involvedEntity,
    required this.connectionId,
    this.nickname,
    required this.status,
    required this.actionDate,
    required this.type,
  });

  /// The other side of the connection, oriented on ENTITY ids.
  ///
  /// Pass the ACTING entity id (UserAccount.entityId), not an account id.
  /// Contacts are entity<->entity now, so a counterpart can be a page - and
  /// a page's `details.id` is a realm pk that can never equal a user id, so
  /// the old `actionBy.details.id == myAccountId` check resolved the wrong
  /// side for any user<->page contact. Comparing entity ids is the only
  /// test valid for both kinds, and it also stays correct while acting as
  /// a page (where neither side is the human).
  ContactEntity otherEntity(String myEntityId) =>
      actionBy.id == myEntityId ? involvedEntity : actionBy;

  ContactPersonDetails other(String myEntityId) =>
      otherEntity(myEntityId).details;

  /// Entity id of the other side - also the key AppState.presence uses.
  String otherEntityId(String myEntityId) => otherEntity(myEntityId).id;

  /// Whether the counterpart is a page rather than a person. Presence and
  /// "active now" are human concepts, so callers skip them for realms.
  bool otherIsRealm(String myEntityId) =>
      otherEntity(myEntityId).type == "realm";

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: (json["id"] ?? "").toString(),
      actionBy: ContactEntity.fromJson(json["action_by"] is Map
          ? Map<String, dynamic>.from(json["action_by"])
          : const {}),
      involvedEntity: ContactEntity.fromJson(json["involved_entity"] is Map
          ? Map<String, dynamic>.from(json["involved_entity"])
          : const {}),
      connectionId: (json["connection_id"] ?? "").toString(),
      nickname: json["nickname"]?.toString(),
      status: json["status"] == true,
      actionDate: (json["action_date"] ?? "").toString(),
      type: (json["type"] ?? "").toString(),
    );
  }
}
