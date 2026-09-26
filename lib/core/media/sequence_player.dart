/// The editor's preview of a whole edit: its clips one after another, its
/// audio tracks alongside, from a playhead the timeline scrubs - round and
/// round while playing.
///
/// The picture is the caller's to draw (the clip under the playhead, with
/// [videoFor]'s player when it is a video); this keeps the players in step
/// with the playhead:
///  - a video clip's player is seeked to where the playhead is in it when
///    the clip comes up, and again whenever it drifts off by more than a
///    little;
///  - an audio track's player starts where the playhead enters it and stops
///    where it leaves.
///
/// Decoders are scarce, so only the clips around the playhead keep a video
/// player; the rest are let go and made again when needed. One player per
/// FILE - the pieces of a split clip or song share it (they never play at
/// once).
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

  /// How far a player may wander from the playhead before it is re-seeked.
  static const _videoDrift = Duration(milliseconds: 300);

  /// While scrubbing, a video is seeked at most this often (seeks are not
  /// free); the last position is always reached.
  static const _scrubEvery = Duration(milliseconds: 80);

  late final Ticker _ticker;
  Composition? _edit;

  /// The playhead - every frame while playing. [addListener] hears only the
  /// bigger changes (the clip on screen, playing or not, a player ready).
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);

  bool _playing = false;
  Duration _anchor = Duration.zero;
  int? _shownIndex;
  bool _disposed = false;

  final Map<String, VideoPlayerController> _videos = {};
  final Map<String, Future<void>> _videoReady = {};
  final Set<String> _awaiting = {};

  /// Files whose player failed to start, and when: not tried again for
  /// [_retryAfter]. Retried at once, a failing file (decoders all taken,
  /// say) went round load-fail-load with no pause and froze the app.
  final Map<String, DateTime> _failedAt = {};
  static const _retryAfter = Duration(seconds: 3);
  final Map<String, AudioPlayer> _audio = {};

  /// Per audio file, the track now playing from it.
  final Map<String, int> _playingTrack = {};

  DateTime _lastScrubSeek = DateTime(0);
  Timer? _trailingSeek;

  bool get playing => _playing;

  /// The clip under the playhead.
  int get currentIndex => _edit?.locate(position.value).index ?? 0;

  /// The ready player for the clip at [index], when it is a video.
  VideoPlayerController? videoFor(int index) {
    final clips = _edit?.clips;
    if (clips == null || index >= clips.length) return null;
    final clip = clips[index];
    if (!clip.source.isVideo) return null;
    final controller = _videos[clip.source.path];
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
    // Players for files no longer in the edit go.
    final paths = {for (final clip in edit.clips) clip.source.path};
    for (final path in [..._videos.keys]) {
      if (!paths.contains(path)) _releaseVideo(path);
    }
    final songs = {for (final track in edit.audio) track.path};
    for (final path in [..._audio.keys]) {
      if (!songs.contains(path)) {
        _audio.remove(path)?.dispose();
        _playingTrack.remove(path);
      }
    }
    _shownIndex = null;
    _playingTrack.clear();
    // Edits arrive with every move of a trim handle: seek like a scrub.
    _sync(seekVideo: true, scrubbing: !_playing);
    notifyListeners();
  }

  Future<void> play() async {
    final edit = _edit;
    if (edit == null || _playing) return;
    if (position.value >= edit.naturalDuration - const Duration(milliseconds: 50)) {
      position.value = Duration.zero;
    }
    _playing = true;
    _anchor = position.value;
    _shownIndex = null;
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
    if (at >= total) {
      // Round again, from the top.
      _anchor = Duration.zero;
      at = Duration.zero;
      _ticker
        ..stop()
        ..start();
      _shownIndex = null;
      _playingTrack.clear();
    }
    position.value = at;
    _sync();
  }

  /// Brings every player in line with the playhead.
  void _sync({bool seekVideo = false, bool scrubbing = false}) {
    final edit = _edit;
    if (edit == null || edit.clips.isEmpty) return;
    final at = position.value;
    final (:index, :offset) = edit.locate(at);
    final clip = edit.clips[index];

    if (index != _shownIndex) {
      final previous = _shownIndex;
      _shownIndex = index;
      if (previous != null && previous < edit.clips.length) {
        final before = edit.clips[previous].source;
        if (before.isVideo && before.path != clip.source.path) {
          final video = _videos[before.path];
          if (video != null && video.value.isInitialized) video.pause();
        }
      }
      seekVideo = true;
      _keepAround(edit, index);
      notifyListeners();
    }

    if (clip.source.isVideo) {
      final want = clip.usedRange.start + offset;
      final video = _videos[clip.source.path];
      final path = clip.source.path;
      if (video == null || !video.value.isInitialized) {
        final failed = _failedAt[path];
        final resting =
            failed != null && DateTime.now().difference(failed) < _retryAfter;
        // Once it's ready, show it from where the playhead is by then.
        if (!resting && _awaiting.add(path)) {
          _load(path).whenComplete(() {
            _awaiting.remove(path);
            if (_disposed || _edit != edit) return;
            // Only when it did start: after a failure this would come
            // straight back round.
            if (_videos[path]?.value.isInitialized != true) return;
            _shownIndex = null;
            _sync(seekVideo: true);
          });
        }
      } else {
        video.setVolume(clip.soundHeard ? clip.volume.clamp(0.0, 1.0) : 0);
        final drift = (video.value.position - want).abs();
        if (scrubbing) {
          _scrubSeek(video, want);
        } else if (seekVideo || drift > _videoDrift) {
          video.seekTo(want);
        }
        // Not at the file's very end: play() there starts it over from 0.
        final atEnd = video.value.position >=
            video.value.duration - const Duration(milliseconds: 50);
        if (_playing && !video.value.isPlaying && !atEnd) video.play();
        if (!_playing && video.value.isPlaying) video.pause();
      }
    }

    if (!_playing) return;
    for (var k = 0; k < edit.audio.length; k++) {
      final track = edit.audio[k];
      final active = at >= track.start && at < track.end;
      final player = _audio[track.path];
      if (active) {
        if (_playingTrack[track.path] == k) continue;
        _playingTrack[track.path] = k;
        final from = track.trim.start + (at - track.start);
        _startTrack(track, player, from);
      } else if (_playingTrack[track.path] == k) {
        _playingTrack.remove(track.path);
        player?.pause();
      }
    }
  }

  Future<void> _startTrack(
      AudioTrack track, AudioPlayer? existing, Duration from) async {
    try {
      final player = existing ?? await _audioFor(track.path);
      if (_disposed) return;
      await player.setVolume(track.volume.clamp(0.0, 1.0));
      await player.seek(from);
      if (_playing) await player.resume();
    } catch (e) {
      debugPrint('SequencePlayer: audio failed: $e');
    }
  }

  Future<AudioPlayer> _audioFor(String path) async {
    final existing = _audio[path];
    if (existing != null) return existing;
    final player = AudioPlayer();
    _audio[path] = player;
    // Plays alongside the video preview instead of taking audio focus from
    // it (see the videos' mixWithOthers).
    await player.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
            .build());
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setSource(DeviceFileSource(path));
    return player;
  }

  void _scrubSeek(VideoPlayerController video, Duration to) {
    _trailingSeek?.cancel();
    final now = DateTime.now();
    if (now.difference(_lastScrubSeek) >= _scrubEvery) {
      _lastScrubSeek = now;
      video.seekTo(to);
    } else {
      // The last one lands even if the finger stops inside the window.
      _trailingSeek = Timer(_scrubEvery, () => video.seekTo(to));
    }
  }

  /// Players for the clips either side of [index] load ahead; the others
  /// let their decoders go.
  void _keepAround(Composition edit, int index) {
    final keep = <String>{
      for (var i = index - 1; i <= index + 1; i++)
        if (i >= 0 && i < edit.clips.length && edit.clips[i].source.isVideo)
          edit.clips[i].source.path
    };
    for (final path in [..._videos.keys]) {
      if (!keep.contains(path)) _releaseVideo(path);
    }
    for (final path in keep) {
      _load(path);
    }
  }

  Future<void> _load(String path) {
    return _videoReady[path] ??= () async {
      final controller = VideoPlayerController.file(
        File(path),
        // mixWithOthers: without it the video takes the device's audio focus
        // and the music pauses it (and it the music).
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _videos[path] = controller;
      try {
        await controller.initialize();
        if (_disposed || _videos[path] != controller) {
          await controller.dispose();
          return;
        }
        _failedAt.remove(path);
        notifyListeners();
      } catch (e) {
        debugPrint('SequencePlayer: video failed: $e');
        // Let it go, and rest before the next try.
        _failedAt[path] = DateTime.now();
        if (_videos[path] == controller) {
          _videos.remove(path);
          _videoReady.remove(path);
        }
        await controller.dispose();
      }
    }();
  }

  /// Lets every video player go - their decoders and memory - for heavy
  /// work like a render. [resume] brings back the one on screen.
  void releaseVideos() {
    pause();
    for (final path in [..._videos.keys]) {
      _releaseVideo(path);
    }
    _shownIndex = null;
    notifyListeners();
  }

  /// After [releaseVideos]: the clip on screen loads again.
  void resume() {
    _shownIndex = null;
    _failedAt.clear();
    _sync(seekVideo: true);
  }

  void _releaseVideo(String path) {
    _videoReady.remove(path);
    _videos.remove(path)?.dispose();
  }

  void _releaseAll() {
    for (final path in [..._videos.keys]) {
      _releaseVideo(path);
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
    _trailingSeek?.cancel();
    _ticker.dispose();
    _releaseAll();
    position.dispose();
    super.dispose();
  }
}
