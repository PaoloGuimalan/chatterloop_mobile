import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Keeps cards mounted while their measured, natural heights pack into columns.
class NotesMasonry extends StatefulWidget {
  const NotesMasonry(
      {super.key, required this.ids, required this.itemBuilder, this.onLayout});
  final List<String> ids;
  final Widget Function(BuildContext, int, double, double?) itemBuilder;
  final ValueChanged<Map<String, Rect>>? onLayout;
  @override
  State<NotesMasonry> createState() => _NotesMasonryState();
}

class _NotesMasonryState extends State<NotesMasonry> {
  final _heights = <String, double>{};
  double _width = 0;
  bool _ready = false;

  @override
  void didUpdateWidget(covariant NotesMasonry oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = widget.ids.toSet();
    _heights.removeWhere((id, _) => !ids.contains(id));
  }

  void _measure(String id, Size size) {
    if (!mounted ||
        !widget.ids.contains(id) ||
        (size.width - _width).abs() > .5 ||
        (_heights[id] != null && (_heights[id]! - size.height).abs() < .5)) {
      return;
    }
    setState(() => _heights[id] = size.height);
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        const gap = 10.0;
        _width = math.max(0, (constraints.maxWidth - gap) / 2);
        final bottoms = [0.0, 0.0];
        final rects = <String, Rect>{};
        for (final id in widget.ids) {
          final column = bottoms[0] <= bottoms[1] ? 0 : 1;
          final height = _heights[id] ?? 180;
          rects[id] = Rect.fromLTWH(
              column * (_width + gap), bottoms[column], _width, height);
          bottoms[column] += height + gap;
        }
        widget.onLayout?.call(rects);
        // Apply initial measurements before enabling movement animation; opening
        // the collection should not animate cards down from estimated positions.
        if (!_ready && widget.ids.every(_heights.containsKey)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _ready = true;
          });
        }
        final animate = _ready && !MediaQuery.disableAnimationsOf(context);
        return SizedBox(
            height: math.max(0, math.max(bottoms[0], bottoms[1]) - gap),
            child: Stack(clipBehavior: Clip.none, children: [
              for (final (index, id) in widget.ids.indexed)
                AnimatedPositioned(
                    key: ValueKey(id),
                    duration: animate
                        ? const Duration(milliseconds: 230)
                        : Duration.zero,
                    curve: Curves.easeOutCubic,
                    left: rects[id]!.left,
                    top: rects[id]!.top,
                    width: _width,
                    child: _MeasureCard(
                        onSize: (size) => _measure(id, size),
                        child: widget.itemBuilder(
                            context, index, _width, _heights[id]))),
            ]));
      });
}

class _MeasureCard extends SingleChildRenderObjectWidget {
  const _MeasureCard({required this.onSize, required super.child});
  final ValueChanged<Size> onSize;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureCardBox(onSize);
  @override
  void updateRenderObject(
      BuildContext context, covariant _MeasureCardBox renderObject) {
    renderObject.onSize = onSize;
  }
}

class _MeasureCardBox extends RenderProxyBox {
  _MeasureCardBox(this.onSize);
  ValueChanged<Size> onSize;
  Size? _lastSize;
  @override
  void performLayout() {
    super.performLayout();
    if (_lastSize == size) return;
    _lastSize = size;
    final measured = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onSize(measured);
    });
  }
}
