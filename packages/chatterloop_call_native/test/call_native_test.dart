import 'package:chatterloop_call_native/chatterloop_call_native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  void answer(Object? Function(MethodCall call) reply) {
    messenger.setMockMethodCallHandler(CallNative.channel, (call) async {
      calls.add(call);
      return reply(call);
    });
  }

  /// Delivers a call from the native side, as the platform would.
  Future<void> fromNative(String method, Map<String, Object?> args) async {
    await messenger.handlePlatformMessage(
      CallNative.channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  setUp(calls.clear);
  tearDown(() {
    messenger.setMockMethodCallHandler(CallNative.channel, null);
    debugDefaultTargetPlatformOverride = null;
    CallNative.setActionHandler(null);
    CallNative.inPip.value = false;
  });

  group('ringer', () {
    test('passes the ring to Android and reports whether it rang', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      answer((_) => true);

      final rang = await CallNative.startRinging(
        notificationId: 42,
        channelId: 'calls',
        ringFor: const Duration(seconds: 30),
        declineActionIndex: 1,
      );

      expect(rang, isTrue);
      expect(calls.single.method, 'startRinging');
      expect(calls.single.arguments, {
        'notificationId': 42,
        'channelId': 'calls',
        'timeoutMs': 30000,
        'sound': 'call_ringtone',
        'vibrationPattern': [0, 1000, 1000],
        'declineActionIndex': 1,
      });
    });

    test('is not attempted where there is no ringer', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      answer((_) => true);

      final rang = await CallNative.startRinging(
        notificationId: 1,
        channelId: 'calls',
        ringFor: const Duration(seconds: 45),
      );

      expect(rang, isFalse);
      expect(calls, isEmpty);
    });

    test('an Android refusal reads as not ringing', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      answer((_) => false);

      expect(
        await CallNative.startRinging(
          notificationId: 1,
          channelId: 'calls',
          ringFor: const Duration(seconds: 45),
        ),
        isFalse,
      );
    });
  });

  group('without the native half', () {
    test('every call quietly reports "not available"', () async {
      // No mock handler: MissingPluginException, as in a test or on web.
      expect(await CallNative.isInCall(), isFalse);
      expect(await CallNative.isPipSupported(), isFalse);
      expect(
        await CallNative.startOngoingCall(
          title: 'Call',
          text: '',
          muted: false,
          startedAt: DateTime(2026),
        ),
        isFalse,
      );
      await CallNative.stopRinging();
      await CallNative.exitPip();
    });

    test('a native error does not throw', () async {
      messenger.setMockMethodCallHandler(CallNative.channel, (_) async {
        throw PlatformException(code: 'boom');
      });
      expect(await CallNative.isInCall(), isFalse);
    });
  });

  group('from the native side', () {
    test('PiP changes reach inPip', () async {
      answer((_) => null);
      await CallNative.isInCall(); // installs the handler
      await fromNative('onPipChanged', {'inPip': true});
      expect(CallNative.inPip.value, isTrue);
      await fromNative('onPipChanged', {'inPip': false});
      expect(CallNative.inPip.value, isFalse);
    });

    test('notification buttons reach the action handler', () async {
      final actions = <CallAction>[];
      CallNative.setActionHandler(actions.add);
      await fromNative('onCallAction', {'action': 'mute'});
      await fromNative('onCallAction', {'action': 'unmute'});
      await fromNative('onCallAction', {'action': 'hangup'});
      await fromNative('onCallAction', {'action': 'stopScreenShare'});
      await fromNative('onCallAction', {'action': 'unknown'});
      expect(actions, [
        CallAction.mute,
        CallAction.unmute,
        CallAction.hangUp,
        CallAction.stopScreenShare,
      ]);
    });
  });

  test('the ongoing call carries what the notification shows', () async {
    answer((_) => true);
    final started = await CallNative.startOngoingCall(
      title: 'Call with @ana',
      text: 'Tap to return to the call',
      muted: true,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    expect(started, isTrue);
    expect(calls.single.arguments, {
      'title': 'Call with @ana',
      'text': 'Tap to return to the call',
      'muted': true,
      'startedAt': 1000,
    });
  });
}
