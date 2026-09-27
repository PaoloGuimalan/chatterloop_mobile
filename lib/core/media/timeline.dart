/// Editing a [Composition] along its timeline - what the editor's cards do:
/// reorder, trim, slide, split and remove clips; place, trim, split, stack
/// and remove overlays; place, trim, split and remove audio tracks. Pure, so
/// every rule is tested (test/timeline_test.dart).
///
/// The rules:
///  - The main clips play in order. Each sits straight after the one before
///    - or after a BLANK the user left ([MediaLayer.gapBefore]), black and
///    silent, of any length. Trimming a clip carries the clips after it
///    along, blanks and all, so what sits together stays together; a clip
///    taken out closes up behind it, and the blank before it stays.
///  - SLIDING a picked piece - clip, overlay or track - moves it along its
///    row by exactly as much as it was dragged, however little, opening or
///    closing the blanks either side of it. Nothing sticks to anything
///    unless asked ([clipBlanks] and the like say how far it is to its
///    neighbours, to slide it against one). What it runs into is pushed on
///    ahead of it - nothing overlaps - down to the start, or up to
///    [maxTotal].
///  - The edit runs as long as whatever ends last - a layer or a song may
///    run past the clips, the picture blank under it - up to [maxTotal]
///    (the profile's length), which nothing grows past.
///  - A clip, overlay or track is never trimmed shorter than [minPiece].
///  - Overlays and tracks sit in LANES. Within a lane nothing overlaps;
///    across lanes things play together - a higher overlay lane is drawn
///    over a lower one, audio lanes are mixed. A HELD overlay or track
///    dropped on a lane lands where it was dropped when it fits there, else
///    in the free stretch of that lane nearest it - so dropping one past
///    another swaps them. Lanes left empty close up.
///  - Something new goes in at the playhead, on the lowest lane free there,
///    else on a lane of its own.
library;

import 'dart:math' as math;

import 'package:chatterloop_app/core/media/composition.dart';

/// The shortest a clip, an overlay or an audio track can be trimmed to.
const minPiece = Duration(milliseconds: 500);

/// The most overlay lanes: every one is another picture decoded at once,
/// in the preview and in the render.
const maxOverlayLanes = 3;

/// The most audio lanes - songs playing at once.
const maxAudioLanes = 4;

Duration _clamp(Duration value, Duration low, Duration high) =>
    value < low ? low : (value > high ? high : value);

Duration _max(Duration a, Duration b) => a > b ? a : b;
Duration _min(Duration a, Duration b) => a < b ? a : b;

/// [clip] with no blank before it - itself when it has none.
MediaLayer _stuck(MediaLayer clip) => clip.gapBefore == Duration.zero
    ? clip
    : clip.copyWith(gapBefore: Duration.zero);

/// Something laid on a lane - where it plays, on which.
typedef _Span = ({Duration start, Duration end, int lane});

/// Where something new goes: its lane, where it starts, and how long it
/// can be there.
typedef LaneSlot = ({int lane, Duration start, Duration room});

/// The free stretches of [lane], ignoring the span at [except]: (start, end)
/// pairs, the last one open-ended (null end).
List<(Duration, Duration?)> _gapsIn(List<_Span> spans, int lane,
    {int? except}) {
  final others = [
    for (var i = 0; i < spans.length; i++)
      if (i != except && spans[i].lane == lane) spans[i]
  ]..sort((a, b) => a.start.compareTo(b.start));
  final gaps = <(Duration, Duration?)>[];
  var from = Duration.zero;
  for (final span in others) {
    if (span.start > from) gaps.add((from, span.start));
    from = _max(from, span.end);
  }
  gaps.add((from, null));
  return gaps;
}

/// The room on [lane] from [at] - up to whatever comes next on it, or
/// [end] - when [at] is in a free stretch with at least [minPiece] of it.
Duration? _roomAt(List<_Span> spans, int lane, Duration at, Duration end) {
  for (final (from, to) in _gapsIn(spans, lane)) {
    if (at < from) return null;
    if (to != null && at >= to) continue;
    final room = _min(to ?? end, end) - at;
    return room < minPiece ? null : room;
  }
  return null;
}

