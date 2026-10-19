import 'dart:convert';

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
/// whole set per call. Unchanged sets are skipped and calls are serialized.
class ConversationShortcuts {
  const ConversationShortcuts._();

  static const MethodChannel _channel =
      MethodChannel('chatterloop/conversation_shortcuts');

  /// Android's conversation surface shows only a handful, and each one costs
  /// an avatar fetch, so there's no point publishing the whole list.
  static const int _maxShortcuts = 8;
  static Future<void> _queue = Future<void>.value();
  static String? _lastSynced;
  static int _generation = 0;

  /// Publishes shortcuts for the most recent conversations in [conversations].
  ///
  /// Best-effort throughout: this is a cosmetic upgrade to notifications, so
  /// no failure here should ever surface to the user or block list rendering.
  /// Silently no-ops on non-Android platforms.
  static Future<void> sync(List<MessageItem> conversations) {
    if (defaultTargetPlatform != TargetPlatform.android) return Future.value();
    final generation = _generation;
    final items = conversations
        .take(_maxShortcuts)
        .where((c) => c.conversationID.isNotEmpty)
        .map((convo) => (
              id: convo.conversationID,
              label: convo.details.displayName.isNotEmpty
                  ? convo.details.displayName
                  : (convo.details.username.isNotEmpty
                      ? convo.details.username
                      : 'Chat'),
              profile: convo.details.profile,
            ))
        .toList();
    final signature = jsonEncode([
      for (final item in items) [item.id, item.label, item.profile]
    ]);
    _queue = _queue.then((_) async {
      if (generation != _generation || signature == _lastSynced) return;
      final payload = <Map<String, String?>>[];
      var complete = true;
      for (final item in items) {
        if (generation != _generation) return;
        final profile = item.profile;
        final file = (profile == null || profile.isEmpty || profile == 'none')
            ? null
            : await NotificationRenderer.avatarFile(profile);
        if (profile != null &&
            profile.isNotEmpty &&
            profile != 'none' &&
            file == null) {
          complete = false; // Retry a missing avatar on the next refresh.
        }
        payload
            .add({'id': item.id, 'label': item.label, 'iconPath': file?.path});
      }
      if (generation != _generation) return;
      final ok = payload.isEmpty
          ? await _channel.invokeMethod<bool>('clearAll')
          : await _channel
              .invokeMethod<bool>('sync', {'conversations': payload});
      if (ok == true && complete && generation == _generation) {
        _lastSynced = signature;
      }
    }).catchError((Object e) {
      if (kDebugMode) debugPrint('[shortcuts] sync failed: $e');
    });
    return _queue;
  }

  /// Drops every shortcut. Called on logout so the next account can't see the
  /// previous one's contacts in the launcher's long-press menu or the shade's
  /// conversation section.
  static Future<void> clearAll() {
    _generation++;
    _lastSynced = null;
    if (defaultTargetPlatform != TargetPlatform.android) return Future.value();
    _queue = _queue.then((_) async {
      await _channel.invokeMethod<bool>('clearAll');
    }).catchError((Object e) {
      if (kDebugMode) debugPrint('[shortcuts] clearAll failed: $e');
    });
    return _queue;
  }
}
