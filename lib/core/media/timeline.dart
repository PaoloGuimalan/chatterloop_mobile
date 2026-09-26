/// Editing a [Composition] along its timeline - what the editor's cards do:
/// reorder, trim, split and remove clips; place, trim, split and remove audio
/// tracks. Pure, so every rule is tested (test/timeline_test.dart).
///
/// The rules:
///  - Clips play end to end; the edit is at most the profile's length
///    ([maxTotal]) - growing a clip stops there.
///  - A clip or track is never trimmed shorter than [minPiece].
///  - Audio tracks never overlap. A dragged track lands in the free gap
///    nearest where it was dropped - so dragging one past another swaps them.
library;

import 'package:chatterloop_app/core/media/composition.dart';

/// The shortest a clip or an audio track can be trimmed to.
const minPiece = Duration(milliseconds: 500);

Duration _clamp(Duration value, Duration low, Duration high) =>
    value < low ? low : (value > high ? high : value);

Duration _max(Duration a, Duration b) => a > b ? a : b;
Duration _min(Duration a, Duration b) => a < b ? a : b;

extension TimelineEdits on Composition {
  // ------------------------------------------------------------------ clips

  /// The clip at [from] moved to [to] (its index once moved).
  Composition moveClip(int from, int to) {
    if (from == to) return this;
    final list = [...clips];
    final clip = list.removeAt(from);
    list.insert(to.clamp(0, list.length), clip);
    return copyWith(clips: list);
  }

  /// Without the clip at [index] - null when it was the only one.
  Composition? removeClip(int index) {
    if (clips.length <= 1) return null;
    return copyWith(clips: [...clips]..removeAt(index));
  }

  Composition replaceClip(int index, MediaLayer clip) =>
      copyWith(clips: [...clips]..[index] = clip);

  /// [added] put in at [index] (the end when null).
  Composition insertClips(List<MediaLayer> added, {int? index}) =>
      copyWith(clips: [...clips]..insertAll(index ?? clips.length, added));

  /// Room left before the edit reaches [maxTotal].
  Duration remaining(Duration maxTotal) =>
      _max(Duration.zero, maxTotal - naturalDuration);

  /// The clip under [at] cut in two there. Null when [at] is within
  /// [minPiece] of the clip's ends - nothing to cut.
  Composition? splitAt(Duration at) {
    final (:index, :offset) = locate(at);
    final clip = clips[index];
    if (offset < minPiece || clip.length - offset < minPiece) return null;
    final MediaLayer first, second;
    if (clip.source.isVideo) {
      final range = clip.usedRange;
      final cut = range.start + offset;
      first = clip.copyWith(trim: TrimRange(range.start, cut));
      second = clip.copyWith(trim: TrimRange(cut, range.end));
    } else {
      first = clip.copyWith(duration: offset);
      second = clip.copyWith(duration: clip.length - offset);
    }
    return copyWith(clips: [...clips]..replaceRange(index, index + 1, [first, second]));
  }

  /// The clip at [index] with its edges moved: [head] moves its start
  /// (positive trims more off the front of a video, or shortens a photo),
  /// [tail] moves its end (positive gives a video more of itself, or keeps a
  /// photo up longer).
  ///
  /// Held to the video's own length, to [minPiece], and to the edit's
  /// [maxTotal] - a clip only grows into the room left.
  Composition resizeClip(
    int index, {
    Duration head = Duration.zero,
    Duration tail = Duration.zero,
    required Duration maxTotal,
  }) {
    final clip = clips[index];
    final room = remaining(maxTotal);
    if (!clip.source.isVideo) {
      final length = _clamp(
          clip.length - head + tail, minPiece, clip.length + room);
      return replaceClip(index, clip.copyWith(duration: length));
    }
    final range = clip.usedRange;
    final full = clip.source.duration ?? range.end;
    var start = _clamp(range.start + head, Duration.zero, range.end - minPiece);
    var end = _clamp(range.end + tail, start + minPiece, full);
    final grown = (end - start) - range.length;
    if (grown > room) {
      // Only as much more as there is room for, from the edge being moved.
      if (tail != Duration.zero) {
        end -= grown - room;
      } else {
        start += grown - room;
      }
    }
    return replaceClip(index, clip.copyWith(trim: TrimRange(start, end)));
  }

  // ------------------------------------------------------------------ audio

  /// The free stretches of the audio row, ignoring the track at [except]:
  /// (start, end) pairs, the last one open-ended (null end).
  List<(Duration, Duration?)> _gaps({int? except}) {
    final others = [
      for (var i = 0; i < audio.length; i++)
        if (i != except) audio[i]
    ]..sort((a, b) => a.start.compareTo(b.start));
    final gaps = <(Duration, Duration?)>[];
    var from = Duration.zero;
    for (final track in others) {
      if (track.start > from) gaps.add((from, track.start));
      from = _max(from, track.end);
    }
    gaps.add((from, null));
    return gaps;
  }

  List<AudioTrack> _sorted(List<AudioTrack> tracks) =>
      tracks..sort((a, b) => a.start.compareTo(b.start));