/// Where something added at [at] goes: the lowest of the [lanes] free there,
/// else a lane of its own over them - null when there is no room from [at]
/// to [end], or already [maxLanes].
LaneSlot? _slot(List<_Span> spans, int lanes, Duration at, Duration end,
    int maxLanes) {
  if (end - at < minPiece) return null;
  for (var lane = 0; lane < lanes; lane++) {
    final room = _roomAt(spans, lane, at, end);
    if (room != null) return (lane: lane, start: at, room: room);
  }
  if (lanes >= maxLanes) return null;
  return (lane: lanes, start: at, room: end - at);
}

/// Where the span at [index] (null: one not yet placed) of [length], dropped
/// at [wanted] on [lane], lands: in the free stretch of that lane nearest
/// [wanted] that takes it whole, starting no later than [latest] - right
/// where it was dropped when it fits there. A lane with nothing on it takes
/// it anywhere. Null when it fits nowhere there, or it would make more than
/// [maxLanes] lanes.
Duration? _landing(
  List<_Span> spans,
  int? index,
  int lane,
  Duration wanted,
  Duration length,
  Duration latest,
  int maxLanes,
) {
  final lanes = {
    for (var i = 0; i < spans.length; i++)
      if (i != index) spans[i].lane
  };
  if (!lanes.contains(lane) && lanes.length >= maxLanes) return null;
  final want = _clamp(wanted, Duration.zero, latest);
  Duration? best;
  for (final (from, to) in _gapsIn(spans, lane, except: index)) {
    if (to != null && to - from < length) continue;
    final last = to == null ? null : to - length;
    final place = last == null ? _max(want, from) : _clamp(want, from, last);
    if (best == null || (place - want).abs() < (best - want).abs()) {
      best = place;
    }
  }
  return best;
}

/// The starts of [row] - one lane's pieces in time order, none over
/// another - with the one at [index] moved [by]: by all of it, however
/// little, but not before the start nor past [end]. Whatever it runs into
/// is pushed on ahead of it - the pieces never overlap - and nothing else
/// moves.
List<Duration> _pushed(
    List<({Duration start, Duration length})> row, int index, Duration by,
    Duration end) {
  var lengthBefore = Duration.zero;
  for (var k = 0; k < index; k++) {
    lengthBefore += row[k].length;
  }
  var lengthFrom = Duration.zero;
  for (var k = index; k < row.length; k++) {
    lengthFrom += row[k].length;
  }
  final at = row[index].start;
  // Back until everything before it is packed against the start; on until
  // everything from it on is packed against the end.
  final earliest = _min(lengthBefore - at, Duration.zero);
  final latest = _max(end - lengthFrom - at, Duration.zero);
  final move = _clamp(by, earliest, latest);
  final starts = [for (final piece in row) piece.start];
  starts[index] = at + move;
  for (var k = index + 1; k < row.length; k++) {
    starts[k] = _max(starts[k], starts[k - 1] + row[k - 1].length);
  }
  for (var k = index - 1; k >= 0; k--) {
    starts[k] = _min(starts[k], starts[k + 1] - row[k].length);
  }
  return starts;
}

/// The starts of [spans] with the one at [index] slid [by] along its lane -
/// see [_pushed]; the other lanes as they are.
List<Duration> _slid(List<_Span> spans, int index, Duration by, Duration end) {
  final lane = spans[index].lane;
  final row = [
    for (var i = 0; i < spans.length; i++)
      if (spans[i].lane == lane) i
  ]..sort((a, b) => spans[a].start.compareTo(spans[b].start));
  final moved = _pushed([
    for (final i in row)
      (start: spans[i].start, length: spans[i].end - spans[i].start)
  ], row.indexOf(index), by, end);
  final starts = [for (final span in spans) span.start];
  for (var k = 0; k < row.length; k++) {
    starts[row[k]] = moved[k];
  }
  return starts;
}

