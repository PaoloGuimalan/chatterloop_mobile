/// The editor's preview of a whole edit: its clips one after another, its
/// overlays over them and its audio tracks alongside, from a playhead the
/// timeline scrubs - round and round while playing. Blanks (between clips,
/// or after them under a layer or a song) are simply nothing: the caller
/// draws black there.
///
/// The picture is the caller's to draw (the clip under the playhead, if
/// any, and the overlays showing there, with [videoFor] / [overlayVideoFor]'s
/// players when they are videos); this keeps the players and the playhead
/// in step:
///  - while a main video clip plays, IT keeps time - the playhead follows
///    its picture, and it is not seeked while it plays on as it should.
///    (The playhead used to run on its own clock and pull the video after
///    it with seeks; a seek stalls a video for a moment, a phone's decoder
///    took longer than the pull allowed, and the preview juddered from seek
///    to seek.) Over a photo or a blank, a clock keeps time;
///  - a video is seeked only to where it has to be: when it comes up - the
///    next clip's player waits at its start ahead of time, so it just plays
///    - or when it has stopped somewhere else (run to its file's end, say);
///  - an overlay's player plays along, and is pulled back only when it
///    wanders well off;
///  - an audio track's player starts where the playhead enters it and stops
///    where it leaves, and is put back in step when it drifts.
///
/// Decoders are scarce - a phone runs out of them quickly, and then a video
/// just doesn't play - so a video keeps a player only while it shows or is
/// about to: the main clip on screen, the next one as it nears, the overlays
/// showing or about to. The rest are let go and made again when needed.
/// Players are shared where things never play at once: one per file for the
/// main clips (the pieces of a split clip), one per file per LANE for
/// overlays and songs.
library;

import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

class SequencePlayer extends ChangeNotifier {
  SequencePlayer({required TickerProvider vsync}) {
    _ticker = vsync.createTicker(_onTick);
  }

  /// A video this close to where it should be is left alone - a seek would
  /// only stall it.
  static const _settled = Duration(milliseconds: 150);

  /// How far an overlay playing along may wander before it is pulled back.
  static const _overlayDrift = Duration(milliseconds: 400);

  /// After a seek a player is given this long: its position reads stale
  /// until the seek lands, and seeking it again would start that over.
  static const _seekGrace = Duration(milliseconds: 1200);

  /// A video reports its position every 100ms; in between, the playhead
  /// runs on by the clock - never further than this past the last report
  /// (a video that stopped reporting has stalled, and the playhead waits).
  static const _clockReach = Duration(milliseconds: 120);

  /// How often a playing song is checked against the playhead, and how far
  /// off it may be before it is put back.
  static const _audioCheckEvery = Duration(seconds: 1);
  static const _audioDrift = Duration(milliseconds: 250);

  /// While scrubbing, a video is seeked at most this often (seeks are not
  /// free); the last position is always reached.
  static const _scrubEvery = Duration(milliseconds: 80);

  /// A video's player is made this long before it shows, so it is ready
  /// (and waiting at its start) when it does.
  static const _lead = Duration(milliseconds: 2500);

  /// A player that hasn't started in this long won't: let go, tried later.
  static const _startLimit = Duration(seconds: 8);

  late final Ticker _ticker;
  Composition? _edit;

