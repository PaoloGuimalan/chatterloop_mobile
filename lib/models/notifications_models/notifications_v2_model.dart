// Notifications v2 shapes - the redesigned Notifications screen's data.
// Mirror webapp's INotificationV2 / NotificationSectionData, which mirror the
// Node /u/v2/notifications/* routes exactly.
//
// Distinct from NotificationsItemModel (v1, notifications_item_model.dart):
// v1's `fromUser` is a raw user_account row (username/gender/is_active) and
// is null outright for page senders, while v2 resolves the sender through
// entity_entity so a page gets a real identity too. v1 stays in place for the
// topbar badge + SSE flow, so both shapes coexist deliberately.

/// The three columns notifications are bucketed into, server side, by type.
enum NotificationSection { activity, connections, system }

extension NotificationSectionSlug on NotificationSection {
  /// The path segment AND the overview response key - both use this name.
  String get slug => switch (this) {
        NotificationSection.activity => "activity",
        NotificationSection.connections => "connections",
        NotificationSection.system => "system",
      };

  String get title => switch (this) {
        NotificationSection.activity => "Activity",
        NotificationSection.connections => "Connections",
        NotificationSection.system => "System",
      };

  static NotificationSection? fromSlug(String slug) {
    for (final section in NotificationSection.values) {
      if (section.slug == slug) return section;
    }
    return null;
  }
}

/// Normalized sender - works for BOTH a person and a page.
class NotificationSenderV2 {
  final String entityId;
  final String type;
  final String displayName;
  final String handle;
  final String? profile;
  final bool isVerified;

  const NotificationSenderV2({
    required this.entityId,
    required this.type,
    required this.displayName,
    required this.handle,
    this.profile,
    required this.isVerified,
  });

  factory NotificationSenderV2.fromJson(Map<String, dynamic> json) {
    return NotificationSenderV2(
      entityId: (json["entity_id"] ?? "").toString(),
      type: (json["type"] ?? "user").toString(),
      displayName: (json["display_name"] ?? "").toString(),
      handle: (json["handle"] ?? "").toString(),
      profile: json["profile"]?.toString(),
      isVerified: json["is_verified"] == true,
    );
  }
}

class NotificationV2 {
  final String notificationID;
  final String referenceID;

  /// null when the notification type has no reference to resolve. For a
  /// contact request it flips true once accepted/declined, which is what
  /// hides the Confirm/Decline buttons.
  final bool? referenceStatus;
  final String fromUserID;
  final NotificationSenderV2? fromUser;
  final String headline;
  final String details;
  final String date;
  final String? time;
  final String type;
  final bool isRead;

  const NotificationV2({
    required this.notificationID,
    required this.referenceID,
    this.referenceStatus,
    required this.fromUserID,
    this.fromUser,
    required this.headline,
    required this.details,
    required this.date,
    this.time,
    required this.type,
    required this.isRead,
  });

  NotificationV2 copyWith({bool? isRead, bool? referenceStatus}) =>
      NotificationV2(
        notificationID: notificationID,
        referenceID: referenceID,
        referenceStatus: referenceStatus ?? this.referenceStatus,
        fromUserID: fromUserID,
        fromUser: fromUser,
        headline: headline,
        details: details,
        date: date,
        time: time,
        type: type,
        isRead: isRead ?? this.isRead,
      );

  /// Types that can be answered from the row itself. Both carry
  /// referenceStatus=false while open and flip to true once settled.
  ///
  /// `follow_request` is a follow of a PRIVATE profile, which lands pending
  /// until its owner approves it. Without it here the row rendered passively
  /// and a private-profile user had no way to approve a follow request on
  /// mobile at all.
  static const _answerableTypes = {"contact_request", "follow_request"};

  /// A request is actionable only while it's still pending.
  bool get isActionable =>
      _answerableTypes.contains(type) && referenceStatus != true;

  /// True when this row's buttons answer a FOLLOW request rather than a
  /// contact request - they hit different endpoints with different ids.
  bool get isFollowRequest => type == "follow_request";

  factory NotificationV2.fromJson(Map<String, dynamic> json) {
    final content = json["content"] is Map
        ? Map<String, dynamic>.from(json["content"])
        : const <String, dynamic>{};
    final date = json["date"] is Map
        ? Map<String, dynamic>.from(json["date"])
        : const <String, dynamic>{};
    final sender = json["fromUser"];
    return NotificationV2(
      notificationID: (json["notificationID"] ?? "").toString(),
      referenceID: (json["referenceID"] ?? "").toString(),
      referenceStatus: json["referenceStatus"] is bool
          ? json["referenceStatus"] as bool
          : null,
      fromUserID: (json["fromUserID"] ?? "").toString(),
      fromUser: sender is Map
          ? NotificationSenderV2.fromJson(Map<String, dynamic>.from(sender))
          : null,
      headline: (content["headline"] ?? "").toString(),
      details: (content["details"] ?? "").toString(),
      date: (date["date"] ?? "").toString(),
      time: date["time"]?.toString(),
      type: (json["type"] ?? "").toString(),
      // Absent means read, matching v1's parsing.
      isRead: json["isRead"] ?? true,
    );
  }
}

class NotificationSectionData {
  final List<NotificationV2> items;
  final int total;
  final int unread;
  final bool hasNext;

  const NotificationSectionData({
    required this.items,
    required this.total,
    required this.unread,
    required this.hasNext,
  });

  static const empty =
      NotificationSectionData(items: [], total: 0, unread: 0, hasNext: false);

  factory NotificationSectionData.fromJson(dynamic data) {
    if (data is! Map) return empty;
    final raw = data["items"];
    return NotificationSectionData(
      items: raw is List
          ? raw
              .whereType<Map>()
              .map((item) =>
                  NotificationV2.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
      total: data["total"] is num ? (data["total"] as num).toInt() : 0,
      unread: data["unread"] is num ? (data["unread"] as num).toInt() : 0,
      hasNext: data["next"] == true,
    );
  }
}

class NotificationsOverviewV2 {
  final NotificationSectionData activity;
  final NotificationSectionData connections;
  final NotificationSectionData system;

  const NotificationsOverviewV2({
    required this.activity,
    required this.connections,
    required this.system,
  });

  NotificationSectionData section(NotificationSection section) =>
      switch (section) {
        NotificationSection.activity => activity,
        NotificationSection.connections => connections,
        NotificationSection.system => system,
      };

  factory NotificationsOverviewV2.fromJson(Map<String, dynamic> json) {
    return NotificationsOverviewV2(
      activity: NotificationSectionData.fromJson(json["activity"]),
      connections: NotificationSectionData.fromJson(json["connections"]),
      system: NotificationSectionData.fromJson(json["system"]),
    );
  }
}