/// How far the piece in a row is from its neighbours: the blank [before]
/// it, back to the piece before it - or, [first] (nothing before it), to
/// the start; and the blank [after] it, on to the next piece - null when
/// nothing comes after it.
typedef Blanks = ({Duration before, bool first, Duration? after});

/// [Blanks] around the span at [index], in its lane.
Blanks _blanksAround(List<_Span> spans, int index) {
  final me = spans[index];
  Duration? previousEnd;
  Duration? nextStart;
  for (var i = 0; i < spans.length; i++) {
    final other = spans[i];
    if (i == index || other.lane != me.lane) continue;
    if (other.start < me.start) {
      if (previousEnd == null || other.end > previousEnd) {
        previousEnd = other.end;
      }
    } else if (nextStart == null || other.start < nextStart) {
      nextStart = other.start;
    }
  }
  return (
    before: _max(me.start - (previousEnd ?? Duration.zero), Duration.zero),
    first: previousEnd == null,
    after: nextStart == null ? null : _max(nextStart - me.end, Duration.zero),
  );
}

/// Whether [start]..[start]+[length] on [lane] is clear (the span at
/// [except] aside).
bool _clear(List<_Span> spans, int lane, Duration start, Duration length,
    {int? except}) {
  final end = start + length;
  for (var i = 0; i < spans.length; i++) {
    if (i == except || spans[i].lane != lane) continue;
    if (spans[i].start < end && start < spans[i].end) return false;
  }
  return true;
}

/// Lane numbers closed up (a lane left empty goes, the ones over it move
/// down), then in lane-then-time order.
List<T> _tidy<T>(
  List<T> items,
  int Function(T) laneOf,
  Duration Function(T) startOf,
  T Function(T, int) withLane,
) {
  final used = {for (final item in items) laneOf(item)}.toList()..sort();
  final renumber = {for (var k = 0; k < used.length; k++) used[k]: k};
  final tidy = [
    for (final item in items)
      laneOf(item) == renumber[laneOf(item)]
          ? item
          : withLane(item, renumber[laneOf(item)]!)
  ];
  tidy.sort((a, b) {
    final byLane = laneOf(a).compareTo(laneOf(b));
    return byLane != 0 ? byLane : startOf(a).compareTo(startOf(b));
  });
  return tidy;
}

/// [clip] cut to at most [room] long - a video from the start of its part.
MediaLayer _cutTo(MediaLayer clip, Duration room) {
  if (clip.length <= room) return clip;
  if (clip.source.isVideo) {
    final range = clip.usedRange;
    return clip.copyWith(trim: TrimRange(range.start, range.start + room));
  }
  return clip.copyWith(duration: room);
}

extension TimelineEdits on Composition {
  // ------------------------------------------------------------------ clips

  /// The clip at [from] moved to [to] (its index once moved): out of its
  /// place, the clips after it closing up (the blank before it stays where
  /// it was), and in straight after the clip before its new place.
  Composition moveClip(int from, int to) {
    if (from == to) return this;
    final clip = clips[from];
    final list = _withoutClip(from).clips.toList()
      ..insert(to.clamp(0, clips.length - 1), _stuck(clip));
    return copyWith(clips: list);
  }

  /// Without the clip at [index] - the ones after it closing up, the blank
  /// before it kept. Null when nothing at all would be left.
  Composition? removeClip(int index) {
    if (clips.length <= 1 && overlays.isEmpty && audio.isEmpty) return null;
    return _withoutClip(index);
  }

  Composition _withoutClip(int index) {
    final list = [...clips];
    final clip = list.removeAt(index);
    // The blank before it stays, before the clip that now follows.
    if (clip.gapBefore > Duration.zero && index < list.length) {
      list[index] = list[index]
          .copyWith(gapBefore: list[index].gapBefore + clip.gapBefore);
    }
    return copyWith(clips: list);
  }

  Composition replaceClip(int index, MediaLayer clip) =>
      copyWith(clips: [...clips]..[index] = clip);

