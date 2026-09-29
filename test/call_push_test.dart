// The call push contract (push_payload.dart's third shape): what
// server/reusables/hooks/pushnotification.js sends for a ring and a missed
// call, and the ring window the phone enforces on its own - the server keeps
// no timer, so if that math is wrong a ring either gets stuck or never rings.

import 'dart:convert';

import 'package:chatterloop_app/core/notifications/notification_renderer.dart';
import 'package:chatterloop_app/core/notifications/push_payload.dart';
import 'package:chatterloop_app/models/call_models/incoming_call_alert_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Exactly what sendCall publishes for a group video call.
  Map<String, dynamic> ringData({String? sentAt}) => <String, dynamic>{
        'type': 'call',
        'conversationID': 'CNV_abc123',
        'conversationType': 'group',
        'callType': 'video',
        'callDisplayName': 'Design Team (Group)',
        'callerName': 'Paulo',
        'callerEntityID': 'ENT_caller',
        'recepients': jsonEncode(['ENT_a', 'ENT_b']),
        'displayImage': 'https://cdn.example.com/group.jpg',
        'title': 'Design Team (Group)',
        'body': 'Paulo is calling · video call',
        'sentAt': sentAt ?? '1721557200000',
      };

  group('ring push', () {
    test('unflattens into the same alert the SSE carries', () {
      final alert = IncomingCallAlert.fromPushData(ringData());
      expect(alert.conversationID, 'CNV_abc123');
      expect(alert.isGroup, isTrue);
      expect(alert.callType, 'video');
      expect(alert.caller.name, 'Paulo');
      expect(alert.caller.entityId, 'ENT_caller');
      expect(alert.recepients, ['ENT_a', 'ENT_b']);
      expect(alert.displayImage, 'https://cdn.example.com/group.jpg');
      // The ring's identity - what a Decline marker is matched against.
      expect(alert.ringStartedAt, '1721557200000');
    });

    test('an SSE alert re-flattens to what a push would have carried', () {
      // Background SSE path: the app draws the ring from toPushData, so a
      // round trip must not lose anything the notification or Join needs.
      final original = IncomingCallAlert.fromPushData(ringData());
      final again = IncomingCallAlert.fromPushData(original.toPushData());
      expect(again.conversationID, original.conversationID);
      expect(again.conversationType, original.conversationType);
      expect(again.callType, original.callType);
      expect(again.caller.entityId, original.caller.entityId);
      expect(again.recepients, original.recepients);
      expect(again.ringStartedAt, original.ringStartedAt);
    });

    test('malformed recepients degrade to none rather than throwing', () {
      // This runs in the background isolate; a throw there is no ring at all.
      final alert = IncomingCallAlert.fromPushData(
          ringData()..['recepients'] = 'not json');
      expect(alert.recepients, isEmpty);
    });

    test('is never mistaken for a chat message', () {
      expect(PushPayload.fromData(ringData()).isMessage, isFalse);
    });
  });

  group('ring window', () {
    const window = NotificationRenderer.callRingWindow;
    String ago(Duration d) =>
        DateTime.now().subtract(d).millisecondsSinceEpoch.toString();

    test('a push that sat in FCM rings only for what is left', () {
      final left =
          NotificationRenderer.ringTimeLeft(ago(const Duration(seconds: 20)));
      expect(left.inSeconds, inInclusiveRange(24, 25));
    });

    test('a phone clock running behind still rings the full window', () {
      // sentAt in this phone's future - only a skewed clock does that.
      final ahead = DateTime.now()
          .add(const Duration(minutes: 3))
          .millisecondsSinceEpoch
          .toString();
      expect(NotificationRenderer.ringTimeLeft(ahead), window);
    });

    test('an age FCM cannot produce is skew too, and does not silence it', () {
      // FCM drops a ring after 30s, so "10 minutes old" means the clock is off.
      expect(
          NotificationRenderer.ringTimeLeft(ago(const Duration(minutes: 10))),
          window);
    });

    test('no stamp at all rings the full window', () {
      expect(NotificationRenderer.ringTimeLeft(null), window);
      expect(NotificationRenderer.ringTimeLeft('garbage'), window);
    });

    test('ring and missed call use different tray rows', () {
      // Cancelling a ring must never take a missed call down with it.
      expect(NotificationRenderer.callRingId('CNV_abc123'),
          isNot(NotificationRenderer.missedCallId('CNV_abc123')));
    });
  });

  group('tap destinations', () {
    test('a missed call opens its conversation', () {
      final payload = PushPayload.fromData(<String, dynamic>{
        'type': 'call_missed',
        'conversationID': 'CNV_abc123',
        'title': 'Design Team (Group)',
        'body': 'Missed video call from Paulo',
        'route': '/conversation/CNV_abc123',
        'ringStartedAt': '1721557200000',
      });
      expect(payload.isMessage, isFalse);
      expect(payload.safeRoute, '/conversation/CNV_abc123');
    });

    test('a voice channel join opens its server', () {
      final payload = PushPayload.fromData(<String, dynamic>{
        'type': 'voice_join',
        'title': 'lounge · Design Server',
        'body': '@paulo joined the voice channel.',
        'route': '/server/RLM_abc?name=Design%20Server',
      });
      expect(payload.safeRoute, '/server/RLM_abc?name=Design%20Server');
    });

    test('the servers TAB is not a server deep link', () {
      // '/server/' must not be loosened to '/server', which would also
      // admit '/servers' and '/server-browser'.
      final payload = PushPayload.fromData(<String, dynamic>{
        'type': 'voice_join',
        'route': '/server-browser',
      });
      expect(payload.safeRoute, isNull);
    });
  });
}
