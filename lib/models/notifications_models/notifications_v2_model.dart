// Notifications v2 shapes - the redesigned Notifications screen's data.
// Mirror webapp's INotificationV2 / NotificationSectionData, which mirror the
// Node /u/v2/notifications/* routes exactly.
//
// Distinct from NotificationsItemModel (v1, notifications_item_model.dart):
// v1's `fromUser` is a raw user_account row (username/gender/is_active) and
// is null outright for page senders, while v2 resolves the sender through
// entity_entity so a page gets a real identity too. v1 stays in place for the
// topbar badge + SSE flow, so both shapes coexist deliberately.

import 'dart:io' show Platform;

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

/// This build's platform key, as the server addresses it.
///
/// The server writes one `redirects`/`actions` entry PER PLATFORM because the
/// three clients do not share a route table (`/messages/:id` on web vs
/// `/conversation/:id` here). Android and iOS are addressed separately even
/// though this app currently resolves both to the same routes - the split is
/// the server's, and it exists so iOS can diverge later without a data change.
String get kNotificationPlatform => Platform.isIOS ? 'ios' : 'android';

/// Where tapping the row goes, for one platform.
class NotificationRedirect {
  final String platform;

  /// "post" | "profile" | "conversation" | "realm" | "server" | "external".
  /// Only "external" changes behaviour here - it opens outside the app.
  final String type;

  /// In-app path, or an absolute URL when [type] is "external". Empty means
  /// this platform has no destination, and the row must not be tappable.
  final String route;

  const NotificationRedirect({
    required this.platform,
    required this.type,
    required this.route,
  });

  bool get isExternal => type == 'external';

  factory NotificationRedirect.fromJson(Map<String, dynamic> json) =>
      NotificationRedirect(
        platform: (json['platform'] ?? '').toString(),
        type: (json['type'] ?? '').toString(),
        route: (json['route'] ?? '').toString(),
      );
}

/// One button on the notification, for one platform.
///
/// The same logical button is repeated per platform sharing an [id]; gating an
/// action to some platforms is simply the absence of the others' entries.
class NotificationAction {
  final String platform;
  final String id;
  final String name;

  /// "api-request" | "in-app-redirect" | "external-redirect" |
  /// "external-api-request".
  final String type;

  /// "primary" | "secondary" | "danger" - a presentation hint.
  final String style;
  final int order;

  /// "dismiss" | "refresh" | "none" - what the list does after it succeeds.
  final String after;

  final String route;
  final String url;

  /// Which API base [url] resolves against: "user" (Django) or "realtime"
  /// (Node). A path alone cannot say, and the app talks to both.
  final String service;

  final String method;
  final Map<String, dynamic>? payload;
  final Map<String, dynamic>? headers;

  const NotificationAction({
    required this.platform,
    required this.id,
    required this.name,
    required this.type,
    required this.style,
    required this.order,
    required this.after,
    required this.route,
    required this.url,
    required this.service,
    required this.method,
    this.payload,
    this.headers,
  });

  factory NotificationAction.fromJson(Map<String, dynamic> json) =>
      NotificationAction(
        platform: (json['platform'] ?? '').toString(),
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        type: (json['type'] ?? '').toString(),
        style: (json['style'] ?? 'secondary').toString(),
        order: json['order'] is num ? (json['order'] as num).toInt() : 0,
        after: (json['after'] ?? 'refresh').toString(),
        route: (json['route'] ?? '').toString(),
        url: (json['url'] ?? '').toString(),
        service: (json['service'] ?? 'user').toString(),
        method: (json['method'] ?? '').toString(),
        payload: json['payload'] is Map
            ? Map<String, dynamic>.from(json['payload'])
            : null,
        headers: json['headers'] is Map
            ? Map<String, dynamic>.from(json['headers'])
            : null,
      );
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

  /// Server-driven destination and buttons, ALREADY filtered to this platform
  /// at parse time - see fromJson. Empty when the server sent none (an older
  /// server, or a type with no mapping), which is what keeps the legacy
  /// [isActionable] path working underneath.
  final List<NotificationRedirect> redirects;
  final List<NotificationAction> actions;

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
    this.redirects = const [],
    this.actions = const [],
  });

  /// This platform's destination, or null when there is none - in which case
  /// the row must not be tappable rather than tapping to nowhere.
  NotificationRedirect? get redirect {
    for (final r in redirects) {
      if (r.route.isNotEmpty) return r;
    }
    return null;
  }

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
        redirects: redirects,
        actions: actions,
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
      // Filtered to THIS platform here, once, so nothing downstream has to
      // remember to - a widget that forgot would render another platform's
      // buttons, and a route from the wrong route table goes nowhere.
      //
      // Actions are sorted by `order` because the server sends one flat array
      // grouped by button rather than by platform, so insertion order is not
      // render order.
      redirects: _parsePlatformList(
          json["redirects"], NotificationRedirect.fromJson, (r) => r.platform),
      actions: () {
        final parsed = _parsePlatformList(
            json["actions"], NotificationAction.fromJson, (a) => a.platform);
        parsed.sort((a, b) => a.order.compareTo(b.order));
        return parsed;
      }(),
    );
  }
}

/// Parses a server array and keeps only the entries addressed to this platform.
List<T> _parsePlatformList<T>(
  dynamic raw,
  T Function(Map<String, dynamic>) parse,
  String Function(T) platformOf,
) {
  // A GROWABLE empty list, not `const []`: the caller sorts the result, and
  // sorting a const list throws. The absent-field case is exactly the
  // backward-compatibility path - a server that predates this feature - so it
  // would have crashed on every notification parsed from one.
  if (raw is! List) return <T>[];
  final platform = kNotificationPlatform;
  return raw
      .whereType<Map>()
      .map((item) => parse(Map<String, dynamic>.from(item)))
      .where((item) => platformOf(item) == platform)
      .toList();
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
