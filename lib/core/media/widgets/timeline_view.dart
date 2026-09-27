import 'dart:io';
import 'dart:math' as math;

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/timeline.dart';
import 'package:chatterloop_app/core/media/widgets/trim_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What a card on the timeline is: a main clip, an overlay, an audio track.
enum TimelineKind { clip, overlay, track }

/// What is picked on the timeline: a card, by kind and index.
@immutable
class TimelineSelection {
  final TimelineKind kind;
  final int index;

  const TimelineSelection.clip(this.index) : kind = TimelineKind.clip;
  const TimelineSelection.overlay(this.index) : kind = TimelineKind.overlay;
  const TimelineSelection.track(this.index) : kind = TimelineKind.track;

  bool get isClip => kind == TimelineKind.clip;
  bool get isOverlay => kind == TimelineKind.overlay;
  bool get isTrack => kind == TimelineKind.track;

  @override
  bool operator ==(Object other) =>
      other is TimelineSelection && other.kind == kind && other.index == index;

  @override
  int get hashCode => Object.hash(kind, index);

  @override
  String toString() => 'TimelineSelection.${kind.name}($index)';
}

/// The editor's timeline, like an editing app's: a ruler; the OVERLAY lanes,
/// the top one on top as on the canvas; the main CLIPS as cards in a row
/// (each as wide as it is long, with any blank left between them); the
/// AUDIO lanes under them - with the playhead fixed in the middle and the
/// timeline moving under it.
///
///  - Scroll the timeline to scrub; while playing it scrolls itself.
///  - Tap a card to pick it; a picked card has handles on its ends - drag
///    them to trim. A picked card drags along its row by just as much as
///    the finger moves - a blank opens behind it, of any length - pushing
///    on what it runs into. Nothing sticks to anything: the editor's
///    Anchor buttons put a card against its neighbour.
///  - Hold any card and move it: a clip along the main row to reorder it,
///    or up into an overlay lane - above the top one for a lane of its own;
///    an overlay to another time or lane, or down into the main row; a song
///    to another time or lane - below the last one for a lane of its own.
///
/// Edits come out through [onEdit] as the finger moves, then [onEditEnd].
class TimelineView extends StatefulWidget {
  final Composition edit;
  final ValueListenable<Duration> position;

  /// The longest the edit may be - trimming a clip longer stops there.
  final Duration maxTotal;

  /// A video file's picture for its cards, by path.
  final Map<String, String> thumbnails;

  final TimelineSelection? selection;
  final ValueChanged<TimelineSelection?> onSelect;
  final ValueChanged<Composition> onEdit;
  final VoidCallback onEditEnd;

  /// The user moved the timeline to [Duration] - scrubbing.
  final ValueChanged<Duration> onSeek;
  final VoidCallback onScrubStart;
  final VoidCallback onScrubEnd;

  final VoidCallback onAddMedia;
  final VoidCallback onAddAudio;

  /// The most height it takes; with more lanes than fit, they scroll up
  /// and down. Null: as tall as its lanes.
  final double? maxHeight;

  final bool enabled;

  const TimelineView({
    super.key,
    required this.edit,
    required this.position,
    required this.maxTotal,
    required this.thumbnails,
    required this.selection,
    required this.onSelect,
    required this.onEdit,
    required this.onEditEnd,
    required this.onSeek,
    required this.onScrubStart,
    required this.onScrubEnd,
    required this.onAddMedia,
    required this.onAddAudio,
    this.maxHeight,
    this.enabled = true,
  });

  /// Timeline pixels per second of edit.
  static const pxPerSecond = 48.0;

  static const rulerHeight = 18.0;
  static const overlayHeight = 44.0;
  static const clipHeight = 58.0;
  static const trackHeight = 42.0;
  static const laneGap = 6.0;

  /// How tall the timeline is for [edit], all its lanes showing.
  static double heightFor(Composition edit) => _Rows(edit).height;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

/// Where each row of the timeline is, for an edit: the ruler, the overlay
/// lanes top lane first, the main row, the audio lanes (one row for "Add
/// music" when there are none).
class _Rows {
  final int overlays;
  final int tracks;

  _Rows(Composition edit)
      : overlays = edit.overlayLanes,
        tracks = edit.audioLanes;

  static const _overlayRow = TimelineView.overlayHeight + TimelineView.laneGap;
  static const _trackRow = TimelineView.trackHeight + TimelineView.laneGap;

  double overlayTop(int lane) =>
      TimelineView.rulerHeight + (overlays - 1 - lane) * _overlayRow;

  double get mainTop => TimelineView.rulerHeight + overlays * _overlayRow;

  double trackTop(int lane) =>
      mainTop + TimelineView.clipHeight + TimelineView.laneGap + lane * _trackRow;

