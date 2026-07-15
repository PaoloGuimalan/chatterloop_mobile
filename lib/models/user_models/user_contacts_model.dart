import 'package:chatterloop_app/models/user_models/group_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';

class UserContacts {
  final String contactID;
  final String actionBy;
  final ActionDate actionDate;
  final bool status;
  final String type;
  final UserDetails userdetails;
  final GroupDetails? groupdetails;

  const UserContacts(this.contactID, this.actionBy, this.actionDate,
      this.status, this.type, this.userdetails, this.groupdetails);

  factory UserContacts.fromJson(Map<String, dynamic> json) {
    return UserContacts(
        json["contactID"],
        json["actionBy"],
        ActionDate.fromJson(json["actionDate"]),
        json["status"],
        json["type"],
        UserDetails.fromJson(json["userdetails"]),
        json["groupdetails"] != null
            ? GroupDetails.fromJson(json["groupdetails"])
            : null);
  }
}

class ActionDate {
  final String date;
  final String time;

  const ActionDate(this.date, this.time);

  @override
  String toString() {
    return 'ActionDate(date: $date, time; $time)';
  }

  /// Accepts either the {date, time} shape some endpoints format
  /// server-side, or a raw ISO date string - which is what Mongoose Date
  /// fields (e.g. messages.messageDate) actually serialize as when no
  /// formatting step exists for that particular route. A Map cast here
  /// used to throw on those routes, aborting the whole parse (e.g. a
  /// conversation's messages silently never rendering).
  factory ActionDate.fromJson(dynamic json) {
    if (json is Map) {
      return ActionDate(
        (json["date"] ?? "").toString(),
        (json["time"] ?? "").toString(),
      );
    }
    return ActionDate(json?.toString() ?? "", "");
  }
}

class UserDetails {
  final String type;
  final UsersContactPreview userone;
  final UsersContactPreview? usertwo;

  const UserDetails(this.type, this.userone, this.usertwo);

  factory UserDetails.fromJson(Map<String, dynamic> json) {
    return UserDetails(
      json["type"],
      UsersContactPreview.fromJson(json["userone"]),
      json["usertwo"] != null
          ? UsersContactPreview.fromJson(json["usertwo"])
          : null,
    );
  }
}

class UsersContactPreview {
  /// Despite the name, this is the username, not an id - the server
  /// (transformers.js's formatConnectionData/formatToDesiredStructure)
  /// populates it from row.username. entityID below is the real entity
  /// id, which is what messages.sender/receivers/seeners are actually
  /// keyed by - use entityID to match a message to this person, not this.
  final String userID;
  final String entityID;
  final UserFullname fullname;
  final String profile;
  final String? coverphoto;
  final bool? isActivated;
  final bool? isVerified;

  const UsersContactPreview(this.userID, this.entityID, this.fullname,
      this.profile, this.coverphoto, this.isActivated, this.isVerified);

  String get displayName {
    final full = [fullname.firstName, fullname.lastName]
        .where((p) => p.trim().isNotEmpty)
        .join(" ");
    return full.isNotEmpty ? full : userID;
  }

  factory UsersContactPreview.fromJson(Map<String, dynamic> json) {
    return UsersContactPreview(
        (json["userID"] ?? "").toString(),
        (json["entityID"] ?? json["_id"] ?? "").toString(),
        json["fullname"] is Map
            ? UserFullname.fromJson(Map<String, dynamic>.from(json["fullname"]))
            : const UserFullname("", "", ""),
        (json["profile"] ?? "none").toString(),
        json["coverphoto"]?.toString() ?? "",
        json["isActivated"] ?? false,
        json["isVerified"] ?? false);
  }
}