  /// [added] put in at [index] (the end when null), straight after the clip
  /// before - the clips after them carried along.
  Composition insertClips(List<MediaLayer> added, {int? index}) =>
      copyWith(
          clips: [...clips]
            ..insertAll(index ?? clips.length, [for (final c in added) _stuck(c)]));

  /// Room the main run has left before it reaches [maxTotal].
  Duration remaining(Duration maxTotal) =>
      _max(Duration.zero, maxTotal - mainEnd);

  /// The clip under [at] cut in two there. Null in a blank, or within
  /// [minPiece] of the clip's ends - nothing to cut.
  Composition? splitAt(Duration at) {
    final located = locate(at);
    if (located == null) return null;
    final (:index, :offset) = located;
    final clip = clips[index];
    if (offset < minPiece || clip.length - offset < minPiece) return null;
    final (first, second) = _splitClip(clip, offset);
    return copyWith(clips: [...clips]
      ..replaceRange(index, index + 1, [first, _stuck(second)]));
  }

  /// The clip at [index] with its edges moved: [head] moves its start
  /// (positive trims more off the front of a video, or shortens a photo),
  /// [tail] moves its end (positive gives a video more of itself, or keeps a
  /// photo up longer). It stays where it starts; the clips after it are
  /// carried along.
  ///
  /// Held to the video's own length, to [minPiece], and to [maxTotal] - a
  /// clip only grows into the room the run has left.
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

  /// The clip at [index] slid [by] along the timeline - all of it, however
  /// little: a blank opens behind it, the one ahead of it closes. The
  /// others stay put, but for the ones it runs into, pushed on ahead of it
  /// - back to the start, or on until the run reaches [maxTotal].
  Composition slideClip(int index, Duration by, {required Duration maxTotal}) {
    final starts = clipStarts;
    final moved = _pushed([
      for (var k = 0; k < clips.length; k++)
        (start: starts[k], length: clips[k].length)
    ], index, by, maxTotal);
    var changed = false;
    var end = Duration.zero;
    final list = <MediaLayer>[];
    for (var k = 0; k < clips.length; k++) {
      final gap = moved[k] - end;
      if (gap == clips[k].gapBefore) {
        list.add(clips[k]);
      } else {
        changed = true;
        list.add(clips[k].copyWith(gapBefore: gap));
      }
      end = moved[k] + clips[k].length;
    }
    return changed ? copyWith(clips: list) : this;
  }

  /// The blanks either side of the clip at [index] (see [Blanks]).
  Blanks clipBlanks(int index) => (
        before: clips[index].gapBefore,
        first: index == 0,
        after: index + 1 < clips.length ? clips[index + 1].gapBefore : null,
      );

  /// The main clip at [index] lifted out of the run into an overlay lane -
  /// shown over what plays there instead of in turn with it; the run closes
  /// up behind it. It goes where it played ([start] when given), on [lane]
  /// when given (the lane count for a lane of its own) - else the lowest
  /// lane free for it there, or a new one.
  ///
  /// Null when there is no lane for it.
  Composition? liftClip(int index,
      {Duration? start, int? lane, required Duration maxTotal}) {
    final rest = _withoutClip(index);
    final clip = _stuck(clips[index]);
    final at =
        rest._liftLanding(clip, start ?? clipStarts[index], lane, maxTotal);
    if (at == null) return null;
    return rest._withOverlays([
      ...rest.overlays,
      OverlayClip(clip: clip, start: at.start, lane: at.lane),
    ]);
  }

  /// Where [liftClip] would put the main clip at [index]: its lane and start
  /// (lane numbers as they are now). Null when it can't.
  ({int lane, Duration start})? liftLanding(
    int index, {
    required Duration start,
    int? lane,
    required Duration maxTotal,
  }) =>
      _withoutClip(index)._liftLanding(clips[index], start, lane, maxTotal);

