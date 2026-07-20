// ─── THE PUSH PAYLOAD CONTRACT ───────────────────────────────────────────────
//
// This file is the single source of truth for what the backend must send. If
// a field name changes, it changes here first and the server follows.
//
// Everything the tray renders comes from the FCM `data` block - deliberately
// NOT from `notification`. When a push carries a `notification` block and the
// app is backgrounded, Android renders it itself and our Dart never runs,
// which caps the display at title + body + icon. The threaded, Messenger-style
// tray (per-sender avatars, "3 new messages" stacked in one row, per-chat
// grouping) can only be built by the app, and that only happens for data-only
// messages. So: for chat messages, send NO `notification` block.
//
//   {
//     "data": {
//       "type":             "message",
//       "conversationId":   "CNV_xxxxxxxx",
//       "conversationName": "Design Team",    // group name, or the other user
//       "isGroup":          "false",
//       "senderId":         "ENT_xxxxxxxx",
//       "senderName":       "@paulo",
//       "senderAvatarUrl":  "https://.../avatar.jpg",  // optional
//       "body":             "see you at 5",
//       "sentAt":           "1721557200000",  // ms since epoch
//       "messageId":        "MSG_xxxxxxxx"    // optional
//     },
//     "android": { "priority": "high" }
//   }
//
// Two hard requirements on the sender side:
//
//  1. EVERY `data` value must be a STRING. FCM rejects numbers, booleans and
//     nulls outright - the whole send fails, not just the offending field.
//     That's why `isGroup` and `sentAt` are quoted above.
//  2. `android.priority` must be `"high"`. Normal-priority data messages get
//     batched by Doze and can land minutes late, which for a chat notification
//     reads as "push is broken".
//
// ─── The second shape: everything else ───────────────────────────────────────
//
// Any `type` other than "message" renders as a plain title/body notification on
// a separate, quieter "Activity" channel - one generic shape that covers every
// non-message notification the backend has (contact requests, accepts, pokes,
// reactions, comments, mentions, and anything added later) without needing a
// mobile release per type:
//
//   {
//     "data": {
//       "type":  "contact_request",       // free-form; only "message" is special
//       "title": "Contact Request",
//       "body":  "@paulo sent you a contact request.",
//       "route": "/user/paulo"            // optional deep link, see below
//     },
//     "android": { "priority": "high" }
//   }
//
// `route` is optional. Omitted, a tap opens the notifications screen, which is
// the right destination for almost everything. Set it to deep-link somewhere
// specific instead. Only these prefixes are honoured - anything else falls back
// to the notifications screen rather than navigating somewhere unexpected:
//
//   /conversation/:id   /user/:username   /realm/:slug
//   /notifications      /profile          /settings
//
// The separate channel matters: Android exposes channels individually in system
// settings, so a user can silence activity notifications while keeping messages
// loud. Putting both on one channel takes that choice away.
//
// Parsing here is deliberately total - every field has a fallback and nothing
// throws. This runs in the background isolate, where an exception means no
// notification is shown at all and there is no UI to report it.

/// A parsed FCM `data` block. Construct with [PushPayload.fromData].
class PushPayload {
  const PushPayload({
    required this.type,
    required this.body,
    required this.sentAt,
    this.title,
    this.conversationId,
    this.conversationName,
    this.isGroup = false,
    this.senderId,
    this.senderName,
    this.senderAvatarUrl,
    this.messageId,
    this.route,
  });

  /// Routes which tray layout is used. "message" gets the threaded
  /// MessagingStyle treatment; anything else falls back to title + body.
  final String type;

  /// Message text, or the notification body for non-message types.
  final String body;

  /// When the message was sent. Drives the per-message timestamps Android
  /// shows inside a threaded notification, so it must be the SENT time, not
  /// receive time - otherwise a burst of queued pushes all show "now".
  final DateTime sentAt;

  /// Only used by non-message types; message notifications derive their title
  /// from [conversationName] / [senderName].
  final String? title;

  final String? conversationId;
  final String? conversationName;
  final bool isGroup;
  final String? senderId;
  final String? senderName;
  final String? senderAvatarUrl;
  final String? messageId;

  /// Optional deep link for non-message notifications. Validated against an
  /// allowlist before use - see [allowedRoutePrefixes].
  final String? route;

  /// Route prefixes a push is permitted to navigate to. Anything else is
  /// ignored in favour of the notifications screen: pushes are trusted (only
  /// our own backend can send to this Firebase project), but a typo'd or
  /// stale route should land somewhere sensible rather than on a broken
  /// screen or a redirect loop.
  static const List<String> allowedRoutePrefixes = <String>[
    '/conversation/',
    '/user/',
    '/realm/',
    '/notifications',
    '/profile',
    '/settings',
  ];

  /// [route] if it's one we recognise, otherwise null.
  String? get safeRoute {
    final value = route;
    if (value == null || !value.startsWith('/')) return null;
    final matches = allowedRoutePrefixes.any(value.startsWith);
    return matches ? value : null;
  }

  /// True when this payload has everything the threaded renderer needs.
  bool get isMessage =>
      type == 'message' &&
      conversationId != null &&
      conversationId!.isNotEmpty;

  static PushPayload fromData(Map<String, dynamic> data) {
    String? str(String key) {
      final value = data[key];
      if (value == null) return null;
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    // The backend sends ms-since-epoch as a string. Anything unparseable
    // becomes "now" rather than 1970, which would sort the message to the
    // bottom of the thread and show a nonsense timestamp.
    DateTime parseSentAt() {
      final raw = str('sentAt');
      final ms = raw == null ? null : int.tryParse(raw);
      if (ms == null) return DateTime.now();
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }

    return PushPayload(
      type: str('type') ?? 'message',
      body: str('body') ?? str('message') ?? '',
      sentAt: parseSentAt(),
      title: str('title'),
      // conversationID (capital D) is accepted too - the Node codebase uses
      // that casing throughout, so allowing both avoids a silent no-op if a
      // send site copies the field name from a Mongo document.
      conversationId: str('conversationId') ?? str('conversationID'),
      conversationName: str('conversationName'),
      isGroup: (str('isGroup') ?? 'false').toLowerCase() == 'true',
      senderId: str('senderId'),
      senderName: str('senderName'),
      senderAvatarUrl: str('senderAvatarUrl'),
      messageId: str('messageId'),
      route: str('route'),
    );
  }
}
