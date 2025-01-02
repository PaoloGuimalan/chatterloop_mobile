// ignore_for_file: prefer_if_null_operators

import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';

class GroupDetails {
  final String groupID;
  final String groupName;
  final String profile;
  final ActionDate dateCreated;
  final String createdBy;
  final String type;
  final bool? privacy;
  final String? serverID;

  const GroupDetails(this.groupID, this.groupName, this.profile,
      this.dateCreated, this.createdBy, this.type, this.privacy, this.serverID);

  factory GroupDetails.fromJson(Map<String, dynamic> json) {
    return GroupDetails(
        json["groupID"],
        json["groupName"],
        json["profile"] ?? "",
        ActionDate.fromJson(json["dateCreated"]),
        json["createdBy"],
        json["type"],
        json["privacy"],
        json["serverID"] != null ? json["serverID"] : null);
  }
}