  /// The playhead - every frame while playing. [addListener] hears only the
  /// bigger changes (what is on screen, playing or not, a player ready).
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);

  bool _playing = false;
  Duration _anchor = Duration.zero;

  /// The main clip on screen when last synced: its index, [_blank] in a
  /// blank, null when not synced yet.
  int? _shownIndex;
  static const _blank = -1;

  /// The overlays showing when last synced, as a key ("1,3").
  String? _shownOverlays;
  bool _disposed = false;

  /// Video players by key ([_mainKey], [_overlayKey]) - made, or being
  /// made.
  final Map<String, VideoPlayerController> _videos = {};
  final Map<String, Future<void>> _videoReady = {};

  /// Players that failed to start, and when: not tried again for
  /// [_retryAfter]. Retried at once, a failing file (decoders all taken,
  /// say) went round load-fail-load with no pause and froze the app.
  final Map<String, DateTime> _failedAt = {};
  static const _retryAfter = Duration(seconds: 3);

  /// Audio players by key ([_trackKey]).
  final Map<String, AudioPlayer> _audio = {};

  /// Per audio player, the track now playing on it.
  final Map<String, int> _playingTrack = {};

  final Map<String, DateTime> _lastScrubSeek = {};
  final Map<String, Timer> _trailingSeek = {};

  /// Where each video player was last sent, and when.
  final Map<String, ({Duration to, DateTime at})> _lastSeek = {};

  /// Seeks not yet seen to land: until a player reports being where it was
  /// sent (or [_seekGrace] passes), its position is the one from before.
  final Map<String, ({Duration to, DateTime at})> _landing = {};

  /// The volume each video player was last given - sent again only when it
  /// changes (it used to go to the platform on every frame).
  final Map<String, double> _volumes = {};

  /// The video keeping time: its player, its last reported position, and
  /// when that report came (by the ticker).
  String? _clockKey;
  Duration _clockPosition = Duration.zero;
  Duration _clockElapsed = Duration.zero;

  DateTime _audioCheckedAt = DateTime(0);

  static String _mainKey(String path) => 'm|$path';
  static String _overlayKey(OverlayClip o) =>
      'o${o.lane}|${o.clip.source.path}';
  static String _trackKey(AudioTrack t) => 'a${t.lane}|${t.path}';

  bool get playing => _playing;

  /// The main clip under the playhead - null in a blank.
  int? get currentIndex => _edit?.locate(position.value)?.index;

  /// The ready player for the main clip at [index], when it is a video.
  VideoPlayerController? videoFor(int index) {
    final clips = _edit?.clips;
    if (clips == null || index >= clips.length) return null;
    final clip = clips[index];
    if (!clip.source.isVideo) return null;
    return _ready(_mainKey(clip.source.path));
  }

  /// The ready player for the overlay at [index], when it is a video.
  VideoPlayerController? overlayVideoFor(int index) {
    final overlays = _edit?.overlays;
    if (overlays == null || index >= overlays.length) return null;
    final overlay = overlays[index];
    if (!overlay.clip.source.isVideo) return null;
    return _ready(_overlayKey(overlay));
  }

  VideoPlayerController? _ready(String key) {
    final controller = _videos[key];
    return controller != null && controller.value.isInitialized
        ? controller
        : null;
  }

  /// The edit changed (or was first given): the players follow it.
  void setEdit(Composition? edit) {
    _edit = edit;
    if (edit == null) {
      pause();
      position.value = Duration.zero;
      _releaseAll();
      return;
    }
    final total = edit.naturalDuration;
    if (position.value > total) position.value = total;
    // Players for what is no longer in the edit go.
    final videos = {
      for (final clip in edit.clips)
        if (clip.source.isVideo) _mainKey(clip.source.path),
      for (final overlay in edit.overlays)
        if (overlay.clip.source.isVideo) _overlayKey(overlay),
    };
    for (final key in [..._videos.keys]) {
      if (!videos.contains(key)) _releaseVideo(key);
    }
    final songs = {for (final track in edit.audio) _trackKey(track)};
    for (final key in [..._audio.keys]) {
      if (!songs.contains(key)) _audio.remove(key)?.dispose();
    }
    _shownIndex = null;
    _shownOverlays = null;
    _playingTrack.clear();
    // Edits arrive with every move of a trim handle: seek like a scrub.
    _sync(seekVideo: true, scrubbing: !_playing);
    notifyListeners();
  }

  Future<void> play() async {
    final edit = _edit;
    if (edit == null || _playing) return;
    if (position.value >=
        edit.naturalDuration - const Duration(milliseconds: 50)) {
      position.value = Duration.zero;
    }
    _playing = true;
    _anchor = position.value;
    _shownIndex = null;
    _shownOverlays = null;
    _playingTrack.clear();
    _sync(seekVideo: true);
    if (!_ticker.isActive) _ticker.start();
    notifyListeners();
  }

  void pause() {
    if (!_playing) return;
    _playing = false;
    _ticker.stop();
    for (final video in _videos.values) {
      if (video.value.isInitialized) video.pause();
    }
    for (final player in _audio.values) {
      player.pause();
    }
    _playingTrack.clear();
    notifyListeners();
  }

  void toggle() => _playing ? pause() : play();

  /// Moves the playhead to [to] - the picture follows (a video is seeked
  /// there, at most every [_scrubEvery]).
  void seek(Duration to) {
    final edit = _edit;
    if (edit == null) return;
    final total = edit.naturalDuration;
    position.value =
        to < Duration.zero ? Duration.zero : (to > total ? total : to);
    if (_playing) {
      _anchor = position.value;
      _ticker
        ..stop()
        ..start();
      _playingTrack.clear();
    }
    _sync(seekVideo: true, scrubbing: !_playing);
  }

  void _onTick(Duration elapsed) {
    final edit = _edit;
    if (edit == null) return;
    final total = edit.naturalDuration;
    var at = _anchor + elapsed;
    // A video on screen keeps time; the clock is kept in step with it, for
    // when a photo or a blank comes next.
    final led = _videoClock(edit, elapsed);
    if (led != null) {
      at = led;
      _anchor = at - elapsed;
    }
    if (at >= total) {
      // Round again, from the top.
      _anchor = Duration.zero;
      at = Duration.zero;
      _ticker
        ..stop()
        ..start();
      _shownIndex = null;
      _shownOverlays = null;
      _clockKey = null;
      _playingTrack.clear();
    }
    position.value = at;
    _sync();
    _keepAudioInStep(edit);
  }

  /// The playhead as the main video on screen tells it - null when no
  /// video is keeping time (a photo or a blank is on screen, or its video
  /// isn't ready or playing).
  Duration? _videoClock(Composition edit, Duration elapsed) {
    final index = _shownIndex;
    if (index == null || index < 0 || index >= edit.clips.length) return null;
    final clip = edit.clips[index];
    if (!clip.source.isVideo) return null;
    final key = _mainKey(clip.source.path);
    final video = _ready(key);
    if (video == null || !video.value.isPlaying) return null;
    final reported = video.value.position;
    // Just sent somewhere and not there yet: the playhead waits for it.
    // Once it has been seen there, it keeps time from there on.
    final sent = _landing[key];
    if (sent != null) {
      if ((reported - sent.to).abs() > _settled &&
          DateTime.now().difference(sent.at) < _seekGrace) {
        return position.value;
      }
      _landing.remove(key);
    }
    if (key != _clockKey ||
        reported != _clockPosition ||
        elapsed < _clockElapsed) {
      _clockKey = key;
      _clockPosition = reported;
      _clockElapsed = elapsed;
    }
    var since = elapsed - _clockElapsed;
    if (since > _clockReach) since = _clockReach;
    final start = edit.clipStarts[index];
    final at = start + (reported + since - clip.usedRange.start);
    // Not before its clip - a report from before its seek landed.
    return at < start ? start : at;
  }

  /// Every [_audioCheckEvery], each playing song is asked where it is and
  /// put back where the playhead says it should be when it has drifted -
  /// the playhead waits for a video that is slow to start, the songs don't.
  void _keepAudioInStep(Composition edit) {
    final now = DateTime.now();
    if (now.difference(_audioCheckedAt) < _audioCheckEvery) return;
    _audioCheckedAt = now;
    for (final MapEntry(:key, value: k) in [..._playingTrack.entries]) {
      final player = _audio[key];
      if (player == null || k >= edit.audio.length) continue;
      final track = edit.audio[k];
      player.getCurrentPosition().then((heard) {
        if (heard == null || !_playing || _disposed) return;
        if (_playingTrack[key] != k || !identical(_edit, edit)) return;
        final expected = track.trim.start + (position.value - track.start);
        if (expected < track.trim.start || expected >= track.trim.end) return;
        if ((heard - expected).abs() > _audioDrift) player.seek(expected);
      }).catchError((Object e) {
        debugPrint('SequencePlayer: audio check failed: $e');
      });
    }
  }

  /// The main clip that comes after [index] - or, in a blank, the first
  /// starting after [at] - and how long until it does. Round to the first
  /// after the last. Null with no clips.
  (int, Duration)? _nextClip(Composition edit, int index, Duration at) {
    if (edit.clips.isEmpty) return null;
    final starts = edit.clipStarts;
    var next = index + 1;
    if (index < 0) {
      next = starts.indexWhere((start) => start > at);
      if (next < 0) next = edit.clips.length;
    }
    if (next < edit.clips.length) return (next, starts[next] - at);
    // Round again: to the end, then from the top.
    return (0, edit.naturalDuration - at + starts.first);
  }

  /// Brings every player in line with the playhead.
  void _sync({bool seekVideo = false, bool scrubbing = false}) {
    final edit = _edit;
    if (edit == null) return;
    final at = position.value;
    final located = edit.locate(at);
    final index = located?.index ?? _blank;
    final clip = located == null ? null : edit.clips[located.index];
    final showing = edit.overlaysAt(at);
    final showingKey = showing.join(',');

    var changed = false;
    if (index != _shownIndex) {
      final previous = _shownIndex;
      _shownIndex = index;
      if (previous != null && previous >= 0 && previous < edit.clips.length) {
        final before = edit.clips[previous].source;
        if (before.isVideo && before.path != clip?.source.path) {
          final video = _videos[_mainKey(before.path)];
          if (video != null && video.value.isInitialized) video.pause();
        }
      }
      seekVideo = true;
      changed = true;
    }
    final overlaysChanged = showingKey != _shownOverlays;
    if (overlaysChanged) {
      _shownOverlays = showingKey;
      changed = true;
    }
    if (changed) {
      _retain(edit, index, at);
      notifyListeners();
    }

    if (clip != null && clip.source.isVideo) {
      _drive(
        _mainKey(clip.source.path),
        clip.source.path,
        clip.usedRange.start + located!.offset,
        clip.soundHeard ? clip.volume : 0,
        seek: seekVideo,
        scrubbing: scrubbing,
        keepsTime: true,
      );
    }
    // The next clip's player - when it is another - is made as it nears and
    // waits at its start, so it plays the moment it comes up instead of
    // seeking then.
    final upcoming = _nextClip(edit, index, at);
    if (upcoming != null && !scrubbing) {
      final (next, until) = upcoming;
      final nextClip = edit.clips[next];
      if (nextClip.source.isVideo &&
          nextClip.source.path != clip?.source.path &&
          until <= _lead) {
        final key = _mainKey(nextClip.source.path);
        _loadUnlessResting(key, nextClip.source.path);
        final video = _ready(key);
        if (video != null && !video.value.isPlaying) {
          _seek(key, video, nextClip.usedRange.start);
        }
      }
    }

    // The overlays showing play; the ones just gone stop - unless their
    // player is one a showing overlay shares.
    final driven = <String>{};
    for (final i in showing) {
      final overlay = edit.overlays[i];
      if (!overlay.clip.source.isVideo) continue;
      final key = _overlayKey(overlay);
      driven.add(key);
      _drive(
        key,
        overlay.clip.source.path,
        overlay.clip.usedRange.start + (at - overlay.start),
        overlay.clip.soundHeard ? overlay.clip.volume : 0,
        seek: seekVideo || overlaysChanged,
        scrubbing: scrubbing,
      );
    }
    // Ones about to show are made ready, waiting at their start.
    for (final overlay in edit.overlays) {
      if (!overlay.clip.source.isVideo) continue;
      final key = _overlayKey(overlay);
      if (driven.contains(key)) continue;
      final soon = at >= overlay.start - _lead && at < overlay.start;
      if (soon) {
        _loadUnlessResting(key, overlay.clip.source.path);
        final video = _ready(key);
        if (video != null && !video.value.isPlaying && !scrubbing) {
          _seek(key, video, overlay.clip.usedRange.start);
        }
      } else {
        final video = _videos[key];
        if (video != null && video.value.isInitialized && video.value.isPlaying) {
          video.pause();
        }
      }
    }

    if (!_playing) return;
    for (var k = 0; k < edit.audio.length; k++) {
      final track = edit.audio[k];
      final key = _trackKey(track);
      final active = at >= track.start && at < track.end;
      final player = _audio[key];
      if (active) {
        if (_playingTrack[key] == k) continue;
        _playingTrack[key] = k;
        final from = track.trim.start + (at - track.start);
        _startTrack(key, track, player, from);
      } else if (_playingTrack[key] == k) {
        _playingTrack.remove(key);
        player?.pause();
      }
    }
  }

  /// Keeps the video player [key] (of [path]) showing [want]: made when
  /// missing, sent there when it comes up or the playhead moved, playing
  /// along with the playhead, at [volume].
  ///
  /// The one that [keepsTime] is left alone while it plays on - the
  /// playhead follows it; an overlay is pulled back when it wanders well
  /// off. Either is sent back when it has stopped somewhere else (a video
  /// run to its file's end stops there, and parks on its last frame).
  void _drive(
    String key,
    String path,
    Duration want,
    double volume, {
    required bool seek,
    required bool scrubbing,
    bool keepsTime = false,
  }) {
    final video = _videos[key];
    if (video == null || !video.value.isInitialized) {
      _loadUnlessResting(key, path);
      return;
    }
    _setVolume(key, video, volume);
    final off = (video.value.position - want).abs();
    if (scrubbing) {
      _scrubSeek(key, video, want);
    } else if (seek || !_playing) {
      _seek(key, video, want);
    } else if (!video.value.isPlaying && off > _settled) {
      // Should be playing, and isn't, somewhere else.
      if (!_seekedLately(key)) _seek(key, video, want);
    } else if (!keepsTime && off > _overlayDrift && !_seekedLately(key)) {
      _seek(key, video, want);
    }
    // Not at the file's very end: play() there starts it over from 0.
    final atEnd = video.value.position >=
        video.value.duration - const Duration(milliseconds: 50);
    if (_playing && !video.value.isPlaying && !atEnd) video.play();
    if (!_playing && video.value.isPlaying) video.pause();
  }

  /// Makes the player [key] - unless it is made or being made already, or
  /// failed a moment ago - and once it is ready, shows it from where the
  /// playhead is by then.
  ///
  /// "Being made" is only ever the player in [_videos]: one let go while
  /// starting (video_player never finishes starting one disposed then) is
  /// gone from there, and made afresh when wanted again. (A separate
  /// "starting" list kept such a file blocked for good - the clip never
  /// played again.) Nor is a player that already exists re-synced: that
  /// went round sync-load-sync forever in microtasks - the editor froze.
  void _loadUnlessResting(String key, String path) {
    if (_videos.containsKey(key)) return;
    final failed = _failedAt[key];
    if (failed != null && DateTime.now().difference(failed) < _retryAfter) {
      return;
    }
    _load(key, path).whenComplete(() {
      if (_disposed || _edit == null) return;
      // Only when it did start: after a failure this would come straight
      // back round.
      if (_videos[key]?.value.isInitialized != true) return;
      _shownIndex = null;
      _shownOverlays = null;
      _sync(seekVideo: true);
    });
  }

  Future<void> _startTrack(String key, AudioTrack track, AudioPlayer? existing,
      Duration from) async {
    try {
      final player = existing ?? await _audioFor(key, track.path);
      if (_disposed) return;
      await player.setVolume(track.volume.clamp(0.0, 1.0));
      await player.seek(from);
      if (_playing) await player.resume();
    } catch (e) {
      debugPrint('SequencePlayer: audio failed: $e');
    }
  }

  Future<AudioPlayer> _audioFor(String key, String path) async {
    final existing = _audio[key];
    if (existing != null) return existing;
    final player = AudioPlayer();
    _audio[key] = player;
    // Plays alongside the video preview instead of taking audio focus from
    // it (see the videos' mixWithOthers).
    await player.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
            .build());
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setSource(DeviceFileSource(path));
    return player;
  }

  /// Sends the video player [key] to [to] - unless it is there already, or
  /// was just sent there. [force]: always (scrubbing, which wants the exact
  /// frame).
  void _seek(String key, VideoPlayerController video, Duration to,
      {bool force = false}) {
    final now = DateTime.now();
    if (!force) {
      if ((video.value.position - to).abs() <= _settled) return;
      final last = _lastSeek[key];
      if (last != null &&
          (last.to - to).abs() <= _settled &&
          now.difference(last.at) < _seekGrace) {
        return;
      }
    }
    _lastSeek[key] = (to: to, at: now);
    _landing[key] = (to: to, at: now);
    video.seekTo(to);
  }

  bool _seekedLately(String key) {
    final last = _lastSeek[key];
    return last != null && DateTime.now().difference(last.at) < _seekGrace;
  }

  void _setVolume(String key, VideoPlayerController video, double volume) {
    final level = volume.clamp(0.0, 1.0);
    if (_volumes[key] == level) return;
    _volumes[key] = level;
    video.setVolume(level);
  }

  void _scrubSeek(String key, VideoPlayerController video, Duration to) {
    _trailingSeek.remove(key)?.cancel();
    final now = DateTime.now();
    if (now.difference(_lastScrubSeek[key] ?? DateTime(0)) >= _scrubEvery) {
      _lastScrubSeek[key] = now;
      _seek(key, video, to, force: true);
    } else {
      // The last one lands even if the finger stops inside the window.
      _trailingSeek[key] = Timer(_scrubEvery, () {
        _trailingSeek.remove(key);
        if (identical(_videos[key], video)) _seek(key, video, to, force: true);
      });
    }
  }

  /// Lets go of the players not wanted at [at] (the main clip [index] on
  /// screen): all but that clip's, the next clip's as it nears, and the
  /// overlays' showing or about to. What is wanted and missing is made.
  void _retain(Composition edit, int index, Duration at) {
    final keep = <String, String>{};
    void want(MediaLayer clip, String key) {
      if (clip.source.isVideo) keep[key] = clip.source.path;
    }

    if (index >= 0) {
      final clip = edit.clips[index];
      want(clip, _mainKey(clip.source.path));
    }
    final upcoming = _nextClip(edit, index, at);
    if (upcoming != null && upcoming.$2 <= _lead) {
      final next = edit.clips[upcoming.$1];
      want(next, _mainKey(next.source.path));
    }
    for (final overlay in edit.overlays) {
      if (at >= overlay.start - _lead && at < overlay.end) {
        want(overlay.clip, _overlayKey(overlay));
      }
    }
    for (final key in [..._videos.keys]) {
      if (!keep.containsKey(key)) _releaseVideo(key);
    }
    for (final MapEntry(:key, :value) in keep.entries) {
      _loadUnlessResting(key, value);
    }
  }

  Future<void> _load(String key, String path) {
    return _videoReady[key] ??= () async {
      final controller = VideoPlayerController.file(
        File(path),
        // mixWithOthers: without it the video takes the device's audio focus
        // and the music pauses it (and it the music).
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _videos[key] = controller;
      try {
        await controller.initialize().timeout(_startLimit);
        if (_disposed || _videos[key] != controller) {
          await controller.dispose();
          return;
        }
        _failedAt.remove(key);
        notifyListeners();
      } catch (e) {
        // Let go of already (and maybe made again since): not a failure of
        // the file, and nothing of the new one's to touch.
        if (_videos[key] != controller) {
          unawaited(controller.dispose());
          return;
        }
        debugPrint('SequencePlayer: video failed: $e');
        // Let it go, and rest before the next try.
        _failedAt[key] = DateTime.now();
        _videos.remove(key);
        _videoReady.remove(key);
        unawaited(controller.dispose());
      }
    }();
  }

  /// Lets every video player go - their decoders and memory - for heavy
  /// work like a render. [resume] brings back the ones on screen.
  void releaseVideos() {
    pause();
    for (final key in [..._videos.keys]) {
      _releaseVideo(key);
    }
    _shownIndex = null;
    _shownOverlays = null;
    notifyListeners();
  }

  /// After [releaseVideos]: what is on screen loads again.
  void resume() {
    _shownIndex = null;
    _shownOverlays = null;
    _failedAt.clear();
    _sync(seekVideo: true);
  }

  void _releaseVideo(String key) {
    _videoReady.remove(key);
    _trailingSeek.remove(key)?.cancel();
    _lastSeek.remove(key);
    _landing.remove(key);
    _volumes.remove(key);
    if (_clockKey == key) _clockKey = null;
    _videos.remove(key)?.dispose();
  }

  void _releaseAll() {
    for (final key in [..._videos.keys]) {
      _releaseVideo(key);
    }
    for (final player in _audio.values) {
      player.dispose();
    }
    _audio.clear();
    _playingTrack.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _trailingSeek.values) {
      timer.cancel();
    }
    _trailingSeek.clear();
    _ticker.dispose();
    _releaseAll();
    position.dispose();
    super.dispose();
  }
}
