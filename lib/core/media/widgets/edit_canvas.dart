import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chatterloop_app/core/media/canvas_geometry.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// One picture on the [EditCanvas]: a clip, and its playing video when it
/// is one.
@immutable
class CanvasLayer {
  final MediaLayer layer;
  final VideoPlayerController? video;

  const CanvasLayer(this.layer, {this.video});
}

/// The editor's canvas: what shows at the playhead - the main clip over the
/// edit's background (or, in a blank, black), then the overlays showing
/// there, each over the one before - drawn with the SAME geometry the
/// renderer uses ([placeLayer]), plus the gestures that change a layer's
/// framing: drag to move, pinch to zoom, twist to rotate, double-tap for
/// [onDoubleTap]. A gesture moves the top layer under the finger - the main
/// clip when it is on none of the overlays.
///
/// Size it to the output's aspect ratio (an AspectRatio parent); every
/// position is a fraction of whatever size it gets, so the preview matches
/// the render at any screen size.
class EditCanvas extends StatefulWidget {
  /// Bottom first: the main clip under the playhead ([hasBase]), then the
  /// overlays showing there.
  final List<CanvasLayer> layers;

  /// Whether [layers] starts with a main clip. Without one - a blank - the
  /// canvas is black under the overlays.
  final bool hasBase;
  final CompositionBackground background;

  /// The layer outlined as the one being edited, if any.
  final int? outlined;

  /// Layer [index]'s framing, as a gesture changes it.
  final void Function(int index, LayerTransform transform) onTransform;

  /// A gesture on layer [index] starts - before any [onTransform].
  final ValueChanged<int>? onGestureStart;
  final VoidCallback? onGestureEnd;

  /// A double tap on layer [index].
  final ValueChanged<int>? onDoubleTap;

  /// False while rendering - the edit is frozen.
  final bool enabled;

  const EditCanvas({
    super.key,
    required this.layers,
    required this.background,
    required this.onTransform,
    this.hasBase = true,
    this.outlined,
    this.onGestureStart,
    this.onGestureEnd,
    this.onDoubleTap,
    this.enabled = true,
  });

  @override
  State<EditCanvas> createState() => _EditCanvasState();
}

class _EditCanvasState extends State<EditCanvas> {
  /// Canvas pixels within which the centre snaps to the middle.
  static const _snapPx = 8.0;

  /// The render's blurred background, as a preview blur: boxblur 10:2 at a
  /// quarter of 720 wide is a ~34px Gaussian at full size.
  static const _blurSigmaAt720 = 34.0;

  /// The render darkens the blurred background (eq brightness -0.08).
  static const _blurDim = 0.12;

  Size _size = Size.zero;

  /// The layer the gesture moves.
  int _target = 0;
  LayerTransform _start = LayerTransform.fit;
  Offset _startFocal = Offset.zero;
  Offset _doubleTapAt = Offset.zero;
  bool _snapX = false, _snapY = false, _snapTurn = false;
  bool _gesturing = false;

  MediaLayer _layerAt(int index) => widget.layers[index].layer;

  LayerPlacement _placed(MediaLayer layer) {
    final source = layer.source;
    return placeLayer(
      mediaWidth: source.width.toDouble(),
      mediaHeight: source.height.toDouble(),
      canvasWidth: _size.width,
      canvasHeight: _size.height,
      transform: layer.transform,
    );
  }

  /// The top layer under [point] - the main clip (0) when it is on no
  /// overlay; -1 when there is none of either (a blank).
  int _layerUnder(Offset point) {
    final lowest = widget.hasBase ? 1 : 0;
    for (var i = widget.layers.length - 1; i >= lowest; i--) {
      final placed = _placed(_layerAt(i));
      // Into the layer's own unrotated frame.
      final dx = point.dx - placed.centerX, dy = point.dy - placed.centerY;
      final cos = math.cos(placed.rotation), sin = math.sin(placed.rotation);
      final u = dx * cos + dy * sin;
      final v = -dx * sin + dy * cos;
      if (u.abs() <= placed.width / 2 && v.abs() <= placed.height / 2) return i;
    }
    return widget.hasBase && widget.layers.isNotEmpty ? 0 : -1;
  }

  void _onScaleStart(ScaleStartDetails d) {
    _target = _layerUnder(d.localFocalPoint);
    // A picked layer takes a pinch wherever it lands - a small one (a word
    // of text) can't fit two fingers - and a drag off every other layer.
    // (A second finger restarts the gesture: it stays on the picked one.)
    final picked = widget.outlined;
    if (picked != null &&
        picked < widget.layers.length &&
        (d.pointerCount >= 2 || _target <= 0)) {
      _target = picked;
    }
    if (_target < 0) return; // Nothing there to move.
    widget.onGestureStart?.call(_target);
    _start = _layerAt(_target).transform;
    _startFocal = d.localFocalPoint;
    // Already on a guide when the gesture starts is not "landing" on it.
    _snapX = _nearMiddle(_start.cx, _size.width);
    _snapY = _nearMiddle(_start.cy, _size.height);
    _snapTurn = snapRotation(_start.rotationDeg) % 90 == 0;
    setState(() => _gesturing = true);
  }

