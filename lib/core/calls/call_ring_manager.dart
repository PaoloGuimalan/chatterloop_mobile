// Loops a ringtone while an incoming-call alert is showing. A separate,
// stateless static helper rather than something owned by IncomingCallView's
// State - keeps the "is a ringtone currently playing" concern in one place
// regardless of which screen is asking, and avoids a leaked loop if a
// screen gets torn down some other way than its own dispose() (e.g. a
// route replaced from underneath it).

import 'package:audioplayers/audioplayers.dart';

class CallRingManager {
  CallRingManager._();

  static final AudioPlayer _player = AudioPlayer();
  static bool _ringing = false;

  static Future<void> start() async {
    if (_ringing) return;
    _ringing = true;
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.play(AssetSource('sounds/alert_call_tune.mp3'));
  }

  static Future<void> stop() async {
    if (!_ringing) return;
    _ringing = false;
    await _player.stop();
  }
}