  ({int lane, Duration start})? _liftLanding(
      MediaLayer clip, Duration wanted, int? lane, Duration maxTotal) {
    final spans = _overlaySpans;
    final latest = _max(Duration.zero, maxTotal - clip.length);
    if (lane != null) {
      final at = _landing(
          spans, null, lane, wanted, clip.length, latest, maxOverlayLanes);
      return at == null ? null : (lane: lane, start: at);
    }
    // Where it was, on the lowest lane with room for all of it there.
    final at = _clamp(wanted, Duration.zero, latest);
    final lanes = overlayLanes;
    for (var k = 0; k < lanes; k++) {
      if (_clear(spans, k, at, clip.length)) return (lane: k, start: at);
    }
    return lanes < maxOverlayLanes ? (lane: lanes, start: at) : null;
  }

  // --------------------------------------------------------------- overlays

  List<_Span> get _overlaySpans => [
        for (final o in overlays) (start: o.start, end: o.end, lane: o.lane)
      ];

  Composition _withOverlays(List<OverlayClip> list) => copyWith(
        overlays: _tidy<OverlayClip>(list, (o) => o.lane, (o) => o.start,
            (o, lane) => o.copyWith(lane: lane)),
      );

  /// Where an overlay added at [at] goes, and how long it can be there -
  /// up to whatever is next on its lane, or [maxTotal]. Null when there is
  /// no room.
  LaneSlot? overlaySlot(Duration at, {required Duration maxTotal}) =>
      _slot(_overlaySpans, overlayLanes, at, maxTotal, maxOverlayLanes);

  /// [clip] laid over the main run at its [overlaySlot] from [at], cut to
  /// fit it. Null when there is no room.
  Composition? addOverlay(MediaLayer clip,
      {required Duration at, required Duration maxTotal, TextCard? text}) {
    final slot = overlaySlot(at, maxTotal: maxTotal);
    if (slot == null) return null;
    return _withOverlays([
      ...overlays,
      OverlayClip(
          clip: _cutTo(_stuck(clip), slot.room),
          start: slot.start,
          lane: slot.lane,
          text: text),
    ]);
  }

  /// Where the overlay at [index] dropped at [start] on [lane] (the lane
  /// count: a lane of its own) would land. Null when it fits nowhere there.
  Duration? overlayLanding(
    int index,
    Duration start, {
    int? lane,
    required Duration maxTotal,
  }) {
    final overlay = overlays[index];
    return _landing(
      _overlaySpans,
      index,
      lane ?? overlay.lane,
      start,
      overlay.length,
      _max(Duration.zero, maxTotal - overlay.length),
      maxOverlayLanes,
    );
  }

  /// The overlay at [index] dropped at [start] - on [lane] when given: in
  /// the free stretch of that lane nearest there that it fits whole.
  /// Unmoved when it fits nowhere.
  Composition moveOverlay(
    int index,
    Duration start, {
    int? lane,
    required Duration maxTotal,
  }) {
    final overlay = overlays[index];
    final to = lane ?? overlay.lane;
    final at = overlayLanding(index, start, lane: to, maxTotal: maxTotal);
    if (at == null || (at == overlay.start && to == overlay.lane)) return this;
    return _withOverlays(
        [...overlays]..[index] = overlay.copyWith(start: at, lane: to));
  }

  /// The overlay at [index] slid [by] along its lane, like [slideClip]: all
  /// of it, the ones on its lane it runs into pushed on ahead of it. Each
  /// keeps its place in [overlays].
  Composition slideOverlay(int index, Duration by,
      {required Duration maxTotal}) {
    final starts = _slid(_overlaySpans, index, by, maxTotal);
    if (starts[index] == overlays[index].start) return this;
    return copyWith(overlays: [
      for (var i = 0; i < overlays.length; i++)
        if (starts[i] == overlays[i].start)
          overlays[i]
        else
          overlays[i].copyWith(start: starts[i])
    ]);
  }

  /// The blanks either side of the overlay at [index] on its lane (see
  /// [Blanks]).
  Blanks overlayBlanks(int index) => _blanksAround(_overlaySpans, index);

