import 'package:chatterloop_app/models/file_models/file_info_models.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';

class ConversationInfoModel {
  String contactID;
  String actionBy;
  ActionDate actionDate;
  bool status;
  List<UserIDObject> users;
  String type;
  List<UsersContactPreview> usersWithInfo;
  List<ConversationFilesModel> conversationfiles;

  ConversationInfoModel(
      this.contactID,
      this.actionBy,
      this.actionDate,
      this.status,
      this.users,
      this.type,
      this.usersWithInfo,
      this.conversationfiles);

  factory ConversationInfoModel.fromJson(Map<String, dynamic> json) {
    return ConversationInfoModel(
        json["contactID"],
        json["actionBy"],
        ActionDate.fromJson(json["actionDate"]),
        json["status"],
        (json["users"] as List)
            .map((user) => UserIDObject.fromJson(user))
            .toList(),
        json["type"],
        (json["usersWithInfo"] as List)
            .map((user) => UsersContactPreview.fromJson(user))
            .toList(),
        (json["conversationfiles"] as List)
            .map((file) => ConversationFilesModel.fromJson(file))
            .toList());
  }
}

class UserIDObject {
  String userID;

  UserIDObject(this.userID);

  factory UserIDObject.fromJson(Map<String, dynamic> json) {
    return UserIDObject(json["userID"]);
  }
}
