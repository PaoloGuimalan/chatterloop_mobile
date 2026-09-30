// Where the live call's screen is - so the call can be LEFT without being
// ended, and come back to.
//
// A call ends only when the user ends it (End, Leave) or the app is killed.
// Every other way out of a call screen - back, the system gesture, navigating
// elsewhere, the screen being swapped out - just minimizes it: the app keeps
// going with the call in a floating window (CallOverlayHost), and leaving the
// app turns it into a picture-in-picture window (CallBackground).
//
// The two call screens (ActiveCallView, VoiceChannelScreen) report here:
// whether they are the screen on top - the floating window hides while one is
// - and how to open them again, which is what tapping the floating window does.
import 'package:chatterloop_app/core/calls/call_controller.dart';
import 'package:flutter/widgets.dart';

class CallScreens {
  CallScreens._();

  /// True while a call screen is the screen on top.
  static final ValueNotifier<bool> onScreen = ValueNotifier<bool>(false);

  static final Set<Object> _visible = <Object>{};
  static VoidCallback? _reopen;
  static String? _roomName;

  /// A call screen's state reports whether it is the route on top. Applied
  /// after the frame: it is called from build, and listeners rebuild.
  static void report(Object screen, {required bool visible}) {
    final changed = visible ? _visible.add(screen) : _visible.remove(screen);
    if (!changed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onScreen.value = _visible.isNotEmpty;
    });
  }

  /// How to bring the live call's screen back, and - for a voice channel -
  /// the room's name, which is what the floating window and the notification
  /// call it.
  static void register(VoidCallback reopen, {String? roomName}) {
    _reopen = reopen;
    _roomName = roomName;
  }

  static void reopen() => _reopen?.call();

  /// The call is over.
  static void clear() {
    _reopen = null;
    _roomName = null;
  }

  /// What the live call is called, wherever it is shown outside its screen.
  static String title(CallController call) {
    final room = _roomName;
    if (room != null && room.isNotEmpty) return room;
    final name = call.displayName;
    if (name != null && name.isNotEmpty) return name;
    final peer = call.joinedParticipants
        .where((p) => p.clientId != call.clientId && p.username.isNotEmpty)
        .map((p) => p.username)
        .firstOrNull;
    return peer != null ? '@$peer' : 'Call';
  }
}
