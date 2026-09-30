// The native side of a call - everything Dart alone cannot do:
//
//   ringer   An incoming call's ringtone and vibration, played by the app in a
//            short foreground service rather than by the notification. A
//            notification's own sound stops the moment the user opens the
//            shade, and its vibration follows the phone's "vibrate for calls"
//            setting; the ringer does neither.
//   ongoing  The "in a call" notification, a microphone foreground service
//            that keeps the call alive and the mic open with the app in the
//            background, with Mute and Hang up.
//   pip      Picture-in-picture for video calls.
//   screen   Screen sharing's Android side: the ongoing-call service takes on
//            the media projection Android requires (wired through a
//            flutter_webrtc patch - see CallScreenShare.kt), and its
//            notification offers Stop sharing.
//
// Every method is safe to call anywhere: on a platform or build without the
// native half (tests, web, an older iOS) it quietly does nothing and reports
// "not available", so callers never have to guard.
//
// Android implements all three. iOS implements the same contract with what it
// can safely do today - it has no app-played ringer without CallKit, and PiP
// for a WebRTC call needs native frame rendering - and says so through
// [CallNative.ringerSupported] and [CallNative.isPipSupported].
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What a user did on a notification or PiP control, for the Dart side that
/// runs the call. [stopScreenShare] also arrives when screen capture ends from
/// outside the app - the system's own stop control.
enum CallAction { hangUp, mute, unmute, stopScreenShare }

class CallNative {
  CallNative._();

  @visibleForTesting
  static const MethodChannel channel = MethodChannel('chatterloop/call_native');

  static bool _handlerSet = false;
  static void Function(CallAction action)? _onAction;

  /// True while the app is showing as a picture-in-picture window.
  static final ValueNotifier<bool> inPip = ValueNotifier<bool>(false);

  /// Receives Hang up / Mute / Unmute from the ongoing-call notification and
  /// the PiP window. Only the isolate that runs the UI (and so the call)
  /// gets these.
  static void setActionHandler(void Function(CallAction action)? handler) {
    _onAction = handler;
    _ensureHandler();
  }

  static void _ensureHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    channel.setMethodCallHandler((call) async {
      final args = call.arguments is Map ? call.arguments as Map : const {};
      switch (call.method) {
        case 'onCallAction':
          final action = switch (args['action']) {
            'hangup' => CallAction.hangUp,
            'mute' => CallAction.mute,
            'unmute' => CallAction.unmute,
            'stopScreenShare' => CallAction.stopScreenShare,
            _ => null,
          };
          if (action != null) _onAction?.call(action);
        case 'onPipChanged':
          inPip.value = args['inPip'] == true;
      }
      return null;
    });
  }

  // ── Ringer ──────────────────────────────────────────────────────────────

  /// Whether this platform can ring through [startRinging] at all.
  static bool get ringerSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Rings for the call whose notification [notificationId] is already in
  /// the tray: the app plays [sound] (a raw resource) on loop at ringer
  /// volume and vibrates [vibrationPattern] (off/on/off... in ms, repeated)
  /// until [stopRinging], the notification's Decline (its action at
  /// [declineActionIndex]), the notification being dismissed, or [ringFor].
  ///
  /// The ringer takes the notification over as its own, so it stays up for
  /// exactly as long as the ring - and a plain cancel can't remove it; go
  /// through [stopRinging].
  ///
  /// False when it could not start - the platform has no ringer, or Android
  /// refused a foreground service right now. The caller must then ring some
  /// other way.
  static Future<bool> startRinging({
    required int notificationId,
    required String channelId,
    required Duration ringFor,
    String sound = 'call_ringtone',
    List<int> vibrationPattern = const <int>[0, 1000, 1000],
    int declineActionIndex = -1,
  }) async {
    if (!ringerSupported) return false;
    return await _invoke<bool>('startRinging', <String, Object?>{
          'notificationId': notificationId,
          'channelId': channelId,
          'timeoutMs': ringFor.inMilliseconds,
          'sound': sound,
          'vibrationPattern': vibrationPattern,
          'declineActionIndex': declineActionIndex,
        }) ??
        false;
  }

  /// Stops the ring for [notificationId] - or whatever is ringing, when null
  /// - and takes its notification down.
  static Future<void> stopRinging({int? notificationId}) =>
      _invoke<void>('stopRinging', <String, Object?>{
        'notificationId': notificationId,
      });

  // ── Ongoing call ────────────────────────────────────────────────────────

  /// Shows the ongoing-call notification and keeps the call running with the
  /// app in the background. Call once the call is connected - Android only
  /// allows it while the app is on screen.
  static Future<bool> startOngoingCall({
    required String title,
    required String text,
    required bool muted,
    required DateTime startedAt,
  }) async {
    return await _invoke<bool>('startOngoingCall', <String, Object?>{
          'title': title,
          'text': text,
          'muted': muted,
          'startedAt': startedAt.millisecondsSinceEpoch,
        }) ??
        false;
  }

  /// [screenSharing]: false once the screen share is over, so the
  /// notification drops its "Sharing your screen" and Stop sharing. (The
  /// native side turns it on by itself, the moment capture is allowed.)
  static Future<void> updateOngoingCall({
    String? title,
    bool? muted,
    bool? screenSharing,
  }) =>
      _invoke<void>('updateOngoingCall', <String, Object?>{
        'title': title,
        'muted': muted,
        'screenSharing': screenSharing,
      });

  static Future<void> stopOngoingCall() => _invoke<void>('stopOngoingCall');

  /// Whether a call is running in this process - readable from any isolate,
  /// which is the point: a push drawn in the background isolate can't see
  /// the call controller.
  static Future<bool> isInCall() async =>
      await _invoke<bool>('isInCall') ?? false;

  // ── Picture-in-picture ──────────────────────────────────────────────────

  static Future<bool> isPipSupported() async =>
      await _invoke<bool>('isPipSupported') ?? false;

  /// Whether leaving the app should shrink it into a PiP window, and in what
  /// shape. Android 12+ enters on its own when the user goes home; older
  /// versions enter on the same gesture through the plugin.
  static Future<void> updatePip({
    required bool enabled,
    required bool muted,
    int aspectWidth = 9,
    int aspectHeight = 16,
  }) =>
      _invoke<void>('updatePip', <String, Object?>{
        'enabled': enabled,
        'muted': muted,
        'aspectWidth': aspectWidth,
        'aspectHeight': aspectHeight,
      });

  /// Closes the PiP window, if one is up - the call it showed has ended.
  static Future<void> exitPip() => _invoke<void>('exitPip');

  static Future<T?> _invoke<T>(String method, [Object? args]) async {
    _ensureHandler();
    try {
      return await channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[CallNative] $method failed: ${e.message}');
      return null;
    }
  }
}
