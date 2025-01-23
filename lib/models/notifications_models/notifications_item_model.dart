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
  UsersContactPreview fromUser;

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
        UsersContactPreview.fromJson(json["fromUser"]));
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
