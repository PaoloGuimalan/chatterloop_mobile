import 'package:chatterloop_app/models/notifications_models/notifications_item_model.dart';

class NotificationsStateModel {
  final List<NotificationsItemModel> notificationsList;
  final int totalunread;

  const NotificationsStateModel(this.notificationsList, this.totalunread);

  factory NotificationsStateModel.fromJson(Map<String, dynamic> json) {
    return NotificationsStateModel(
        (json["notificationsList"] as List)
            .map((notif) => NotificationsItemModel.fromJson(notif))
            .toList(),
        json["totalunread"]);
  }
}