  /// The overlay at [index] with its edges moved, like [resizeClip]: held
  /// to its video's own length, [minPiece], whatever is either side of it
  /// in its lane, and [maxTotal].
  Composition resizeOverlay(
    int index, {
    Duration head = Duration.zero,
    Duration tail = Duration.zero,
    required Duration maxTotal,
  }) {
    final overlay = overlays[index];
    final clip = overlay.clip;
    final (previousEnd, nextStart) = _neighbours(_overlaySpans, index);
    final limit = _min(nextStart ?? maxTotal, maxTotal);

    if (!clip.source.isVideo) {
      final shift = _clamp(head, previousEnd - overlay.start,
          overlay.length - minPiece);
      final start = overlay.start + shift;
      final length = _clamp(overlay.length - shift + tail, minPiece,
          _max(minPiece, limit - start));
      return replaceOverlay(index,
          overlay.copyWith(start: start, clip: clip.copyWith(duration: length)));
    }
    final range = clip.usedRange;
    final shift = _clamp(
      head,
      _max(previousEnd - overlay.start, -range.start),
      overlay.length - minPiece,
    );
    final start = overlay.start + shift;
    final trimStart = range.start + shift;
    final full = clip.source.duration ?? range.end;
    final maxEnd = _min(full, trimStart + (limit - start));
    final trimEnd = _clamp(range.end + tail, trimStart + minPiece,
        _max(maxEnd, trimStart + minPiece));
    return replaceOverlay(
      index,
      overlay.copyWith(
          start: start, clip: clip.copyWith(trim: TrimRange(trimStart, trimEnd))),
    );
  }

  Composition replaceOverlay(int index, OverlayClip overlay) =>
      copyWith(overlays: [...overlays]..[index] = overlay);

  Composition removeOverlay(int index) =>
      _withOverlays([...overlays]..removeAt(index));

  /// The overlay at [index] cut in two at [at] (a time in the edit). Null
  /// within [minPiece] of its ends.
  Composition? splitOverlay(int index, Duration at) {
    final overlay = overlays[index];
    final offset = at - overlay.start;
    if (offset < minPiece || overlay.length - offset < minPiece) return null;
    final (first, second) = _splitClip(overlay.clip, offset);
    return copyWith(
      overlays: [...overlays]..replaceRange(index, index + 1, [
          overlay.copyWith(clip: first),
          overlay.copyWith(clip: second, start: at),
        ]),
    );
  }

  /// A copy of the overlay at [index] - straight after it on its lane when
  /// there is room there, else over it on a free lane. Null when neither.
  Composition? duplicateOverlay(int index, {required Duration maxTotal}) {
    final overlay = overlays[index];
    final room = _roomAt(_overlaySpans, overlay.lane, overlay.end, maxTotal);
    if (room != null) {
      return _withOverlays([
        ...overlays,
        overlay.copyWith(clip: _cutTo(overlay.clip, room), start: overlay.end),
      ]);
    }
    return addOverlay(overlay.clip,
        at: overlay.start, maxTotal: maxTotal, text: overlay.text);
  }

  /// The overlay at [index] drawn over the next one that shows at the same
  /// time as it: moved to the lane just over that one's. Null when nothing
  /// is over it - it is already on top.
  Composition? bringForward(int index) {
    final overlay = overlays[index];
    final over = [
      for (var j = 0; j < overlays.length; j++)
        if (j != index &&
            overlays[j].lane > overlay.lane &&
            _together(overlay, overlays[j]))
          overlays[j].lane
    ];
    if (over.isEmpty) return null;
    final lane = over.reduce(math.min) + 1;
    return _toLane(index, lane, insertAt: lane);
  }

  /// The overlay at [index] drawn under the next one that shows at the same
  /// time as it: moved to the lane just under that one's. Null when nothing
  /// is under it - only the main clips are.
  Composition? sendBackward(int index) {
    final overlay = overlays[index];
    final under = [
      for (var j = 0; j < overlays.length; j++)
        if (j != index &&
            overlays[j].lane < overlay.lane &&
            _together(overlay, overlays[j]))
          overlays[j].lane
    ];
    if (under.isEmpty) return null;
    final lane = under.reduce(math.max);
    return _toLane(index, lane - 1, insertAt: lane);
  }

