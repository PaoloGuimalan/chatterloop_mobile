import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';

class ServerDetails {
  final String serverID;
  final String serverName;
  final String profile;
  final ActionDate dateCreated;
  final List<ServerMember> members;
  final String createdBy;
  final bool privacy;

  ServerDetails(this.serverID, this.serverName, this.profile, this.dateCreated,
      this.members, this.createdBy, this.privacy);

  factory ServerDetails.fromJson(Map<String, dynamic> json) {
    return ServerDetails(
        json["serverID"],
        json["serverName"],
        json["profile"],
        ActionDate.fromJson(json["dateCreated"]),
        (json["members"] as List)
            .map((member) => ServerMember.fromJson(member))
            .toList(),
        json["createdBy"],
        json["privacy"]);
  }
}

class ServerMember {
  final String userID;

  ServerMember(this.userID);

  factory ServerMember.fromJson(Map<String, dynamic> json) {
    return ServerMember(json["userID"]);
  }
}
