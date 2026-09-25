import 'dart:math' as math;

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:flutter/material.dart';

/// One track of an edit as a card - a video's or a song's - with the part of
/// it to use: a range over [total], at least [minSpan] and at most [maxSpan]
/// long. Moving one end past the allowed length drags the other along, so
/// the window always fits. Cards stack, one per track, like an editor's
/// timeline.
///
/// [position] draws the preview's playhead on the track. Drawn light-on-dark,
/// for the editor's black screen.
class TrimBar extends StatelessWidget {
  final IconData icon;
  final String title;
  final Duration total;
  final TrimRange range;
  final Duration maxSpan;
  final Duration minSpan;
  final ValueChanged<TrimRange> onChanged;

  /// A thumb is grabbed - e.g. to pause the preview while scrubbing.
  final ValueChanged<TrimRange>? onChangeStart;

  /// A thumb is let go - e.g. to restart the preview at the new start.
  final ValueChanged<TrimRange>? onChangeEnd;

  /// Buttons at the end of the title row (mute, remove).
  final List<Widget> actions;

  /// Where the preview is in this track, if playing.
  final Duration? position;

  final bool enabled;

  const TrimBar({
    super.key,
    required this.icon,
    required this.title,
    required this.total,
    required this.range,
    required this.maxSpan,
    required this.onChanged,
    this.minSpan = const Duration(seconds: 1),
    this.onChangeStart,
    this.onChangeEnd,
    this.actions = const [],
    this.position,
    this.enabled = true,
  });

  /// The track's horizontal inset inside the slider - its thumb overlay's
  /// radius, set explicitly below so the playhead can be lined up with it.
  static const _trackInset = 16.0;

  /// The range [start]..[end] becomes once held to the span limits, keeping
  /// the end the user is moving where they put it. Pure, for the tests.
  static TrimRange constrain({
    required TrimRange previous,
    required Duration start,
    required Duration end,
    required Duration total,
    required Duration minSpan,
    required Duration maxSpan,
  }) {
    final minMs = math.min(minSpan.inMilliseconds, total.inMilliseconds);
    final maxMs = math.min(maxSpan.inMilliseconds, total.inMilliseconds);
    var s = start.inMilliseconds.clamp(0, total.inMilliseconds);
    var e = end.inMilliseconds.clamp(0, total.inMilliseconds);
    final movedStart = s != previous.start.inMilliseconds;
    final limit = e - s > maxMs
        ? maxMs
        : e - s < minMs
            ? minMs
            : null;
    if (limit != null) {
      // Keep the end being moved; the other one follows it.
      if (movedStart) {
        e = s + limit;
      } else {
        s = e - limit;
      }
    }
    // Pushed past an edge by the other thumb: slide the window back in.
    if (e > total.inMilliseconds) {
      s -= e - total.inMilliseconds;
      e = total.inMilliseconds;
    }
    if (s < 0) {
      e -= s;
      s = 0;
    }
    return TrimRange(Duration(milliseconds: s), Duration(milliseconds: e));
  }

  static String clock(Duration d) {
    final seconds = d.inMilliseconds ~/ 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  /// "30s", "7.5s", "1:42".
  static String lengthLabel(Duration d) {
    final tenths = (d.inMilliseconds / 100).round();
    if (tenths < 600) {
      return tenths % 10 == 0 ? '${tenths ~/ 10}s' : '${tenths / 10}s';
    }
    return clock(d);
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = math.max(1, total.inMilliseconds).toDouble();
    TrimRange picked(RangeValues v) => constrain(
          previous: range,
          start: Duration(milliseconds: v.start.round()),
          end: Duration(milliseconds: v.end.round()),
          total: total,
          minSpan: minSpan,
          maxSpan: maxSpan,
        );
    final at = position;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 32,
              child: Row(
                children: [
                  Icon(icon, size: 16, color: Colors.white70),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: CLType.label,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    lengthLabel(range.length),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: CLType.label,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  ...actions,
                ],
              ),
            ),
            SizedBox(
              height: 32,
              child: Stack(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white24,
                      overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: _trackInset),
                      rangeThumbShape: const RoundRangeSliderThumbShape(
                          enabledThumbRadius: 8),
                    ),
                    child: RangeSlider(
                      min: 0,
                      max: totalMs,
                      values: RangeValues(
                        range.start.inMilliseconds.clamp(0, totalMs).toDouble(),
                        range.end.inMilliseconds.clamp(0, totalMs).toDouble(),
                      ),
                      onChanged: enabled ? (v) => onChanged(picked(v)) : null,
                      onChangeStart: enabled && onChangeStart != null
                          ? (v) => onChangeStart!(picked(v))
                          : null,
                      onChangeEnd: enabled && onChangeEnd != null
                          ? (v) => onChangeEnd!(picked(v))
                          : null,
                    ),
                  ),
                  if (at != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: LayoutBuilder(
                          builder: (context, box) {
                            final track = box.maxWidth - 2 * _trackInset;
                            final fraction =
                                (at.inMilliseconds / totalMs).clamp(0.0, 1.0);
                            return Stack(
                              children: [
                                Positioned(
                                  left: _trackInset + track * fraction - 1,
                                  top: 6,
                                  bottom: 6,
                                  width: 2,
                                  child: const ColoredBox(
                                      color: Color(0xFFFFD54F)),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              // Under the track's ends (the card pads 12 left, 4 right).
              padding: const EdgeInsets.fromLTRB(
                  _trackInset - 8, 0, _trackInset + 4, 0),
              child: Row(
                children: [
                  Text(clock(range.start),
                      style: const TextStyle(
                          color: Colors.white60, fontSize: CLType.meta)),
                  const Spacer(),
                  Text('of ${clock(total)}',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: CLType.meta)),
                  const Spacer(),
                  Text(clock(range.end),
                      style: const TextStyle(
                          color: Colors.white60, fontSize: CLType.meta)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
