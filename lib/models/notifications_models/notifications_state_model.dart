import 'package:chatterloop_app/models/notifications_models/notifications_item_model.dart';

class NotificationsStateModel {
  final List<NotificationsItemModel> notificationsList;
  final int totalunread;

  /// Total notifications on the server, across all pages.
  final int total;

  /// Whether another page exists. The server computes this as
  /// `total - range * page > 0` (routes/users/index.js's GET
  /// /getNotifications), so it already accounts for the current page.
  final bool next;

  /// [total] and [next] are optional positional so the many existing
  /// two-argument call sites (sse_events, home_tab_scaffold, AppState's
  /// default) keep working unchanged - they only ever care about the list and
  /// the unread badge count, not pagination.
  const NotificationsStateModel(
    this.notificationsList,
    this.totalunread, [
    this.total = 0,
    this.next = false,
  ]);

  factory NotificationsStateModel.fromJson(Map<String, dynamic> json) {
    return NotificationsStateModel(
      (json["notificationsList"] as List)
          .map((notif) => NotificationsItemModel.fromJson(notif))
          .toList(),
      json["totalunread"],
      json["total"] ?? 0,
      json["next"] == true,
    );
  }
}