  double get height => trackTop(math.max(tracks, 1)) + 2;

  /// The overlay lane at [y]: its number - the lane count (a new lane over
  /// the others) above them all - or null on the main row or under it.
  int? overlayLaneAt(double y) {
    if (y >= mainTop - 8) return null;
    if (y < TimelineView.rulerHeight) return overlays;
    final fromTop = ((y - TimelineView.rulerHeight) / _overlayRow).floor();
    return (overlays - 1 - fromTop).clamp(0, math.max(overlays - 1, 0)).toInt();
  }

  /// The audio lane at [y]: its number - the lane count (a new lane under
  /// the others) below them all.
  int trackLaneAt(double y) {
    final lane = ((y - trackTop(0)) / _trackRow).floor();
    return lane < 0 ? 0 : math.min(lane, tracks);
  }
}

/// Where a held card would go if let go now: a place in the main run
/// ([slot]), or a [lane] of overlays or tracks (the lane count: a new one)
/// from [start].
@immutable
class _Landing {
  final TimelineKind into;
  final int slot;
  final int lane;
  final Duration start;

  const _Landing.main(this.slot)
      : into = TimelineKind.clip,
        lane = 0,
        start = Duration.zero;

  const _Landing.lane(this.into, this.lane, this.start) : slot = 0;
}

class _TimelineViewState extends State<TimelineView> {
  static const _pps = TimelineView.pxPerSecond;
  static const _handle = 16.0;
  static const _addButton = 46.0;

  /// Overlays' cards: the layers colour, to tell them from the main clips.
  static const _overlayTint = Color(0xFF8E7CFF);

  final _scroll = ScrollController();
  final _lanesScroll = ScrollController();
  final _content = GlobalKey();
  bool _userScrolling = false;

  /// A card held and moved: which, where on it the finger took it, where
  /// its top-left is now, and where it would land.
  TimelineSelection? _held;
  Offset _heldGrab = Offset.zero;
  Offset _heldAt = Offset.zero;
  Size _heldSize = Size.zero;
  _Landing? _landing;

  /// The edit as it was when a trim or move started - drags apply their
  /// whole distance to it, so nothing accumulates rounding.
  Composition? _before;

  double _px(Duration d) => d.inMicroseconds / 1e6 * _pps;
  Duration _time(double px) =>
      Duration(microseconds: (px / _pps * 1e6).round());

  /// How far a picked card has been slid so far - to the millisecond, as
  /// the edit is saved.
  Duration get _slid =>
      Duration(milliseconds: (_slideDx / _pps * 1000).round());

  @override
  void initState() {
    super.initState();
    widget.position.addListener(_follow);
  }

  @override
  void didUpdateWidget(TimelineView old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) {
      old.position.removeListener(_follow);
      widget.position.addListener(_follow);
    }
  }

  @override
  void dispose() {
    widget.position.removeListener(_follow);
    _scroll.dispose();
    _lanesScroll.dispose();
    super.dispose();
  }

  /// The timeline keeps the playhead's time under the middle line.
  void _follow() {
    if (_userScrolling || !_scroll.hasClients) return;
    final target = _px(widget.position.value)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    if ((target - _scroll.offset).abs() > 0.5) _scroll.jumpTo(target);
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _userScrolling = true;
      widget.onScrubStart();
    } else if (n is ScrollUpdateNotification && _userScrolling) {
      widget.onSeek(_time(n.metrics.pixels));
    } else if (n is ScrollEndNotification && _userScrolling) {
      _userScrolling = false;
      widget.onSeek(_time(n.metrics.pixels));
      widget.onScrubEnd();
    }
    return false;
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final half = box.maxWidth / 2;
      final edit = widget.edit;
      final rows = _Rows(edit);
      final total = edit.naturalDuration;
      // The edit runs to whatever ends last. After it, room to drag things
      // on past the end (the edit grows, blank under them) - while
      // something is being moved, to the most the edit may be.
      final contentEnd = _px(total);
      final moving = _held != null || _before != null;
      final after = moving
          ? math.max(_px(widget.maxTotal) - contentEnd, 0.0)
          : _px(const Duration(seconds: 4));
      final width = contentEnd + math.max(_addButton + 12, after + 12);
      final height = rows.height;
      final cap = widget.maxHeight;
      final visible = cap == null ? height : math.min(height, cap);

      // Every card is keyed and stays in this one Stack, the held one too
      // (moved to the end, to paint on top): rebuilt anywhere else, it
      // would drop the finger's gesture mid-drag.
      final cards = <Widget>[
        ..._overlayCards(edit, rows, total),
        ..._clipCards(edit, rows),
        ..._trackCards(edit, rows, total),
      ];
      final held = _held;
      if (held != null) {
        final key = _cardKey(held);
        final at = cards.indexWhere((card) => card.key == key);
        if (at >= 0) cards.add(cards.removeAt(at));
      }

