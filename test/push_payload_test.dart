// The push contract the backend codes against (push_payload.dart documents it,
// server/reusables/hooks/pushnotification.js sends it).
//
// These are cheap but not trivial: the server deliberately ships new alert
// types WITHOUT a mobile release, on the promise that anything that isn't
// "message" renders generically from title/body and deep-links via an
// allowlisted route. The mention push added to sendMessage relies on exactly
// that promise, so it's worth a test rather than a reading of the comments.

import 'package:chatterloop_app/core/notifications/push_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mention push', () {
    // Exactly what routes/users/index.js now sends for an @mentioned receiver.
    Map<String, dynamic> mentionData() => <String, dynamic>{
          'type': 'mention',
          'title': 'Design Team',
          'body': '@paulo mentioned you: standup in 5',
          'route': '/conversation/CNV_abc123',
          'senderAvatarUrl': 'https://cdn.example.com/paulo.jpg',
        };

    test('renders as activity, not as a threaded message', () {
      final payload = PushPayload.fromData(mentionData());
      // isMessage drives which renderer runs - and with it the channel, and
      // with the channel the SOUND. False here is what puts a mention on the
      // Activity channel's notification_alert tone rather than the Messages
      // channel's message_alert.
      expect(payload.isMessage, isFalse);
      expect(payload.type, 'mention');
      expect(payload.title, 'Design Team');
      expect(payload.body, '@paulo mentioned you: standup in 5');
      expect(payload.senderAvatarUrl, 'https://cdn.example.com/paulo.jpg');
    });

    test('deep-links to the conversation it happened in', () {
      final payload = PushPayload.fromData(mentionData());
      expect(payload.safeRoute, '/conversation/CNV_abc123');
    });

    test('a bad route falls back rather than navigating somewhere odd', () {
      final payload = PushPayload.fromData(
        mentionData()..['route'] = '/definitely-not-a-screen/CNV_abc123',
      );
      expect(payload.safeRoute, isNull);
    });

    test('type alone never makes something a message push', () {
      // Guards the other direction: "message" without a conversationId can't
      // reach the threaded renderer, which would throw for want of a thread.
      final payload = PushPayload.fromData(<String, dynamic>{
        'type': 'message',
        'body': 'orphaned',
      });
      expect(payload.isMessage, isFalse);
    });
  });
}
