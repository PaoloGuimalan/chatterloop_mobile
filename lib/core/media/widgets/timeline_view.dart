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

/// What is picked on the timeline: a clip or an audio track, by index.
@immutable
class TimelineSelection {
  final bool isClip;
  final int index;

  const TimelineSelection.clip(this.index) : isClip = true;
  const TimelineSelection.track(this.index) : isClip = false;

  @override
  bool operator ==(Object other) =>
      other is TimelineSelection &&
      other.isClip == isClip &&
      other.index == index;

  @override
  int get hashCode => Object.hash(isClip, index);
}

/// The editor's timeline, like an editing app's: a ruler, the CLIPS as
/// cards in a row (each as wide as it is long), and the AUDIO tracks as
/// cards in a row under them, at their places in time - with the playhead
/// fixed in the middle and the timeline moving under it.
///
///  - Scroll the timeline to scrub; while playing it scrolls itself.
///  - Tap a card to pick it; a picked card has handles on its ends - drag
///    them to trim.
///  - Long-press a clip and drag it to move it in the order.
///  - Drag a picked audio card to move it in time: it lands in the free
///    stretch nearest the finger, so it can go past other tracks.
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
    this.enabled = true,
  });

  /// Timeline pixels per second of edit.
  static const pxPerSecond = 48.0;

  static const rulerHeight = 18.0;
  static const clipHeight = 58.0;
  static const trackHeight = 42.0;
  static const laneGap = 8.0;
  static const height = rulerHeight + clipHeight + laneGap + trackHeight + 8;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  static const _pps = TimelineView.pxPerSecond;
  static const _handle = 16.0;
  static const _addButton = 46.0;

  final _scroll = ScrollController();
  bool _userScrolling = false;

  /// A clip being moved: which, where the finger has it, and the slot it
  /// would drop into.
  int? _dragClip;
  double _dragX = 0;
  int _dragTarget = 0;

  /// The edit as it was when a trim or move started - drags apply their
  /// whole distance to it, so nothing accumulates rounding.
  Composition? _before;

  double _px(Duration d) => d.inMicroseconds / 1e6 * _pps;
  Duration _time(double px) =>
      Duration(microseconds: (px / _pps * 1e6).round());

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
      final total = edit.naturalDuration;
      final audioEnd = edit.audio.fold(
          Duration.zero, (Duration end, track) => end > track.end ? end : track.end);
      final contentEnd = math.max(_px(total), _px(audioEnd));
      final width = contentEnd + _addButton + 12;

      return SizedBox(
        height: TimelineView.height,
        child: Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                physics: widget.enabled
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: half),
                child: SizedBox(
                  width: width,
                  height: TimelineView.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        width: width,
                        height: TimelineView.rulerHeight,
                        child: CustomPaint(
                            painter: _RulerPainter(_px(total), _pps)),
                      ),
                      ..._clipLane(edit),
                      ..._trackLane(edit, total),
                    ],
                  ),
                ),
              ),
            ),
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

  // ------------------------------------------------------------------ clips

  static const _clipTop = TimelineView.rulerHeight;

  List<Widget> _clipLane(Composition edit) {
    final clips = edit.clips;
    // While a clip is moved, the others close up around the slot it would
    // drop into.
    final order = [for (var i = 0; i < clips.length; i++) i];
    final dragged = _dragClip;
    if (dragged != null) {
      order
        ..remove(dragged)
        ..insert(_dragTarget, dragged);
    }
    final lefts = <int, double>{};
    var x = 0.0;
    for (final i in order) {
      lefts[i] = x;
      x += _px(clips[i].length);
    }
    final end = x;

    // Every card stays the same widget, keyed, whatever its place - the
    // held one included: rebuilt elsewhere, it would drop the finger's
    // gesture mid-drag. The held card is painted last, on top.
    final paintOrder = [
      for (var i = 0; i < clips.length; i++)
        if (i != dragged) i,
      if (dragged != null) dragged,
    ];
    final widgets = <Widget>[
      if (dragged != null)
        // Where it would drop, outlined.
        Positioned(
          key: const ValueKey('clip-slot'),
          left: lefts[dragged]!,
          top: _clipTop,
          width: _px(clips[dragged].length),
          height: TimelineView.clipHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white38),
              borderRadius: BorderRadius.circular(CLRadii.sm),
            ),
          ),
        ),
    ];
    for (final i in paintOrder) {
      final w = _px(clips[i].length);
      final held = i == dragged;
      final selected = widget.selection == TimelineSelection.clip(i);
      widgets.add(AnimatedPositioned(
        key: ValueKey('clip-$i'),
        duration: dragged == null || held
            ? Duration.zero
            : const Duration(milliseconds: 160),
        left: held ? _dragX : lefts[i]!,
        top: _clipTop,
        width: w,
        height: TimelineView.clipHeight,
        child: Transform.scale(
          scale: held ? 1.06 : 1,
          child: Opacity(
            opacity: held ? 0.9 : 1,
            child: _clipCard(i, clips[i], w, selected),
          ),
        ),
      ));
    }
    // Add more, right after the last clip.
    widgets.add(Positioned(
      key: const ValueKey('clip-add'),
      left: end + 6,
      top: _clipTop + (TimelineView.clipHeight - _addButton) / 2,
      width: _addButton,
      height: _addButton,
      child: _AddButton(
        tooltip: "Add photos or videos",
        onTap: widget.enabled ? widget.onAddMedia : null,
      ),
    ));
    return widgets;
  }

  Widget _clipCard(int index, MediaLayer clip, double width, bool selected) {
    final thumb = clip.source.isVideo
        ? widget.thumbnails[clip.source.path]
        : clip.source.path;
    final card = ClipRRect(
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
              icon: clip.source.isVideo
                  ? (clip.soundHeard
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_outlined)
                  : Icons.photo_outlined,
              label: TrimBar.lengthLabel(clip.length),
            ),
          ),
          if (selected)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(CLRadii.sm),
              ),
            ),
        ],
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled
          ? () => widget.onSelect(selected ? null : TimelineSelection.clip(index))
          : null,
      onLongPressStart: widget.enabled && widget.edit.clips.length > 1
          ? (d) => _startClipDrag(index, d)
          : null,
      onLongPressMoveUpdate: widget.enabled ? _moveClipDrag : null,
      onLongPressEnd: widget.enabled ? (_) => _endClipDrag() : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: card),
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

  double _dragStartX = 0;
  double _dragOriginX = 0;

  void _startClipDrag(int index, LongPressStartDetails d) {
    HapticFeedback.mediumImpact();
    final starts = widget.edit.clipStarts;
    setState(() {
      _dragClip = index;
      _dragTarget = index;
      _dragOriginX = _px(starts[index]);
      _dragStartX = d.globalPosition.dx;
      _dragX = _dragOriginX;
    });
    widget.onSelect(null);
  }

  void _moveClipDrag(LongPressMoveUpdateDetails d) {
    final dragged = _dragClip;
    if (dragged == null) return;
    final clips = widget.edit.clips;
    final x = _dragOriginX + d.globalPosition.dx - _dragStartX;
    // The slot: how many of the other clips' middles the dragged card's
    // middle has passed.
    final middle = x + _px(clips[dragged].length) / 2;
    var slot = 0;
    var at = 0.0;
    for (var i = 0; i < clips.length; i++) {
      if (i == dragged) continue;
      final w = _px(clips[i].length);
      if (middle > at + w / 2) slot++;
      at += w;
    }
    if (slot != _dragTarget) HapticFeedback.selectionClick();
    setState(() {
      _dragX = x;
      _dragTarget = slot;
    });
    _edgeScroll(d.globalPosition.dx);
  }

  void _endClipDrag() {
    final dragged = _dragClip;
    if (dragged == null) return;
    final target = _dragTarget;
    setState(() => _dragClip = null);
    if (target != dragged) {
      widget.onEdit(widget.edit.moveClip(dragged, target));
      widget.onSelect(TimelineSelection.clip(target));
      widget.onEditEnd();
    }
  }

  /// Near either edge of the screen while moving something, the timeline
  /// scrolls along.
  void _edgeScroll(double globalX) {
    if (!_scroll.hasClients) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(Offset(globalX, 0)).dx;
    const edge = 40.0;
    double by = 0;
    if (local < edge) by = -12;
    if (local > box.size.width - edge) by = 12;
    if (by != 0) {
      _scroll.jumpTo((_scroll.offset + by)
          .clamp(0.0, _scroll.position.maxScrollExtent));
    }
  }

  void _resizeClip(int index,
      {Duration head = Duration.zero, Duration tail = Duration.zero}) {
    final before = _before ??= widget.edit;
    widget.onEdit(before.resizeClip(index,
        head: head, tail: tail, maxTotal: widget.maxTotal));
  }

  // ------------------------------------------------------------------ audio

  static const _trackTop =
      TimelineView.rulerHeight + TimelineView.clipHeight + TimelineView.laneGap;

  List<Widget> _trackLane(Composition edit, Duration total) {
    final widgets = <Widget>[];
    if (edit.audio.isEmpty) {
      widgets.add(Positioned(
        left: 0,
        top: _trackTop,
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
      end = math.max(end, left + w);
      final selected = widget.selection == TimelineSelection.track(k);
      widgets.add(Positioned(
        left: left,
        top: _trackTop,
        width: w,
        height: TimelineView.trackHeight,
        child: _trackCard(k, track, selected,
            pastEnd: track.start >= total),
      ));
    }
    widgets.add(Positioned(
      left: end + 6,
      top: _trackTop + (TimelineView.trackHeight - 34) / 2,
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
          ? () =>
              widget.onSelect(selected ? null : TimelineSelection.track(index))
          : null,
      // A picked track moves with the finger; others let the timeline
      // scroll. From where the finger went down, so the card keeps under it.
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragUpdate: selected && widget.enabled
          ? (d) => _moveTrack(index, d)
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

  double _trackDragDx = 0;
  AudioTrack? _movingTrack;

  void _moveTrack(int index, DragUpdateDetails d) {
    final before = _before ??= widget.edit;
    final track = _movingTrack ??= before.audio[index];
    _trackDragDx += d.delta.dx;
    final from = before.audio.indexOf(track);
    final moved =
        before.moveTrack(from, track.start + _time(_trackDragDx));
    widget.onEdit(moved);
    // The list is kept in time order - the picked track may have changed
    // place in it.
    final now = moved.audio.indexWhere(
        (t) => t.path == track.path && t.trim == track.trim);
    if (now >= 0 && widget.selection != TimelineSelection.track(now)) {
      widget.onSelect(TimelineSelection.track(now));
    }
    _edgeScroll(d.globalPosition.dx);
  }

  void _resizeTrack(int index,
      {Duration head = Duration.zero, Duration tail = Duration.zero}) {
    final before = _before ??= widget.edit;
    widget.onEdit(before.resizeTrack(index, head: head, tail: tail));
  }

  void _endDrag() {
    _before = null;
    _movingTrack = null;
    _trackDragDx = 0;
    widget.onEditEnd();
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
