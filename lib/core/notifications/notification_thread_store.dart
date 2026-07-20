import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One previously-delivered push, kept so the tray can show a conversation as
/// a thread rather than a single line.
class ThreadEntry {
  const ThreadEntry({
    required this.text,
    required this.senderName,
    required this.sentAt,
    this.avatarUrl,
  });

  final String text;
  final String senderName;
  final DateTime sentAt;
  final String? avatarUrl;

  Map<String, dynamic> toJson() => {
        'text': text,
        'name': senderName,
        'at': sentAt.millisecondsSinceEpoch,
        'avatar': avatarUrl,
      };

  static ThreadEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text']?.toString();
    if (text == null) return null;
    return ThreadEntry(
      text: text,
      senderName: raw['name']?.toString() ?? '',
      sentAt: DateTime.fromMillisecondsSinceEpoch(
        raw['at'] is int ? raw['at'] as int : 0,
      ),
      avatarUrl: raw['avatar']?.toString(),
    );
  }
}

/// Android's MessagingStyle wants the WHOLE conversation to render a thread,
/// but FCM hands us exactly one message per push. This keeps the last few per
/// conversation on disk so each new push can redraw the full thread.
///
/// Two isolates touch this: the background isolate appends (spawned fresh per
/// push, so it always reads current data off disk), and the UI isolate clears
/// when a conversation is opened. The UI isolate is long-lived and
/// SharedPreferences caches in memory, so every read here calls reload()
/// first - without it, the app would redraw a thread from a stale in-memory
/// snapshot that predates whatever the background isolate wrote.
class NotificationThreadStore {
  const NotificationThreadStore._();

  static const String _prefix = 'push_thread_';

  /// Enough to show a real thread, few enough that the tray stays readable
  /// and the prefs entry stays small. Android itself only renders a handful.
  static const int _maxPerConversation = 8;

  static String _keyFor(String conversationId) => '$_prefix$conversationId';

  /// Appends [entry] and returns the resulting thread, oldest first.
  static Future<List<ThreadEntry>> append(
    String conversationId,
    ThreadEntry entry,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final thread = _decode(prefs.getString(_keyFor(conversationId)))
      ..add(entry);
    while (thread.length > _maxPerConversation) {
      thread.removeAt(0);
    }

    await prefs.setString(
      _keyFor(conversationId),
      jsonEncode(thread.map((e) => e.toJson()).toList()),
    );
    return thread;
  }

  /// Drops the stored thread. Call when the conversation is opened or its
  /// notification is dismissed - otherwise the next push redraws messages the
  /// user has already read, which looks like duplicate delivery.
  static Future<void> clear(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await prefs.remove(_keyFor(conversationId));
  }

  /// Clears every stored thread. Used on logout so the next account never
  /// inherits the previous one's notification history.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      await prefs.remove(key);
    }
  }

  static List<ThreadEntry> _decode(String? source) {
    if (source == null || source.isEmpty) return <ThreadEntry>[];
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return <ThreadEntry>[];
      return decoded
          .map(ThreadEntry.fromJson)
          .whereType<ThreadEntry>()
          .toList();
    } catch (_) {
      // Corrupt entry - start the thread over rather than lose the push.
      return <ThreadEntry>[];
    }
  }
}