  static bool _together(OverlayClip a, OverlayClip b) =>
      a.start < b.end && b.start < a.end;

  /// The overlay at [index] on [lane] at the same time, when that lane is
  /// clear for it then - else on a new lane put in at [insertAt], the lanes
  /// from there up moving up one. Null past [maxOverlayLanes].
  Composition? _toLane(int index, int lane, {required int insertAt}) {
    final overlay = overlays[index];
    final spans = _overlaySpans;
    if (lane >= 0 &&
        lane < overlayLanes &&
        _clear(spans, lane, overlay.start, overlay.length, except: index)) {
      return _withOverlays(
          [...overlays]..[index] = overlay.copyWith(lane: lane));
    }
    final moved = [
      for (var j = 0; j < overlays.length; j++)
        if (j == index)
          overlay.copyWith(lane: insertAt)
        else if (overlays[j].lane >= insertAt)
          overlays[j].copyWith(lane: overlays[j].lane + 1)
        else
          overlays[j]
    ];
    final next = _withOverlays(moved);
    return next.overlayLanes > maxOverlayLanes ? null : next;
  }

  /// The overlay at [index] put into the main run, at [slot] (a place in
  /// the order of the main clips) - by default the clip edge nearest where
  /// it starts. Null when the run has no room for it under [maxTotal].
  Composition? dropOverlay(int index,
      {required Duration maxTotal, int? slot}) {
    final overlay = overlays[index];
    if (overlay.length > remaining(maxTotal)) return null;
    final int at;
    if (slot != null) {
      at = slot.clamp(0, clips.length);
    } else {
      final edges = [...clipStarts, mainEnd];
      var nearest = 0;
      for (var k = 1; k < edges.length; k++) {
        if ((edges[k] - overlay.start).abs() <
            (edges[nearest] - overlay.start).abs()) {
          nearest = k;
        }
      }
      at = nearest;
    }
    return insertClips([overlay.clip], index: at)
        ._withOverlays([...overlays]..removeAt(index));
  }

  // ------------------------------------------------------------------ audio

  List<_Span> get _trackSpans => [
        for (final t in audio) (start: t.start, end: t.end, lane: t.lane)
      ];

  Composition _withAudio(List<AudioTrack> list) => copyWith(
        audio: _tidy<AudioTrack>(list, (t) => t.lane, (t) => t.start,
            (t, lane) => t.copyWith(lane: lane)),
      );

  /// Where a track added at [at] goes, and how long it can be there: the
  /// lowest lane free at [at], up to whatever is next on it or [maxTotal] -
  /// else a lane of its own, to be heard with the others. Null when there
  /// is no room.
  LaneSlot? trackSlot(Duration at, {required Duration maxTotal}) =>
      _slot(_trackSpans, audioLanes, at, maxTotal, maxAudioLanes);

  /// [track] laid in at its [trackSlot] from [at], cut to fit it. Null when
  /// there is no room.
  Composition? addTrack(AudioTrack track,
      {required Duration at, required Duration maxTotal}) {
    final slot = trackSlot(at, maxTotal: maxTotal);
    if (slot == null) return null;
    final length = _min(track.length, slot.room);
    final placed = track.copyWith(
      start: slot.start,
      lane: slot.lane,
      trim: TrimRange(track.trim.start, track.trim.start + length),
    );
    return _withAudio([...audio, placed]);
  }

  /// Where the track at [index] dropped at [start] on [lane] (the lane
  /// count: a lane of its own) would land. Null when it fits nowhere there.
  Duration? trackLanding(
    int index,
    Duration start, {
    int? lane,
    required Duration maxTotal,
  }) {
    final track = audio[index];
    return _landing(
      _trackSpans,
      index,
      lane ?? track.lane,
      start,
      track.length,
      _max(Duration.zero, maxTotal - track.length),
      maxAudioLanes,
    );
  }

