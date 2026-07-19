// Mobile side of Firebase Cloud Messaging. The backend owns the SEND path
// (storing the token on the device session via the fcm-token header that
// jwtchecker reads, and calling admin.messaging() for offline devices). This
// service owns the CLIENT side:
//
//  1. Keeps the current FCM registration token cached in [cachedToken] so
//     ApiClient's request interceptor can attach it as the `fcm-token` header
//     on every authenticated request - that header is how the token gets
//     registered/refreshed server-side (no dedicated endpoint needed).
//  2. Requests the notification permission (Android 13+ POST_NOTIFICATIONS).
//  3. Displays FOREGROUND messages as a system notification - FCM only
//     auto-displays when the app is backgrounded/killed, never in foreground.
//  4. Routes a notification tap to the right conversation via go_router.
//
// It deliberately makes NO API calls itself: registration is header-driven, so
// there's nothing to POST here. It just keeps the token current and handles
// display + taps.

import 'dart:convert';

import 'package:chatterloop_app/core/notifications/fcm_token_holder.dart';
import 'package:chatterloop_app/core/routes/app_router.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  /// The message-notification channel. Its id MUST match the
  /// `default_notification_channel_id` meta-data in AndroidManifest.xml so
  /// that OS-shown (background/killed) and app-shown (foreground) notifications
  /// land in the same channel.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'chatterloop_messages',
    'Messages',
    description: 'New message and chat notifications',
    importance: Importance.high,
  );

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

    // Foreground: FCM does not display anything itself - we post it.
    FirebaseMessaging.onMessage.listen(_showForeground);

    // Tap while the app is backgrounded.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteTap);

    // Tap that cold-launched the app from a killed state. Delay so the router
    // and auth have a beat to settle before we navigate.
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      Future.delayed(
          const Duration(milliseconds: 800), () => _handleRemoteTap(initial));
    }
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
    const androidInit =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    await _local.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload != null && payload.isNotEmpty) {
          _navigateFromData(_decode(payload));
        }
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  void _showForeground(RemoteMessage message) {
    final notification = message.notification;
    // Data-only messages carry no title/body to render here; they're handled
    // by their own logic (or, in background/killed, by the OS). Nothing to
    // show for a foreground data-only message unless we choose to.
    if (notification == null) return;

    _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/launcher_icon',
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _handleRemoteTap(RemoteMessage message) =>
      _navigateFromData(message.data);

  /// Deep-links to the conversation named in the push's data payload. The
  /// backend should include `conversationId` in the FCM `data` block for
  /// message pushes; other push types can be routed here later by adding
  /// cases. No-ops if there's nothing to route to.
  void _navigateFromData(Map<String, dynamic> data) {
    final conversationId =
        (data['conversationId'] ?? data['conversationID'])?.toString();
    if (conversationId != null && conversationId.isNotEmpty) {
      appRouter.push('/conversation/$conversationId');
    }
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
