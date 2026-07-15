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

  /// The server can legitimately return an empty/near-empty object here -
  /// e.g. opening a conversation that has no backing user_connection row
  /// yet (a fresh single conversation with no message sent, so
  /// formatConnectionData(rows) short-circuits on an empty rows array).
  /// Every field is defensive so that edge case degrades to an "unknown
  /// participants" conversation instead of throwing and leaving
  /// conversationInfo permanently unset.
  factory ConversationInfoModel.fromJson(Map<String, dynamic> json) {
    return ConversationInfoModel(
        (json["contactID"] ?? "").toString(),
        (json["actionBy"] ?? "").toString(),
        ActionDate.fromJson(json["actionDate"]),
        json["status"] == true,
        json["users"] is List
            ? (json["users"] as List)
                .whereType<Map>()
                .map((user) =>
                    UserIDObject.fromJson(Map<String, dynamic>.from(user)))
                .toList()
            : [],
        (json["type"] ?? "single").toString(),
        json["usersWithInfo"] is List
            ? (json["usersWithInfo"] as List)
                .whereType<Map>()
                .map((user) => UsersContactPreview.fromJson(
                    Map<String, dynamic>.from(user)))
                .toList()
            : [],
        json["conversationfiles"] is List
            ? (json["conversationfiles"] as List)
                .whereType<Map>()
                .map((file) => ConversationFilesModel.fromJson(
                    Map<String, dynamic>.from(file)))
                .toList()
            : []);
  }
}

/// Conversation membership is keyed by entity id in Postgres/Mongo, not
/// username - matching messages.sender/receivers/seeners and
/// Conversations.participant_ids. Despite the name, `userID` here is
/// actually the username (server's transformers.js's
/// formatConnectionData/formatToDesiredStructure both populate
/// `users.push({userID: row.username, _id: row.involved_entity_id})`) -
/// entityID is the real id and is what receivers/seen-tracking must use.
class UserIDObject {
  String userID;
  String entityID;

  UserIDObject(this.userID, this.entityID);

  factory UserIDObject.fromJson(Map<String, dynamic> json) {
    return UserIDObject((json["userID"] ?? "").toString(),
        (json["entityID"] ?? json["_id"] ?? "").toString());
  }
}