      Widget lanes = NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          physics: widget.enabled
              ? const ClampingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: half),
          // Its own layer: while playing, the timeline scrolls every frame,
          // and without this every card was painted again each time - now
          // the painted lanes just move.
          child: RepaintBoundary(
            child: SizedBox(
              key: _content,
              width: width,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    key: const ValueKey('ruler'),
                    left: 0,
                    top: 0,
                    width: width,
                    height: TimelineView.rulerHeight,
                    child: CustomPaint(painter: _RulerPainter(width, _pps)),
                  ),
                  ..._laneBands(edit, rows, width),
                  ..._landingMarks(edit, rows, width),
                  ...cards,
                ],
              ),
            ),
          ),
        ),
      );
      if (height > visible) {
        lanes = SingleChildScrollView(
          controller: _lanesScroll,
          physics: widget.enabled
              ? const ClampingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          child: lanes,
        );
      }

      return SizedBox(
        height: visible,
        child: Stack(
          children: [
            Positioned.fill(child: lanes),
            // The playhead, fixed in the middle.
            Positioned(
              left: half - 1,
              top: 0,
              bottom: 0,
              width: 2,
              child: const IgnorePointer(
                child: ColoredBox(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    });
  }

  static Key _cardKey(TimelineSelection item) =>
      ValueKey('${item.kind.name}-${item.index}');

  /// A faint band behind each overlay and audio lane, so the rows read as
  /// rows.
  List<Widget> _laneBands(Composition edit, _Rows rows, double width) => [
        // The main row's too: a blank between clips shows as its ground.
        Positioned(
          key: const ValueKey('band-main'),
          left: 0,
          top: rows.mainTop,
          width: width,
          height: TimelineView.clipHeight,
          child: const _Band(),
        ),
        for (var lane = 0; lane < rows.overlays; lane++)
          Positioned(
            key: ValueKey('band-overlay-$lane'),
            left: 0,
            top: rows.overlayTop(lane),
            width: width,
            height: TimelineView.overlayHeight,
            child: const _Band(),
          ),
        for (var lane = 0; lane < rows.tracks; lane++)
          Positioned(
            key: ValueKey('band-track-$lane'),
            left: 0,
            top: rows.trackTop(lane),
            width: width,
            height: TimelineView.trackHeight,
            child: const _Band(),
          ),
      ];

  /// While a card is held: where it would land - outlined in its lane, or a
  /// bright line where a new lane would open.
  List<Widget> _landingMarks(Composition edit, _Rows rows, double width) {
    final held = _held;
    final landing = _landing;
    if (held == null || landing == null) return const [];
    const key = ValueKey('landing');
    switch (landing.into) {
      case TimelineKind.clip:
        if (held.isClip) return const []; // The main row makes room for it.
        // An overlay going into the run: a line where it would go in -
        // straight after the clip before that place.
        final slot = landing.slot.clamp(0, edit.clips.length);
        final x = slot == 0
            ? 0.0
            : _px(edit.clipStarts[slot - 1] + edit.clips[slot - 1].length);
        return [
          Positioned(
            key: key,
            left: x - 2,
            top: rows.mainTop - 2,
            width: 4,
            height: TimelineView.clipHeight + 4,
            child: const _Mark(),
          ),
        ];
      case TimelineKind.overlay:
      case TimelineKind.track:
        final isOverlay = landing.into == TimelineKind.overlay;
        final lanes = isOverlay ? rows.overlays : rows.tracks;
        if (landing.lane >= lanes) {
          return [
            Positioned(
              key: key,
              left: 0,
              top: isOverlay
                  ? TimelineView.rulerHeight - 4
                  : rows.trackTop(lanes) - TimelineView.laneGap / 2 - 1,
              width: width,
              height: 3,
              child: const _Mark(),
            ),
          ];
        }
        final length = switch (held.kind) {
          TimelineKind.clip => edit.clips[held.index].length,
          TimelineKind.overlay => edit.overlays[held.index].length,
          TimelineKind.track => edit.audio[held.index].length,
        };
        return [
          Positioned(
            key: key,
            left: _px(landing.start),
            top: isOverlay
                ? rows.overlayTop(landing.lane)
                : rows.trackTop(landing.lane),
            width: math.max(_px(length), 8),
            height: isOverlay
                ? TimelineView.overlayHeight
                : TimelineView.trackHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 1.5),
                borderRadius: BorderRadius.circular(CLRadii.sm),
              ),
            ),
          ),
        ];
    }
  }

  /// A card's place: where it lives - or, held, under the finger - a
  /// little bigger while held.
  Widget _placed({
    required TimelineSelection item,
    required double left,
    required double top,
    required double width,
    required double height,
    required Widget child,
    Duration shift = Duration.zero,
  }) {
    final held = _held == item;
    return AnimatedPositioned(
      key: _cardKey(item),
      duration: held ? Duration.zero : shift,
      left: held ? _heldAt.dx : left,
      top: held ? _heldAt.dy : top,
      width: width,
      height: height,
      child: Transform.scale(
        scale: held ? 1.06 : 1,
        child: Opacity(opacity: held ? 0.9 : 1, child: child),
      ),
    );
  }

  // ------------------------------------------------------------------ clips

  List<Widget> _clipCards(Composition edit, _Rows rows) {
    final clips = edit.clips;
    final held = _held;
    final landing = _landing;
    final heldClip = held != null && held.isClip ? held.index : null;
    // Where each clip sits - and, while one is held, where they all would
    // with it let go there: closed up around the slot it would drop into,
    // or around nothing while it is up in an overlay lane.
    var shown = edit;
    final order = [for (var i = 0; i < clips.length; i++) i];
    if (heldClip != null && landing != null) {
      order.remove(heldClip);
      if (landing.into == TimelineKind.clip) {
        final slot = landing.slot.clamp(0, order.length);
        order.insert(slot, heldClip);
        shown = edit.moveClip(heldClip, slot);
      } else {
        shown = edit.removeClip(heldClip) ?? edit;
      }
    }
    final starts = shown.clipStarts;
    final lefts = <int, double>{
      for (final (j, i) in order.indexed) i: _px(starts[j]),
    };
    final end = _px(shown.mainEnd);

    final widgets = <Widget>[
      if (heldClip != null && lefts.containsKey(heldClip))
        // Where it would drop, outlined.
        Positioned(
          key: const ValueKey('clip-slot'),
          left: lefts[heldClip]!,
          top: rows.mainTop,
          width: _px(clips[heldClip].length),
          height: TimelineView.clipHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white38),
              borderRadius: BorderRadius.circular(CLRadii.sm),
            ),
          ),
        ),
    ];
    for (var i = 0; i < clips.length; i++) {
      final w = _px(clips[i].length);
      final item = TimelineSelection.clip(i);
      widgets.add(_placed(
        item: item,
        left: lefts[i] ?? 0,
        top: rows.mainTop,
        width: w,
        height: TimelineView.clipHeight,
        shift: heldClip == null
            ? Duration.zero
            : const Duration(milliseconds: 160),
        child: _clipCard(i, clips[i], widget.selection == item),
      ));
    }
    // Add more, right after the last clip.
    widgets.add(Positioned(
      key: const ValueKey('clip-add'),
      left: end + 6,
      top: rows.mainTop + (TimelineView.clipHeight - _addButton) / 2,
      width: _addButton,
      height: _addButton,
      child: _AddButton(
        tooltip: "Add photos or videos",
        onTap: widget.enabled ? widget.onAddMedia : null,
      ),
    ));
    return widgets;
  }

  Widget _clipCard(int index, MediaLayer clip, bool selected) {
    final item = TimelineSelection.clip(index);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled
          ? () => widget.onSelect(selected ? null : item)
          : null,
      onLongPressStart: widget.enabled ? (d) => _pickUp(item, d) : null,
      onLongPressMoveUpdate: widget.enabled ? _moveHeld : null,
      onLongPressEnd: widget.enabled ? (_) => _drop() : null,
      // A picked clip slides along its row with the finger - into the blank
      // either side of it.
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragUpdate:
          selected && widget.enabled ? (d) => _slideClip(index, d) : null,
      onHorizontalDragEnd: selected && widget.enabled ? (_) => _endDrag() : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: _mediaCard(clip, selected)),
          if (selected && widget.enabled) ...[
            _trimHandle(
              left: true,
              onDrag: (dx) => _resizeClip(index, head: _time(dx)),
            ),
            _trimHandle(
              left: false,
              onDrag: (dx) => _resizeClip(index, tail: _time(dx)),
            ),
          ],
        ],
      ),
    );
  }

  /// A photo or video card: its picture along it, what it is and how long.
  Widget _mediaCard(MediaLayer clip, bool selected,
      {bool overlay = false, bool pastEnd = false}) {
    final thumb = clip.source.isVideo
        ? widget.thumbnails[clip.source.path]
        : clip.source.path;
    return Opacity(
      opacity: pastEnd ? 0.45 : 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CLRadii.sm),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF2A2F37)),
            if (thumb != null)
              Image.file(
                File(thumb),
                fit: BoxFit.fitHeight,
                repeat: ImageRepeat.repeatX,
                alignment: Alignment.centerLeft,
                cacheHeight: 116,
                gaplessPlayback: true,
              ),
            // A hairline between clips.
            if (!overlay)
              const Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 1.5,
                child: ColoredBox(color: Colors.black),
              ),
            Positioned(
              left: 6,
              bottom: 4,
              child: _Badge(
                icon: overlay
                    ? Icons.layers_rounded
                    : clip.source.isVideo
                        ? (clip.soundHeard
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_outlined)
                        : Icons.photo_outlined,
                label: TrimBar.lengthLabel(clip.length),
              ),
            ),
            if (selected || overlay)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected ? Colors.white : _overlayTint,
                    width: selected ? 2 : 1.5,
                  ),
                  borderRadius: BorderRadius.circular(CLRadii.sm),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _resizeClip(int index,
      {Duration head = Duration.zero, Duration tail = Duration.zero}) {
    final before = _before ??= widget.edit;
    widget.onEdit(before.resizeClip(index,
        head: head, tail: tail, maxTotal: widget.maxTotal));
  }

  void _slideClip(int index, DragUpdateDetails d) {
    final before = _before ??= widget.edit;
    _slideDx += d.delta.dx;
    widget.onEdit(before.slideClip(index, _slid, maxTotal: widget.maxTotal));
    _edgeScroll(d.globalPosition);
  }

  // --------------------------------------------------------------- overlays

  List<Widget> _overlayCards(Composition edit, _Rows rows, Duration total) {
    return [
      for (var i = 0; i < edit.overlays.length; i++)
        _placed(
          item: TimelineSelection.overlay(i),
          left: _px(edit.overlays[i].start),
          top: rows.overlayTop(edit.overlays[i].lane),
          width: math.max(_px(edit.overlays[i].length), 8.0),
          height: TimelineView.overlayHeight,
          child: _overlayCard(i, edit.overlays[i],
              widget.selection == TimelineSelection.overlay(i),
              pastEnd: edit.overlays[i].start >= widget.maxTotal),
        ),
    ];
  }

  Widget _overlayCard(int index, OverlayClip overlay, bool selected,
      {required bool pastEnd}) {
    final item = TimelineSelection.overlay(index);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled
          ? () => widget.onSelect(selected ? null : item)
          : null,
      onLongPressStart: widget.enabled ? (d) => _pickUp(item, d) : null,
      onLongPressMoveUpdate: widget.enabled ? _moveHeld : null,
      onLongPressEnd: widget.enabled ? (_) => _drop() : null,
      // A picked overlay moves along its lane with the finger; others let
      // the timeline scroll.
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragUpdate: selected && widget.enabled
          ? (d) => _slideOverlay(index, d)
          : null,
      onHorizontalDragEnd: selected && widget.enabled ? (_) => _endDrag() : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: overlay.text != null
                ? _textCard(overlay.text!, selected, pastEnd: pastEnd)
                : _mediaCard(overlay.clip, selected,
                    overlay: true, pastEnd: pastEnd),
          ),
          if (selected && widget.enabled) ...[
            _trimHandle(
              left: true,
              height: TimelineView.overlayHeight,
              onDrag: (dx) => _resizeOverlay(index, head: _time(dx)),
            ),
            _trimHandle(
              left: false,
              height: TimelineView.overlayHeight,
              onDrag: (dx) => _resizeOverlay(index, tail: _time(dx)),
            ),
          ],
        ],
      ),
    );
  }

  /// A text layer's card: its words.
  Widget _textCard(TextCard text, bool selected, {required bool pastEnd}) =>
      Opacity(
        opacity: pastEnd ? 0.45 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF3B3470),
            borderRadius: BorderRadius.circular(CLRadii.sm),
            border: Border.all(
              color: selected ? Colors.white : _overlayTint,
              width: selected ? 2 : 1.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              const Icon(Icons.text_fields_rounded,
                  size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  text.text.replaceAll('\n', ' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: CLType.meta,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );

  double _slideDx = 0;

  /// Slid, it keeps its place in the list (it never passes another on its
  /// lane): still picked.
  void _slideOverlay(int index, DragUpdateDetails d) {
    final before = _before ??= widget.edit;
    _slideDx += d.delta.dx;
    widget.onEdit(before.slideOverlay(index, _slid, maxTotal: widget.maxTotal));
    _edgeScroll(d.globalPosition);
  }

  static TimelineSelection? _overlayIndex(
      Composition edit, MediaLayer clip, Duration start) {
    final i = edit.overlays
        .indexWhere((o) => o.clip.source.path == clip.source.path && o.start == start);
    return i < 0 ? null : TimelineSelection.overlay(i);
  }

  void _resizeOverlay(int index,
      {Duration head = Duration.zero, Duration tail = Duration.zero}) {
    final before = _before ??= widget.edit;
    widget.onEdit(before.resizeOverlay(index,
        head: head, tail: tail, maxTotal: widget.maxTotal));
  }

  // ------------------------------------------------------------------ audio

  List<Widget> _trackCards(Composition edit, _Rows rows, Duration total) {
    final widgets = <Widget>[];
    if (edit.audio.isEmpty) {
      widgets.add(Positioned(
        key: const ValueKey('track-add-card'),
        left: 0,
        top: rows.trackTop(0),
        width: math.max(_px(total), 140),
        height: TimelineView.trackHeight,
        child: _AddAudioCard(onTap: widget.enabled ? widget.onAddAudio : null),
      ));
      return widgets;
    }
    var end = 0.0;
    for (var k = 0; k < edit.audio.length; k++) {
      final track = edit.audio[k];
      final left = _px(track.start);
      final w = math.max(_px(track.length), 8.0);
      if (track.lane == 0) end = math.max(end, left + w);
      final item = TimelineSelection.track(k);
      widgets.add(_placed(
        item: item,
        left: left,
        top: rows.trackTop(track.lane),
        width: w,
        height: TimelineView.trackHeight,
        child: _trackCard(k, track, widget.selection == item,
            pastEnd: track.start >= widget.maxTotal),
      ));
    }
    widgets.add(Positioned(
      key: const ValueKey('track-add'),
      left: end + 6,
      top: rows.trackTop(0) + (TimelineView.trackHeight - 34) / 2,
      width: 34,
      height: 34,
      child: _AddButton(
        tooltip: "Add music",
        icon: Icons.music_note_rounded,
        onTap: widget.enabled ? widget.onAddAudio : null,
      ),
    ));
    return widgets;
  }

  Widget _trackCard(int index, AudioTrack track, bool selected,
      {required bool pastEnd}) {
    final item = TimelineSelection.track(index);
    final card = Container(
      decoration: BoxDecoration(
        color: pastEnd ? const Color(0x55357A6B) : const Color(0xFF2E7D6B),
        borderRadius: BorderRadius.circular(CLRadii.sm),
        border: Border.all(
          color: selected ? Colors.white : const Color(0x33FFFFFF),
          width: selected ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(
            track.heard ? Icons.music_note_rounded : Icons.music_off_rounded,
            size: 14,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              track.name ?? "Music",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: CLType.meta,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled
          ? () => widget.onSelect(selected ? null : item)
          : null,
      onLongPressStart: widget.enabled ? (d) => _pickUp(item, d) : null,
      onLongPressMoveUpdate: widget.enabled ? _moveHeld : null,
      onLongPressEnd: widget.enabled ? (_) => _drop() : null,
      // A picked track moves with the finger; others let the timeline
      // scroll. From where the finger went down, so the card keeps under it.
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragUpdate: selected && widget.enabled
          ? (d) => _slideTrack(index, d)
          : null,
      onHorizontalDragEnd: selected && widget.enabled ? (_) => _endDrag() : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: card),
          if (selected && widget.enabled) ...[
            _trimHandle(
              left: true,
              height: TimelineView.trackHeight,
              onDrag: (dx) => _resizeTrack(index, head: _time(dx)),
            ),
            _trimHandle(
              left: false,
              height: TimelineView.trackHeight,
              onDrag: (dx) => _resizeTrack(index, tail: _time(dx)),
            ),
          ],
        ],
      ),
    );
  }

  void _slideTrack(int index, DragUpdateDetails d) {
    final before = _before ??= widget.edit;
    _slideDx += d.delta.dx;
    widget.onEdit(before.slideTrack(index, _slid, maxTotal: widget.maxTotal));
    _edgeScroll(d.globalPosition);
  }

  static TimelineSelection? _trackIndex(
      Composition edit, AudioTrack track, Duration start) {
    final i = edit.audio.indexWhere((t) =>
        t.path == track.path && t.trim == track.trim && t.start == start);
    return i < 0 ? null : TimelineSelection.track(i);
  }

  void _resizeTrack(int index,
      {Duration head = Duration.zero, Duration tail = Duration.zero}) {
    final before = _before ??= widget.edit;
    widget.onEdit(before.resizeTrack(index,
        head: head, tail: tail, maxTotal: widget.maxTotal));
  }

  void _endDrag() {
    _before = null;
    _slideDx = 0;
    widget.onEditEnd();
  }

  // ------------------------------------------------------------ hold & move

  Offset? _toContent(Offset global) {
    final box = _content.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global);
  }

  void _pickUp(TimelineSelection item, LongPressStartDetails d) {
    final finger = _toContent(d.globalPosition);
    if (finger == null) return;
    final edit = widget.edit;
    final rows = _Rows(edit);
    final Rect card;
    switch (item.kind) {
      case TimelineKind.clip:
        card = Rect.fromLTWH(_px(edit.clipStarts[item.index]), rows.mainTop,
            _px(edit.clips[item.index].length), TimelineView.clipHeight);
      case TimelineKind.overlay:
        final overlay = edit.overlays[item.index];
        card = Rect.fromLTWH(
            _px(overlay.start),
            rows.overlayTop(overlay.lane),
            math.max(_px(overlay.length), 8),
            TimelineView.overlayHeight);
      case TimelineKind.track:
        final track = edit.audio[item.index];
        card = Rect.fromLTWH(_px(track.start), rows.trackTop(track.lane),
            math.max(_px(track.length), 8), TimelineView.trackHeight);
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _held = item;
      _heldGrab = finger - card.topLeft;
      _heldAt = card.topLeft;
      _heldSize = card.size;
      _landing = _landingFor(finger);
    });
    widget.onSelect(null);
  }

  void _moveHeld(LongPressMoveUpdateDetails d) {
    if (_held == null) return;
    final finger = _toContent(d.globalPosition);
    if (finger == null) return;
    _heldAt = finger - _heldGrab;
    final landing = _landingFor(finger);
    final before = _landing;
    if (landing?.into != before?.into ||
        landing?.lane != before?.lane ||
        landing?.slot != before?.slot) {
      HapticFeedback.selectionClick();
    }
    setState(() => _landing = landing);
    _edgeScroll(d.globalPosition);
  }

  /// Where the held card would land with the finger at [finger] (content
  /// coordinates), its left edge where the card's is.
  _Landing? _landingFor(Offset finger) {
    final held = _held;
    if (held == null) return null;
    final edit = widget.edit;
    final rows = _Rows(edit);
    final start = _time(math.max(0, _heldAt.dx));
    switch (held.kind) {
      case TimelineKind.track:
        final lane = rows.trackLaneAt(finger.dy);
        final at = edit.trackLanding(held.index, start,
            lane: lane, maxTotal: widget.maxTotal);
        return at == null ? null : _Landing.lane(TimelineKind.track, lane, at);
      case TimelineKind.clip:
      case TimelineKind.overlay:
        final lane = rows.overlayLaneAt(finger.dy);
        if (lane == null) {
          if (held.isOverlay &&
              (edit.overlays[held.index].isText ||
                  edit.overlays[held.index].length >
                      edit.remaining(widget.maxTotal))) {
            // Words stay over the clips; else no room left in the run.
            return null;
          }
          return _Landing.main(_slotFor(held));
        }
        if (held.isClip) {
          final at = edit.liftLanding(held.index,
              start: start, lane: lane, maxTotal: widget.maxTotal);
          return at == null
              ? null
              : _Landing.lane(TimelineKind.overlay, at.lane, at.start);
        }
        final at = edit.overlayLanding(held.index, start,
            lane: lane, maxTotal: widget.maxTotal);
        return at == null
            ? null
            : _Landing.lane(TimelineKind.overlay, lane, at);
    }
  }

  /// The place in the main run the held card's middle is at: how many of
  /// the other clips' middles it has passed - the others as they sit with
  /// the held clip out of the run.
  int _slotFor(TimelineSelection held) {
    final edit = widget.edit;
    final others = held.isClip ? (edit.removeClip(held.index) ?? edit) : edit;
    final starts = others.clipStarts;
    final middle = _time(_heldAt.dx + _heldSize.width / 2);
    var slot = 0;
    for (var i = 0; i < others.clips.length; i++) {
      if (identical(others, edit) && held.isClip && i == held.index) continue;
      if (middle > starts[i] + others.clips[i].length ~/ 2) slot++;
    }
    return slot;
  }

  void _drop() {
    final held = _held;
    final landing = _landing;
    setState(() {
      _held = null;
      _landing = null;
    });
    if (held == null || landing == null) return;
    final edit = widget.edit;
    Composition? next;
    TimelineSelection? pick;
    switch ((held.kind, landing.into)) {
      case (TimelineKind.clip, TimelineKind.clip):
        if (landing.slot == held.index) return;
        next = edit.moveClip(held.index, landing.slot);
        pick = TimelineSelection.clip(landing.slot);
      case (TimelineKind.clip, _):
        final clip = edit.clips[held.index];
        next = edit.liftClip(held.index,
            start: landing.start,
            lane: landing.lane,
            maxTotal: widget.maxTotal);
        if (next != null) pick = _overlayIndex(next, clip, landing.start);
      case (TimelineKind.overlay, TimelineKind.clip):
        next = edit.dropOverlay(held.index,
            maxTotal: widget.maxTotal, slot: landing.slot);
        pick = TimelineSelection.clip(landing.slot);
      case (TimelineKind.overlay, _):
        final clip = edit.overlays[held.index].clip;
        next = edit.moveOverlay(held.index, landing.start,
            lane: landing.lane, maxTotal: widget.maxTotal);
        pick = _overlayIndex(next, clip, landing.start);
      case (TimelineKind.track, _):
        final track = edit.audio[held.index];
        next = edit.moveTrack(held.index, landing.start,
            lane: landing.lane, maxTotal: widget.maxTotal);
        // Its lane may have been renumbered as an emptied one closed up.
        pick = _trackIndex(next, track, landing.start);
    }
    if (next == null || identical(next, edit)) return;
    widget.onEdit(next);
    widget.onSelect(pick);
    widget.onEditEnd();
  }

  /// Near an edge of the timeline while moving something, it scrolls along
  /// - sideways, and up or down through its lanes.
  void _edgeScroll(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(global);
    const edge = 40.0;
    if (_scroll.hasClients) {
      double by = 0;
      if (local.dx < edge) by = -12;
      if (local.dx > box.size.width - edge) by = 12;
      if (by != 0) {
        _scroll.jumpTo((_scroll.offset + by)
            .clamp(0.0, _scroll.position.maxScrollExtent));
      }
    }
    if (_lanesScroll.hasClients) {
      double by = 0;
      if (local.dy < 24) by = -8;
      if (local.dy > box.size.height - 24) by = 8;
      if (by != 0) {
        _lanesScroll.jumpTo((_lanesScroll.offset + by)
            .clamp(0.0, _lanesScroll.position.maxScrollExtent));
      }
    }
  }

  // ---------------------------------------------------------------- handles

  double _handleDx = 0;

  /// A card end's grip: dragging it reports the distance moved so far.
  Widget _trimHandle({
    required bool left,
    required ValueChanged<double> onDrag,
    double height = TimelineView.clipHeight,
  }) {
    return Positioned(
      // Inside the card's ends: a touch outside a widget's box never reaches
      // it.
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      height: height,
      width: _handle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (_) {
          _handleDx = 0;
          _before = widget.edit;
          HapticFeedback.selectionClick();
        },
        onHorizontalDragUpdate: (d) {
          _handleDx += d.delta.dx;
          onDrag(_handleDx);
        },
        onHorizontalDragEnd: (_) => _endDrag(),
        child: Center(
          child: Container(
            width: 10,
            height: height - 10,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [
                BoxShadow(color: Color(0x66000000), blurRadius: 3),
              ],
            ),
            child: const Center(
              child: SizedBox(
                width: 2,
                height: 14,
                child: ColoredBox(color: Color(0xFF444B55)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A lane's faint ground.
class _Band extends StatelessWidget {
  const _Band();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(CLRadii.sm),
        ),
      );
}

/// Where a held card would go in.
class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(2),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 3)],
        ),
      );
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Badge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(CLRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white),
          const SizedBox(width: 3),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: CLType.meta,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  const _AddButton(
      {required this.tooltip, this.icon = Icons.add_rounded, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(CLRadii.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CLRadii.sm),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, color: Colors.black, size: 20),
              if (icon != Icons.add_rounded)
                const Positioned(
                  right: 3,
                  top: 3,
                  child: Icon(Icons.add_rounded, color: Colors.black, size: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddAudioCard extends StatelessWidget {
  final VoidCallback? onTap;

  const _AddAudioCard({this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(CLRadii.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CLRadii.sm),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(CLRadii.sm),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: const Row(
            children: [
              Icon(Icons.add_rounded, size: 16, color: Colors.white70),
              SizedBox(width: 4),
              Icon(Icons.music_note_rounded, size: 14, color: Colors.white70),
              SizedBox(width: 6),
              Flexible(
                child: Text("Add music",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: CLType.caption,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seconds along the top: a tick every second, a time every two.
class _RulerPainter extends CustomPainter {
  final double length;
  final double pps;

  _RulerPainter(this.length, this.pps);

  @override
  void paint(Canvas canvas, Size size) {
    final tick = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    final seconds = (length / pps).ceil();
    for (var s = 0; s <= seconds; s++) {
      final x = s * pps;
      final labelled = s % 2 == 0;
      canvas.drawLine(Offset(x, size.height - (labelled ? 6 : 3)),
          Offset(x, size.height), tick);
      if (labelled) {
        final text = TextPainter(
          text: TextSpan(
            text: '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}',
            style: const TextStyle(color: Colors.white38, fontSize: CLType.meta),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, Offset(x + 2, 0));
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.length != length || old.pps != pps;
}
