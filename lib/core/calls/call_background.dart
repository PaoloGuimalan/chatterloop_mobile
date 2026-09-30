// Keeps a live call going when the user leaves the call screen - the Dart
// side of chatterloop_call_native, driven entirely by CallController's state:
//
//   connected   -> the ongoing-call notification (Android: a microphone
//                  foreground service, which is what keeps the mic open and
//                  the process alive in the background).
//   video on    -> picture-in-picture, when the call screen is what's showing
//                  (the screen tells us via [setPipEligible]) - but not while
//                  sharing the screen, where the PiP window would float over
//                  the very thing being shared, and be shared with it.
//   backgrounded, not in PiP -> the camera is released until the app is back.
//   ended       -> all of it taken down, PiP window included.
//
// And the other direction: Hang up / Mute / Unmute pressed on the
// notification or the PiP window, applied to the call.
import 'dart:async';

import 'package:chatterloop_app/core/calls/call_controller.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:chatterloop_call_native/chatterloop_call_native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class CallBackground with WidgetsBindingObserver {
  CallBackground._();
  static final CallBackground instance = CallBackground._();

  bool _initialized = false;

  /// The ongoing-call notification is up (or on its way up).
  bool _ongoing = false;
  bool _starting = false;
  String? _shownTitle;
  bool? _shownMuted;
  bool _shownSharing = false;

  bool _pipEligible = false;
  bool _pipWide = false;

  /// What PiP was last told, so an unchanged state is never re-sent - the
  /// call screen reports on every rebuild.
  String? _pipSent;

  void init() {
    if (_initialized) return;
    _initialized = true;
    CallNative.setActionHandler(_onAction);
    CallController.instance.addListener(_sync);
    WidgetsBinding.instance.addObserver(this);
  }

  /// Whether leaving the app should turn the call into a PiP window. The call
  /// screen sets this: true while it is the screen on top and there is video
  /// to show; [wide] for a shared screen, which is landscape.
  void setPipEligible(bool eligible, {bool wide = false}) {
    if (_pipEligible == eligible && _pipWide == wide) return;
    _pipEligible = eligible;
    _pipWide = wide;
    _applyPip();
  }

  void _sync() {
    final call = CallController.instance;
    switch (call.status) {
      case CallEngineStatus.active:
        if (!_ongoing && !_starting) {
          unawaited(_start(call));
        } else if (_ongoing) {
          _refresh(call);
        }
      case CallEngineStatus.idle:
        if (_ongoing || _starting) _stop(call);
      case CallEngineStatus.joining:
      case CallEngineStatus.leaving:
        break;
    }
    _applyPip();
  }

  Future<void> _start(CallController call) async {
    _starting = true;
    final title = _title(call);
    final started = await CallNative.startOngoingCall(
      title: title,
      text: 'Tap to return to the call',
      muted: call.muted,
      startedAt: DateTime.now(),
    );
    _starting = false;
    // The call ended while the notification was starting.
    if (call.status == CallEngineStatus.idle) {
      if (started) unawaited(CallNative.stopOngoingCall());
      return;
    }
    _ongoing = started;
    _shownTitle = title;
    _shownMuted = call.muted;
    // Only Android keeps the engine through the activity being destroyed;
    // on iOS `detached` still means the app is going away.
    call.survivesDetach =
        started && defaultTargetPlatform == TargetPlatform.android;
  }

  void _refresh(CallController call) {
    final title = _title(call);
    final sharing = call.isScreenSharing;
    if (title == _shownTitle &&
        call.muted == _shownMuted &&
        sharing == _shownSharing) {
      return;
    }
    // The native side marks the share itself, the moment capture is allowed;
    // only its END has to be passed on.
    final shareEnded = _shownSharing && !sharing;
    _shownTitle = title;
    _shownMuted = call.muted;
    _shownSharing = sharing;
    unawaited(CallNative.updateOngoingCall(
      title: title,
      muted: call.muted,
      screenSharing: shareEnded ? false : null,
    ));
  }

  void _stop(CallController call) {
    _ongoing = false;
    _starting = false;
    _shownTitle = null;
    _shownMuted = null;
    _shownSharing = false;
    call.survivesDetach = false;
    _pipEligible = false;
    unawaited(CallNative.stopOngoingCall());
    // A call that ended as a PiP window takes the window with it.
    unawaited(CallNative.exitPip());
  }

  void _applyPip() {
    final call = CallController.instance;
    final enabled = _pipEligible &&
        call.status == CallEngineStatus.active &&
        !call.isScreenSharing;
    final key = '$enabled|${call.muted}|$_pipWide';
    if (key == _pipSent) return;
    _pipSent = key;
    unawaited(CallNative.updatePip(
      enabled: enabled,
      muted: call.muted,
      aspectWidth: _pipWide ? 16 : 9,
      aspectHeight: _pipWide ? 9 : 16,
    ));
  }

  /// Who the notification says the call is with.
  String _title(CallController call) {
    if (call.conversationType == 'single') {
      final peer = call.joinedParticipants
          .where((p) => p.clientId != call.clientId && p.username.isNotEmpty)
          .map((p) => p.username)
          .firstOrNull;
      return peer != null ? 'Call with @$peer' : 'Call';
    }
    if (call.conversationType == 'group') return 'Group call';
    return 'Voice channel';
  }

  /// The Share button on both call screens: starts or stops sharing, and says
  /// so when it could not start - unless the user simply said no.
  static Future<void> toggleScreenShare() async {
    final call = CallController.instance;
    if (call.isScreenSharing) {
      await call.stopScreenShare();
      return;
    }
    final result = await call.startScreenShare();
    if (result == ScreenShareResult.failed) {
      CLAlerts.warning("Couldn't share your screen.");
    }
  }

  void _onAction(CallAction action) {
    final call = CallController.instance;
    if (!call.isBusy) return;
    switch (action) {
      case CallAction.hangUp:
        unawaited(call.hangUp());
      case CallAction.mute:
        if (!call.muted) unawaited(call.toggleMic());
      case CallAction.unmute:
        if (call.muted) unawaited(call.toggleMic());
      case CallAction.stopScreenShare:
        unawaited(call.stopScreenShare());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final call = CallController.instance;
    if (call.status == CallEngineStatus.idle) return;
    switch (state) {
      case AppLifecycleState.paused:
        // Into a PiP window is not away - the call is still on screen.
        if (!CallNative.inPip.value) unawaited(call.pauseCameraForBackground());
      case AppLifecycleState.resumed:
        // A PiP window is never resumed, so the app is full-screen again -
        // whether or not Android reported the window closing.
        CallNative.inPip.value = false;
        unawaited(call.resumeCameraFromBackground());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }
}
