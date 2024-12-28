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

  factory ActionDate.fromJson(Map<String, dynamic> json) {
    return ActionDate(
      json["date"],
      json["time"],
    );
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
  final String userID;
  final UserFullname fullname;
  final String profile;
  final String? coverphoto;

  const UsersContactPreview(
      this.userID, this.fullname, this.profile, this.coverphoto);

  factory UsersContactPreview.fromJson(Map<String, dynamic> json) {
    return UsersContactPreview(
      json["userID"],
      UserFullname.fromJson(json["fullname"]),
      json["profile"],
      json["coverphoto"],
    );
  }
}
