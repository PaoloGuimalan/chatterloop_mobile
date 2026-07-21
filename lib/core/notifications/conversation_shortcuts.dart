import 'package:chatterloop_app/core/notifications/notification_renderer.dart';
import 'package:chatterloop_app/models/messages_models/messages_list_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Publishes Android conversation shortcuts for the user's recent chats.
///
/// These exist purely so message notifications qualify for Android's
/// Conversation treatment (API 30+): the sender's avatar shown large, the app
/// icon badged on it in colour, and a dedicated section at the top of the
/// shade. Android grants that only when a long-lived shortcut with a Person
/// exists AND the notification's shortcutId points at it - see
/// NotificationRenderer, which sets the matching shortcutId.
///
/// Called after the conversation list loads, which is both when the data is
/// available and often enough to stay current. The native side replaces the
/// whole set per call, so this is idempotent and needs no diffing.
class ConversationShortcuts {
  const ConversationShortcuts._();

  static const MethodChannel _channel =
      MethodChannel('chatterloop/conversation_shortcuts');

  /// Android's conversation surface shows only a handful, and each one costs
  /// an avatar fetch, so there's no point publishing the whole list.
  static const int _maxShortcuts = 8;

  /// Publishes shortcuts for the most recent conversations in [conversations].
  ///
  /// Best-effort throughout: this is a cosmetic upgrade to notifications, so
  /// no failure here should ever surface to the user or block list rendering.
  /// Silently no-ops on non-Android platforms.
  static Future<void> sync(List<MessageItem> conversations) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      final payload = <Map<String, String?>>[];

      for (final convo in conversations.take(_maxShortcuts)) {
        final id = convo.conversationID;
        if (id.isEmpty) continue;

        final details = convo.details;
        final label = details.displayName.isNotEmpty
            ? details.displayName
            : (details.username.isNotEmpty ? details.username : 'Chat');

        // Reuses NotificationRenderer's cache, so a conversation whose avatar
        // a notification already fetched costs nothing here.
        final profile = details.profile;
        final file = (profile == null || profile.isEmpty || profile == 'none')
            ? null
            : await NotificationRenderer.avatarFile(profile);

        payload.add({'id': id, 'label': label, 'iconPath': file?.path});
      }

      if (payload.isEmpty) return;
      await _channel.invokeMethod<bool>('sync', {'conversations': payload});
    } catch (e) {
      if (kDebugMode) debugPrint('[shortcuts] sync failed: $e');
    }
  }

  /// Drops every shortcut. Called on logout so the next account can't see the
  /// previous one's contacts in the launcher's long-press menu or the shade's
  /// conversation section.
  static Future<void> clearAll() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<bool>('clearAll');
    } catch (e) {
      if (kDebugMode) debugPrint('[shortcuts] clearAll failed: $e');
    }
  }
}
