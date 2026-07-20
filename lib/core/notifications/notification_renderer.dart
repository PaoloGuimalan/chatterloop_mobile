import 'dart:convert';
import 'dart:io';

import 'package:chatterloop_app/core/notifications/notification_thread_store.dart';
import 'package:chatterloop_app/core/notifications/push_payload.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Builds what the user actually sees in the notification tray.
///
/// Shared by BOTH entry points on purpose - the foreground listener in
/// [PushNotificationService] and the background isolate handler in main.dart -
/// so a message looks identical whether the app was open, backgrounded or
/// killed when it arrived.
///
/// Everything here has to survive running in the background isolate, which is
/// spawned fresh per push and shares nothing with the UI isolate: no Redux
/// store, no router, no already-initialized plugins, no warm caches. Hence the
/// lazy [_ensureInitialized], the on-disk thread store, and the total absence
/// of anything that could throw - an uncaught exception in that isolate means
/// no notification at all, with no UI anywhere to report the failure.
class NotificationRenderer {
  const NotificationRenderer._();

  /// Must stay in lockstep with the `default_notification_channel_id`
  /// meta-data in AndroidManifest.xml. If the backend ever does send a
  /// `notification`-block push, the OS posts it to the manifest's channel -
  /// a mismatch would split chat notifications across two channels with
  /// separate user-visible settings.
  static const String channelId = 'chatterloop_messages';
  static const String channelName = 'Messages';
  static const String channelDescription = 'New message and chat notifications';

  /// Everything that isn't a chat message - contact requests, accepts, pokes,
  /// reactions, comments, mentions - shares one quieter channel.
  ///
  /// Kept separate from messages on purpose: Android surfaces channels
  /// individually in system settings, so this lets someone silence activity
  /// while keeping messages loud. One combined channel would take that choice
  /// away, and the usual result is people muting the app entirely.
  static const String activityChannelId = 'chatterloop_activity';
  static const String activityChannelName = 'Activity';
  static const String activityChannelDescription =
      'Contact requests, reactions, mentions and other activity';

  /// Collapses every chat notification under a single tray header instead of
  /// letting them scatter as unrelated rows. Activity gets its own so the two
  /// kinds don't interleave.
  static const String _groupKey = 'chatterloop_conversations';
  static const String _activityGroupKey = 'chatterloop_activity';

  /// Monochrome status-bar icon. A full-colour launcher icon renders as a
  /// white blob here - Android masks the small icon to its alpha channel.
  static const String _smallIcon = '@drawable/ic_stat_chatterloop';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Lets the UI isolate claim initialization.
  ///
  /// [FlutterLocalNotificationsPlugin] is a singleton, so the instance here and
  /// the one in [PushNotificationService] are the same object - and a second
  /// initialize() silently replaces the tap callback registered by the first.
  /// The service initializes WITH a callback (it owns the router); this lets it
  /// say so, instead of having [_ensureInitialized] wipe that callback the
  /// first time a foreground message is rendered.
  static void markInitialized() => _initialized = true;

  /// Android notification ids are Java ints, so the raw Dart hashCode (64-bit,
  /// possibly negative) can't be used directly. Masking to 31 bits keeps it
  /// positive and in range while staying stable for a given conversation -
  /// which is what makes a second message UPDATE the existing tray row
  /// instead of stacking a duplicate beneath it.
  static int notificationIdFor(String conversationId) =>
      conversationId.hashCode & 0x7fffffff;

  /// Entry point. [data] is the raw FCM `data` map.
  static Future<void> render(Map<String, dynamic> data) async {
    try {
      final payload = PushPayload.fromData(data);
      await _ensureInitialized();
      if (payload.isMessage) {
        await _renderMessage(payload, data);
      } else {
        await _renderGeneric(payload, data);
      }
    } catch (e) {
      // Swallow: a failed render must never take down the isolate.
      if (kDebugMode) debugPrint('[FCM] render failed: $e');
    }
  }

