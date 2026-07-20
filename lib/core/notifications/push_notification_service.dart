// Mobile side of Firebase Cloud Messaging. The backend owns the SEND path
// (storing the token on the device session via the fcm-token header that
// jwtchecker reads, and calling admin.messaging() for offline devices). This
// service owns the CLIENT side:
//
//  1. Keeps the current FCM registration token cached in [fcmTokenForHeader]
//     so ApiClient's request interceptor can attach it as the `fcm-token`
//     header on every authenticated request - that header is how the token
//     gets registered/refreshed server-side (no dedicated endpoint needed).
//  2. Requests the notification permission (Android 13+ POST_NOTIFICATIONS).
//  3. Renders FOREGROUND messages, delegating to [NotificationRenderer] so
//     they look identical to the ones the background isolate draws.
//  4. Routes a notification tap to the right conversation via go_router.
//
// It deliberately makes NO API calls itself: registration is header-driven, so
// there's nothing to POST here. It just keeps the token current and handles
// display + taps.
//
// The tray LAYOUT lives in notification_renderer.dart, and the payload the
// backend must send is documented in push_payload.dart.

import 'dart:convert';

import 'package:chatterloop_app/core/notifications/fcm_token_holder.dart';
import 'package:chatterloop_app/core/notifications/notification_renderer.dart';
import 'package:chatterloop_app/core/notifications/push_payload.dart';
import 'package:chatterloop_app/core/routes/app_router.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  /// Long enough for the router and auth resolution to settle before a
  /// cold-start tap tries to navigate.
  static const Duration _coldStartNavDelay = Duration(milliseconds: 800);

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _permissionAsked = false;

  /// Call once, early, after Firebase.initializeApp() and after the router
  /// exists (so tap navigation can run). Idempotent. Does NOT prompt for
  /// permission - call [requestPermission] from a logged-in surface instead,
  /// so the one-shot Android dialog isn't burned on a cold first launch.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _initLocalNotifications();

    // Cache the token now and keep it fresh. The interceptor reads
    // fcmTokenForHeader; jwtchecker persists it on the next authed request.
    fcmTokenForHeader = await _safeGetToken();
    _fcm.onTokenRefresh.listen((token) => fcmTokenForHeader = token);

    // Foreground: nothing displays a message for us, in either payload style.
    FirebaseMessaging.onMessage.listen(_showForeground);

    // Tap while the app is backgrounded. Only fires for OS-displayed
    // (`notification`-block) pushes; taps on the notifications WE draw arrive
    // through the local-notifications callback wired up in
    // _initLocalNotifications instead.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteTap);

    await _handleColdStartTap();
  }

  /// Requests the notification permission. On Android 13+ this shows the
  /// POST_NOTIFICATIONS dialog once; on older Android it's a no-op (granted by
  /// default); on iOS it always prompts. Safe to call more than once - it only
  /// actually prompts the first time. Registration does NOT depend on this:
  /// the token is cached and sent regardless, so a denial only affects whether
  /// notifications are allowed to DISPLAY.
  Future<NotificationSettings> requestPermission() async {
    _permissionAsked = true;
    return _fcm.requestPermission(alert: true, badge: true, sound: true);
  }

  /// Whether [requestPermission] has already run this app session (so callers
  /// don't re-trigger it on every rebuild of a logged-in screen).
  bool get permissionAlreadyAsked => _permissionAsked;

  Future<String?> _safeGetToken() async {
    try {
      return await _fcm.getToken();
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] getToken failed: $e');
      return null;
    }
  }

  Future<void> _initLocalNotifications() async {
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_chatterloop'),
      ),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload != null && payload.isNotEmpty) {
          _navigateFromData(_decode(payload));
        }
      },
    );

    // Both channels up front, so they exist in system settings from first
    // launch rather than only appearing after the first notification of each
    // kind arrives.
    await NotificationRenderer.createChannels(_local);

    // The plugin is a singleton, so the renderer would otherwise re-initialize
    // it on its first foreground render and drop the tap callback above.
    NotificationRenderer.markInitialized();
  }

  /// A tap that cold-launched the app. Two separate sources, because the two
  /// payload styles are displayed by different components:
  ///
  ///  - notifications WE drew (data-only pushes, the normal case) come back
  ///    through the local-notifications plugin's launch details;
  ///  - notifications the OS drew (`notification`-block pushes) come back
  ///    through FCM's initial message.
  ///
  /// Checking only the FCM side - as this did before the renderer existed -
  /// silently drops every cold-start tap on a threaded chat notification.
  Future<void> _handleColdStartTap() async {
    try {
      final launch = await _local.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if ((launch?.didNotificationLaunchApp ?? false) &&
          payload != null &&
          payload.isNotEmpty) {
        _navigateAfterColdStart(_decode(payload));
        return;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] launch details failed: $e');
    }

    final initial = await _fcm.getInitialMessage();
    if (initial != null) _navigateAfterColdStart(initial.data);
  }

  void _navigateAfterColdStart(Map<String, dynamic> data) {
    Future.delayed(_coldStartNavDelay, () => _navigateFromData(data));
  }

  /// Foreground messages are never displayed by FCM in either payload style,
  /// so we always draw them - through the same renderer the background isolate
  /// uses, so an open app and a killed one produce an identical tray entry.
  void _showForeground(RemoteMessage message) {
    final data = Map<String, dynamic>.from(message.data);

    // Tolerate a `notification`-block push by folding its text into the data
    // map as fallbacks. Chat pushes should be data-only (see push_payload.dart)
    // but this keeps a transitional or non-conforming payload displayable
    // rather than silently dropped.
    final notification = message.notification;
    if (notification != null) {
      data.putIfAbsent('title', () => notification.title ?? '');
      data.putIfAbsent('body', () => notification.body ?? '');
    }

    if (data.isEmpty) return;
    NotificationRenderer.render(data);
  }

  void _handleRemoteTap(RemoteMessage message) =>
      _navigateFromData(message.data);

  /// Deep-links to whatever the push points at, in priority order:
  ///
  ///  1. a message push -> its conversation;
  ///  2. an explicit, allowlisted `route` -> there;
  ///  3. anything else -> the notifications screen.
  ///
  /// That last fallback is what lets the backend add new notification types
  /// without a mobile release: an unrecognised type still lands somewhere
  /// useful instead of doing nothing when tapped.
  void _navigateFromData(Map<String, dynamic> data) {
    final payload = PushPayload.fromData(data);

    if (payload.isMessage) {
      final conversationId = payload.conversationId!;
      // Opening the thread makes its tray entry stale - drop both the row and
      // the stored history so the next push starts a fresh thread.
      NotificationRenderer.dismissConversation(conversationId);
      appRouter.push('/conversation/$conversationId');
      return;
    }

    appRouter.push(payload.safeRoute ?? '/notifications');
  }

  Map<String, dynamic> _decode(String source) {
    try {
      final decoded = jsonDecode(source);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }
}