  bool _nearMiddle(double fraction, double extent) =>
      (fraction - 0.5).abs() * extent < _snapPx;

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_size.isEmpty || _target < 0 || _target >= widget.layers.length) {
      return;
    }
    final source = _layerAt(_target).source;
    final fill = LayerTransform.fillScale(
        source.width / source.height, _size.width / _size.height);
    var next = transformForGesture(
      start: _start,
      canvasWidth: _size.width,
      canvasHeight: _size.height,
      startFocalX: _startFocal.dx,
      startFocalY: _startFocal.dy,
      focalX: d.localFocalPoint.dx,
      focalY: d.localFocalPoint.dy,
      scale: d.scale,
      rotation: d.rotation,
      // Down to a fifth of its fitted size - or of where it began, for one
      // already small (text is laid on small).
      minScale: math.min(0.2, _start.scale * 0.2),
      maxScale: math.max(8, fill * 4),
    );

    final turn = snapRotation(next.rotationDeg);
    final snapTurn = turn % 90 == 0;
    final snapX = _nearMiddle(next.cx, _size.width);
    final snapY = _nearMiddle(next.cy, _size.height);
    next = next.copyWith(
      cx: snapX ? 0.5 : null,
      cy: snapY ? 0.5 : null,
      rotationDeg: turn,
    );
    // A tick as the layer lands on a guide, not on every frame it stays.
    if ((snapX && !_snapX) || (snapY && !_snapY) || (snapTurn && !_snapTurn)) {
      HapticFeedback.selectionClick();
    }
    setState(() {
      _snapX = snapX;
      _snapY = snapY;
      _snapTurn = snapTurn;
    });
    widget.onTransform(_target, next);
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_target < 0) return;
    setState(() => _gesturing = false);
    widget.onGestureEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        final background = widget.background;
        final base = widget.hasBase && widget.layers.isNotEmpty
            ? widget.layers.first
            : null;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: widget.enabled ? _onScaleStart : null,
          onScaleUpdate: widget.enabled ? _onScaleUpdate : null,
          onScaleEnd: widget.enabled ? _onScaleEnd : null,
          onDoubleTapDown: widget.enabled
              ? (d) => _doubleTapAt = d.localPosition
              : null,
          onDoubleTap: widget.enabled && widget.onDoubleTap != null
              ? () {
                  final layer = _layerUnder(_doubleTapAt);
                  if (layer >= 0) widget.onDoubleTap!(layer);
                }
              : null,
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: base == null
                      // A blank: black, as it renders.
                      ? const ColoredBox(color: Colors.black)
                      : background.isBlur
                          ? _blurredBackground(base)
                          : ColoredBox(
                              color: Color(background.argb | 0xFF000000)),
                ),
                for (var i = 0; i < widget.layers.length; i++)
                  _placedLayer(widget.layers[i], outlined: widget.outlined == i),
                if (_gesturing && _snapX)
                  const Align(
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: 1,
                      height: double.infinity,
                      child: ColoredBox(color: Color(0xCCFFD54F)),
                    ),
                  ),
                if (_gesturing && _snapY)
                  const Align(
                    alignment: Alignment.center,
                    child: SizedBox(
                      height: 1,
                      width: double.infinity,
                      child: ColoredBox(color: Color(0xCCFFD54F)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _placedLayer(CanvasLayer layer, {required bool outlined}) {
    final placed = _placed(layer.layer);
    return Positioned(
      left: placed.centerX - placed.width / 2,
      top: placed.centerY - placed.height / 2,
      width: placed.width,
      height: placed.height,
      child: Transform.rotate(
        angle: placed.rotation,
        child: outlined
            ? Stack(
                fit: StackFit.expand,
                children: [
                  _media(layer, fit: BoxFit.fill),
                  // Drawn inside its edge, so it turns with it.
                  const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.fromBorderSide(
                            BorderSide(color: Colors.white, width: 2)),
                      ),
                    ),
                  ),
                ],
              )
            : _media(layer, fit: BoxFit.fill),
      ),
    );
  }

  Widget _blurredBackground(CanvasLayer layer) {
    final source = layer.layer.source;
    final sigma = _blurSigmaAt720 * _size.width / 720;
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.clamp,
          ),
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: source.width.toDouble(),
              height: source.height.toDouble(),
              child: _media(layer, fit: BoxFit.fill, lowRes: true),
            ),
          ),
        ),
        ColoredBox(color: Colors.black.withValues(alpha: _blurDim)),
      ],
    );
  }

  Widget _media(CanvasLayer layer,
      {required BoxFit fit, bool lowRes = false}) {
    final source = layer.layer.source;
    final video = layer.video;
    if (source.isVideo) {
      if (video == null || !video.value.isInitialized) {
        return const ColoredBox(color: Colors.black);
      }
      return VideoPlayer(video);
    }
    return Image.file(
      File(source.path),
      fit: fit,
      // A fixed decode size - one tied to the zoom would re-decode (and
      // flicker) on every pinch. The blurred copy needs very little.
      cacheWidth: lowRes ? 240 : math.min(source.width, 1600),
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
  }
}