  /// Clears a conversation's tray row and its stored thread. Call when the
  /// user opens that conversation - otherwise the next push redraws messages
  /// they've already read.
  static Future<void> dismissConversation(String conversationId) async {
    try {
      await NotificationThreadStore.clear(conversationId);
      await _plugin.cancel(notificationIdFor(conversationId));
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] dismiss failed: $e');
    }
  }

  /// Wipes every chat notification and stored thread. For logout/account
  /// switch, so the next account can't see the previous one's messages.
  static Future<void> dismissAll() async {
    try {
      await NotificationThreadStore.clearAll();
      await _plugin.cancelAll();
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] dismissAll failed: $e');
    }
  }

  /// The threaded, Messenger-style layout: one tray row per conversation,
  /// each showing the recent messages with their sender's name and avatar.
  static Future<void> _renderMessage(
    PushPayload payload,
    Map<String, dynamic> raw,
  ) async {
    final conversationId = payload.conversationId!;
    final senderName =
        payload.senderName ?? payload.conversationName ?? payload.title ?? '';

    final thread = await NotificationThreadStore.append(
      conversationId,
      ThreadEntry(
        text: payload.body,
        senderName: senderName,
        sentAt: payload.sentAt,
        avatarUrl: payload.senderAvatarUrl,
      ),
    );

    // One fetch per distinct avatar, not per message - a busy group thread
    // would otherwise re-download the same handful of images every push.
    final avatarUrls = thread
        .map((e) => e.avatarUrl)
        .whereType<String>()
        .toSet();
    final avatars = <String, ByteArrayAndroidIcon>{};
    for (final url in avatarUrls) {
      final icon = await _avatarIcon(url);
      if (icon != null) avatars[url] = icon;
    }

    final messages = thread
        .map(
          (entry) => Message(
            entry.text,
            entry.sentAt,
            Person(
              name: entry.senderName,
              // Android uses key (not name) to decide whether two messages
              // came from the same person, so it must be stable and unique.
              key: entry.senderName,
              icon: entry.avatarUrl == null ? null : avatars[entry.avatarUrl],
            ),
          ),
        )
        .toList();

    final style = MessagingStyleInformation(
      // The "you" persona. Only used for messages with a null person, which
      // we never send - but MessagingStyle requires it.
      const Person(name: 'You', key: 'self'),
      // Android renders this as the header. For a 1:1 chat it's redundant
      // with the sender's own name, so it's left off there.
      conversationTitle: payload.isGroup ? payload.conversationName : null,
      groupConversation: payload.isGroup,
      messages: messages,
    );

    await _plugin.show(
      notificationIdFor(conversationId),
      // MessagingStyle supplies its own text on Android, but these are the
      // fallback if the style can't be applied - worth keeping sensible.
      payload.conversationName ?? senderName,
      payload.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: _smallIcon,
          groupKey: _groupKey,
          styleInformation: style,
          category: AndroidNotificationCategory.message,
          when: payload.sentAt.millisecondsSinceEpoch,
        ),
      ),
      payload: jsonEncode(raw),
    );
  }

  /// The catch-all layout: one shape for every non-message notification the
  /// backend has now or adds later. Plain title + body, expandable if the body
  /// is long, on the quieter Activity channel.
  ///
  /// Deliberately generic - it reads only `title`, `body` and the optional
  /// `route`, never the `type`. That means a brand-new notification type on the
  /// server displays and deep-links correctly with no mobile release.
  static Future<void> _renderGeneric(
    PushPayload payload,
    Map<String, dynamic> raw,
  ) async {
    if (payload.title == null && payload.body.isEmpty) return;

    await _plugin.show(
      // No stable per-thread identity here, so these get a rotating id and
      // stack as separate rows rather than replacing one another - two contact
      // requests are two things to act on, unlike two messages in one chat.
      DateTime.now().millisecondsSinceEpoch.remainder(0x7fffffff),
      payload.title ?? 'Chatterloop',
      payload.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          activityChannelId,
          activityChannelName,
          channelDescription: activityChannelDescription,
          // Default rather than high: these are worth seeing, not worth
          // interrupting for with a heads-up banner over whatever's on screen.
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: _smallIcon,
          groupKey: _activityGroupKey,
          // Lets a longer body expand instead of being ellipsised on one line.
          styleInformation: BigTextStyleInformation(payload.body),
        ),
      ),
      payload: jsonEncode(raw),
    );
  }

  /// The plugin is per-isolate, and the background isolate starts cold on
  /// every push - so this can't be done once at app start.
  ///
  /// No tap callback is registered here: taps are handled in the UI isolate by
  /// [PushNotificationService], which owns the router.
  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings(_smallIcon),
      ),
    );

    await createChannels(_plugin);
  }

  /// Registers both channels. Creating a channel is idempotent, but its
  /// importance is only honoured on FIRST creation - Android deliberately
  /// ignores later changes so an app can't undo a user's own settings.
  ///
  /// Exposed so [PushNotificationService] can call it from the UI isolate: it
  /// initializes the (singleton) plugin itself and therefore skips
  /// [_ensureInitialized] entirely.
  static Future<void> createChannels(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: Importance.high,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        activityChannelId,
        activityChannelName,
        description: activityChannelDescription,
        importance: Importance.defaultImportance,
      ),
    );
  }

  /// Downloads an avatar, caching it in the temp dir so repeat pushes from the
  /// same person don't re-fetch. Returns null on any failure - a missing
  /// avatar degrades to Android's initial-letter placeholder, which is far
  /// better than a slow or broken CDN delaying the notification itself.
  static Future<ByteArrayAndroidIcon?> _avatarIcon(String url) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/push_avatar_${url.hashCode}.img');

      if (file.existsSync()) {
        final cached = await file.readAsBytes();
        if (cached.isNotEmpty) return ByteArrayAndroidIcon(cached);
      }

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;

      final Uint8List bytes = response.bodyBytes;
      await file.writeAsBytes(bytes, flush: true);
      return ByteArrayAndroidIcon(bytes);
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] avatar fetch failed: $e');
      return null;
    }
  }
}
