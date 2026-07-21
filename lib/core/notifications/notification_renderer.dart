import 'dart:convert';
import 'dart:io';

import 'package:chatterloop_app/core/notifications/notification_thread_store.dart';
import 'package:chatterloop_app/core/notifications/push_payload.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
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
  /// Suffixed `_v2` because a channel's sound, importance and vibration are
  /// locked in at CREATION - Android deliberately ignores later edits so an app
  /// can't undo a user's own settings. The v1 channels already exist on every
  /// installed device with the default system sound, so giving them the
  /// Chatterloop tones requires new ids. Bump this again for any future change
  /// to a channel's sound or importance, and add the retired id to
  /// [_legacyChannelIds] so it stops cluttering the user's settings screen.
  static const String channelId = 'chatterloop_messages_v2';
  static const String channelName = 'Messages';
  static const String channelDescription = 'New message and chat notifications';

  /// res/raw/message_alert.mp3 - the same tone the webapp plays for an
  /// incoming message, so both clients sound like one product. Referenced
  /// WITHOUT its extension, which is how Android resource names work.
  static const String _messageSound = 'message_alert';

  /// res/raw/notification_alert.mp3 - the webapp's generic activity tone.
  static const String _activitySound = 'notification_alert';

  /// Channels replaced by a newer id. Deleted on startup, otherwise Android
  /// keeps showing them in the app's notification settings forever - the user
  /// would see two "Messages" entries, only one of which does anything.
  static const List<String> _legacyChannelIds = <String>[
    'chatterloop_messages',
    'chatterloop_activity',
  ];

  /// Everything that isn't a chat message - contact requests, accepts, pokes,
  /// reactions, comments, mentions - shares one quieter channel.
  ///
  /// Kept separate from messages on purpose: Android surfaces channels
  /// individually in system settings, so this lets someone silence activity
  /// while keeping messages loud. One combined channel would take that choice
  /// away, and the usual result is people muting the app entirely.
  static const String activityChannelId = 'chatterloop_activity_v2';
  static const String activityChannelName = 'Activity';
  static const String activityChannelDescription =
      'Contact requests, reactions, mentions and other activity';

  /// Collapses every chat notification under a single tray header instead of
  /// letting them scatter as unrelated rows. Activity gets its own so the two
  /// kinds don't interleave.
  static const String _groupKey = 'chatterloop_conversations';
  static const String _activityGroupKey = 'chatterloop_activity';

  /// Monochrome status-bar icon. A full-colour launcher icon renders as a
  /// white blob here - Android masks the SMALL icon to its alpha channel and
  /// repaints it flat, so no colour can ever survive in this slot.
  static const String _smallIcon = '@drawable/ic_stat_chatterloop';

  /// The LARGE icon slot, which unlike [_smallIcon] renders as a full-colour
  /// bitmap - so this is where the real logo can appear. Used for activity
  /// notifications; message notifications fill this slot with the sender's
  /// avatar instead, which is more useful there.
  static const AndroidBitmap<Object> _largeIcon =
      DrawableResourceAndroidBitmap('@mipmap/launcher_icon');

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
          // Redundant on Android 8+ (the channel's sound wins) but it's what
          // actually plays on 7 and below, where channels don't exist.
          sound: const RawResourceAndroidNotificationSound(_messageSound),
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
          largeIcon: _largeIcon,
          groupKey: _activityGroupKey,
          sound: const RawResourceAndroidNotificationSound(_activitySound),
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

    for (final legacy in _legacyChannelIds) {
      await android.deleteNotificationChannel(legacy);
    }

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound(_messageSound),
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        activityChannelId,
        activityChannelName,
        description: activityChannelDescription,
        importance: Importance.defaultImportance,
        sound: RawResourceAndroidNotificationSound(_activitySound),
      ),
    );
  }

  /// Side length of the processed avatar. Android renders the Person icon
  /// small; anything bigger is bytes over the wire and pixels thrown away.
  static const int _avatarSize = 128;

  /// Downloads an avatar, crops it to a circle, and caches the RESULT so a
  /// repeat push from the same person costs neither a fetch nor a re-crop.
  ///
  /// Returns null on any failure - a missing avatar degrades to Android's
  /// initial-letter placeholder, which is far better than a slow or broken CDN
  /// delaying the notification itself.
  static Future<ByteArrayAndroidIcon?> _avatarIcon(String url) async {
    try {
      final dir = await getTemporaryDirectory();
      // v2 in the name so avatars cached as squares by the previous build
      // aren't served back after this change.
      final file = File('${dir.path}/push_avatar_v2_${url.hashCode}.png');

      if (file.existsSync()) {
        final cached = await file.readAsBytes();
        if (cached.isNotEmpty) return ByteArrayAndroidIcon(cached);
      }

      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;

      final cropped = _circleCrop(response.bodyBytes);
      if (cropped == null) return null;

      await file.writeAsBytes(cropped, flush: true);
      return ByteArrayAndroidIcon(cropped);
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] avatar fetch failed: $e');
      return null;
    }
  }

  /// Square source bytes in, circular PNG out.
  ///
  /// The plugin hands Person icons to IconCompat.createWithBitmap, which draws
  /// the bitmap verbatim - unlike createWithAdaptiveBitmap, it applies no
  /// circular mask. So the roundness has to be baked into the pixels here, by
  /// clearing alpha outside the inscribed circle. PNG, not JPEG, because the
  /// corners must stay transparent.
  static Uint8List? _circleCrop(Uint8List source) {
    final decoded = img.decodeImage(source);
    if (decoded == null) return null;

    // Square off the longer side first, from the centre, so a non-square
    // source doesn't come out as an ellipse.
    final side =
        decoded.width < decoded.height ? decoded.width : decoded.height;
    final square = img.copyCrop(
      decoded,
      x: (decoded.width - side) ~/ 2,
      y: (decoded.height - side) ~/ 2,
      width: side,
      height: side,
    );

    final resized =
        img.copyResize(square, width: _avatarSize, height: _avatarSize);

    // Avatars are almost always JPEGs, which decode to 3 channels with no
    // alpha at all - writing alpha 0 into one silently paints black corners
    // instead of transparent ones. Force RGBA before masking.
    final rgba = resized.numChannels == 4
        ? resized
        : resized.convert(numChannels: 4, alpha: 255);

    final radius = _avatarSize / 2;
    for (var y = 0; y < _avatarSize; y++) {
      for (var x = 0; x < _avatarSize; x++) {
        final dx = x - radius + 0.5;
        final dy = y - radius + 0.5;
        if (dx * dx + dy * dy > radius * radius) {
          rgba.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
    }

    return img.encodePng(rgba);
  }
}
