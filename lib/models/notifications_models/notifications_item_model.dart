import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';

class NotificationsItemModel {
  String notificationID;
  String referenceID;
  bool referenceStatus;
  String toUserID;
  String fromUserID;
  NotificationContentModel content;
  ActionDate date;
  String type;
  bool isRead;
  NotificationFromUser? fromUser;

  NotificationsItemModel(
      this.notificationID,
      this.referenceID,
      this.referenceStatus,
      this.toUserID,
      this.fromUserID,
      this.content,
      this.date,
      this.type,
      this.isRead,
      this.fromUser);

  factory NotificationsItemModel.fromJson(Map<String, dynamic> json) {
    return NotificationsItemModel(
        json["notificationID"],
        json["referenceID"],
        json["referenceStatus"],
        json["toUserID"],
        json["fromUserID"],
        NotificationContentModel.fromJson(json["content"]),
        ActionDate.fromJson(json["date"]),
        json["type"],
        json["isRead"] ?? true,
        json["fromUser"] is Map
            ? NotificationFromUser.fromJson(
                Map<String, dynamic>.from(json["fromUser"]))
            : null);
  }
}

/// Server-populated from a plain SQL row (routes/users/index.js's
/// GET /getNotifications: `SELECT id, username, gender, profile, is_active,
/// is_verified FROM user_account ...`), not the {userID, fullname:{...},
/// coverphoto, isActivated, isVerified} shape UsersContactPreview expects
/// elsewhere - and it's null outright whenever the sender's account isn't
/// found in that join. Both cases used to throw a null/type cast here.
class NotificationFromUser {
  final String id;
  final String username;
  final String? gender;
  final String? profile;
  final bool isActive;
  final bool isVerified;

  const NotificationFromUser({
    required this.id,
    required this.username,
    this.gender,
    this.profile,
    required this.isActive,
    required this.isVerified,
  });

  factory NotificationFromUser.fromJson(Map<String, dynamic> json) {
    return NotificationFromUser(
      id: (json["id"] ?? "").toString(),
      username: (json["username"] ?? "").toString(),
      gender: json["gender"]?.toString(),
      profile: json["profile"]?.toString(),
      isActive: json["is_active"] == true,
      isVerified: json["is_verified"] == true,
    );
  }
}

class NotificationContentModel {
  String headline;
  String details;

  NotificationContentModel(this.headline, this.details);

  factory NotificationContentModel.fromJson(Map<String, dynamic> json) {
    return NotificationContentModel(json['headline'], json['details']);
  }
}