  /// Where a track added at [at] goes, and how long it can be there: the
  /// free stretch at [at] - or the next one with room - up to the next
  /// track or the edit's end. Null when there is no room from [at] on.
  ({Duration start, Duration room})? trackSlot(Duration at) {
    final end = naturalDuration;
    for (final (from, to) in _gaps()) {
      final start = _max(at, from);
      final limit = _min(to ?? end, end);
      if (limit - start < minPiece) continue;
      return (start: start, room: limit - start);
    }
    return null;
  }

  /// [track] laid in at its [trackSlot] from [at], cut to fit it. Null when
  /// there is no room from [at] on.
  Composition? addTrack(AudioTrack track, {required Duration at}) {
    final slot = trackSlot(at);
    if (slot == null) return null;
    final length = _min(track.length, slot.room);
    final placed = track.copyWith(
      start: slot.start,
      trim: TrimRange(track.trim.start, track.trim.start + length),
    );
    return copyWith(audio: _sorted([...audio, placed]));
  }

  /// The track at [index] dropped at [start]: in the free stretch nearest
  /// there that it fits whole. Unmoved when it fits nowhere.
  Composition moveTrack(int index, Duration start) {
    final track = audio[index];
    final latest = _max(Duration.zero, naturalDuration - minPiece);
    final wanted = _clamp(start, Duration.zero, latest);
    Duration? best;
    for (final (from, to) in _gaps(except: index)) {
      if (to != null && to - from < track.length) continue;
      final place = to == null
          ? _max(wanted, from)
          : _clamp(wanted, from, to - track.length);
      if (best == null || (place - wanted).abs() < (best - wanted).abs()) {
        best = place;
      }
    }
    if (best == null || best == track.start) return this;
    return copyWith(
        audio: _sorted([...audio]..[index] = track.copyWith(start: best)));
  }

  /// The track at [index] with its edges moved: [head] moves its start
  /// (positive cuts the front of its part; the rest stays where it was in
  /// the edit), [tail] moves its end. Held to the file, [minPiece], and the
  /// tracks either side.
  Composition resizeTrack(
    int index, {
    Duration head = Duration.zero,
    Duration tail = Duration.zero,
  }) {
    final track = audio[index];
    final previousEnd = index > 0 ? audio[index - 1].end : Duration.zero;
    final nextStart = index + 1 < audio.length ? audio[index + 1].start : null;

    final shift = _clamp(
      head,
      _max(previousEnd - track.start, -track.trim.start),
      track.length - minPiece,
    );
    final start = track.start + shift;
    final trimStart = track.trim.start + shift;

    var maxEnd = track.trim.end + (track.fileLength == null
        ? tail
        : track.fileLength! - track.trim.end);
    if (nextStart != null) {
      maxEnd = _min(maxEnd, trimStart + (nextStart - start));
    }
    final trimEnd = _clamp(track.trim.end + tail, trimStart + minPiece,
        _max(maxEnd, trimStart + minPiece));
    return copyWith(
      audio: [...audio]..[index] = track.copyWith(
          start: start, trim: TrimRange(trimStart, trimEnd)),
    );
  }

  Composition removeTrack(int index) =>
      copyWith(audio: [...audio]..removeAt(index));

  Composition replaceTrack(int index, AudioTrack track) =>
      copyWith(audio: [...audio]..[index] = track);

  /// The track at [index] cut in two at [at] (a time in the edit). Null
  /// within [minPiece] of its ends.
  Composition? splitTrack(int index, Duration at) {
    final track = audio[index];
    final offset = at - track.start;
    if (offset < minPiece || track.length - offset < minPiece) return null;
    final cut = track.trim.start + offset;
    final first = track.copyWith(trim: TrimRange(track.trim.start, cut));
    final second =
        track.copyWith(start: at, trim: TrimRange(cut, track.trim.end));
    return copyWith(
        audio: [...audio]..replaceRange(index, index + 1, [first, second]));
  }

  /// Short fades where a track's sound is cut, so it doesn't start or stop
  /// on a click: in, where its part starts inside the file; out, over its
  /// last second. Not where it runs straight on into its own continuation
  /// (a split) - that would dip the sound mid-song.
  Composition withAutoFades() {
    final tracks = <AudioTrack>[];
    for (var i = 0; i < audio.length; i++) {
      final track = audio[i];
      bool continues(AudioTrack a, AudioTrack b) =>
          a.path == b.path && a.end == b.start && a.trim.end == b.trim.start;
      final joinedBefore = i > 0 && continues(audio[i - 1], track);
      final joinedAfter = i + 1 < audio.length && continues(track, audio[i + 1]);
      tracks.add(track.copyWith(
        fadeIn: track.trim.start > Duration.zero && !joinedBefore
            ? const Duration(milliseconds: 300)
            : Duration.zero,
        fadeOut: track.length >= const Duration(seconds: 4) && !joinedAfter
            ? const Duration(seconds: 1)
            : Duration.zero,
      ));
    }
    return copyWith(audio: tracks);
  }
}