  /// The track at [index] dropped at [start] - on [lane] when given: in the
  /// free stretch of that lane nearest there that it fits whole. Unmoved
  /// when it fits nowhere.
  Composition moveTrack(
    int index,
    Duration start, {
    int? lane,
    required Duration maxTotal,
  }) {
    final track = audio[index];
    final to = lane ?? track.lane;
    final at = trackLanding(index, start, lane: to, maxTotal: maxTotal);
    if (at == null || (at == track.start && to == track.lane)) return this;
    return _withAudio([...audio]..[index] = track.copyWith(start: at, lane: to));
  }

  /// The track at [index] slid [by] along its lane, like [slideClip]: all
  /// of it, the ones on its lane it runs into pushed on ahead of it. Each
  /// keeps its place in [audio].
  Composition slideTrack(int index, Duration by,
      {required Duration maxTotal}) {
    final starts = _slid(_trackSpans, index, by, maxTotal);
    if (starts[index] == audio[index].start) return this;
    return copyWith(audio: [
      for (var i = 0; i < audio.length; i++)
        if (starts[i] == audio[i].start)
          audio[i]
        else
          audio[i].copyWith(start: starts[i])
    ]);
  }

  /// The blanks either side of the track at [index] on its lane (see
  /// [Blanks]).
  Blanks trackBlanks(int index) => _blanksAround(_trackSpans, index);

  /// The track at [index] with its edges moved: [head] moves its start
  /// (positive cuts the front of its part; the rest stays where it was in
  /// the edit), [tail] moves its end. Held to the file, [minPiece], the
  /// tracks either side of it in its lane, and [maxTotal].
  Composition resizeTrack(
    int index, {
    Duration head = Duration.zero,
    Duration tail = Duration.zero,
    required Duration maxTotal,
  }) {
    final track = audio[index];
    final (previousEnd, nextStart) = _neighbours(_trackSpans, index);

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
    maxEnd = _min(maxEnd, trimStart + ((nextStart ?? maxTotal) - start));
    maxEnd = _min(maxEnd, trimStart + (maxTotal - start));
    final trimEnd = _clamp(track.trim.end + tail, trimStart + minPiece,
        _max(maxEnd, trimStart + minPiece));
    return copyWith(
      audio: [...audio]..[index] = track.copyWith(
          start: start, trim: TrimRange(trimStart, trimEnd)),
    );
  }

  Composition removeTrack(int index) => _withAudio([...audio]..removeAt(index));

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
          a.lane == b.lane &&
          a.path == b.path &&
          a.end == b.start &&
          a.trim.end == b.trim.start;
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

  // ----------------------------------------------------------------- shared

  /// Where the span before the one at [index] on its lane ends (zero when
  /// none), and where the one after it starts (null when none).
  static (Duration, Duration?) _neighbours(List<_Span> spans, int index) {
    final me = spans[index];
    var previousEnd = Duration.zero;
    Duration? nextStart;
    for (var i = 0; i < spans.length; i++) {
      final other = spans[i];
      if (i == index || other.lane != me.lane) continue;
      if (other.start < me.start) {
        previousEnd = _max(previousEnd, other.end);
      } else if (nextStart == null || other.start < nextStart) {
        nextStart = other.start;
      }
    }
    return (previousEnd, nextStart);
  }

  /// [clip] cut [offset] into it: the two pieces, the same media either
  /// side.
  static (MediaLayer, MediaLayer) _splitClip(MediaLayer clip, Duration offset) {
    if (clip.source.isVideo) {
      final range = clip.usedRange;
      final cut = range.start + offset;
      return (
        clip.copyWith(trim: TrimRange(range.start, cut)),
        clip.copyWith(trim: TrimRange(cut, range.end)),
      );
    }
    return (
      clip.copyWith(duration: offset),
      clip.copyWith(duration: clip.length - offset),
    );
  }
}
