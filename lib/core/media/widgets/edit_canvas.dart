import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chatterloop_app/core/media/canvas_geometry.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// The editor's canvas: a [Composition] drawn with the SAME geometry the
/// renderer uses ([placeLayer]), plus the gestures that change it - drag to
/// move, pinch to zoom, twist to rotate, double-tap for [onDoubleTap].
///
/// Size it to the output's aspect ratio (an AspectRatio parent); every
/// position is a fraction of whatever size it gets, so the preview matches
/// the render at any screen size.
class EditCanvas extends StatefulWidget {
  final Composition composition;

  /// The playing video, when the layer is a video.
  final VideoPlayerController? video;

  final ValueChanged<LayerTransform> onTransform;
  final VoidCallback? onDoubleTap;

  /// False while rendering - the edit is frozen.
  final bool enabled;

  const EditCanvas({
    super.key,
    required this.composition,
    required this.onTransform,
    this.video,
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
  LayerTransform _start = LayerTransform.fit;
  Offset _startFocal = Offset.zero;
  bool _snapX = false, _snapY = false, _snapTurn = false;
  bool _gesturing = false;

  MediaLayer get _layer => widget.composition.layer;

  void _onScaleStart(ScaleStartDetails d) {
    _start = _layer.transform;
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
    if (_size.isEmpty) return;
    final source = _layer.source;
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
      minScale: 0.2,
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
    widget.onTransform(next);
  }

  void _onScaleEnd(ScaleEndDetails d) {
    setState(() => _gesturing = false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        final source = _layer.source;
        final placed = placeLayer(
          mediaWidth: source.width.toDouble(),
          mediaHeight: source.height.toDouble(),
          canvasWidth: _size.width,
          canvasHeight: _size.height,
          transform: _layer.transform,
        );
        final background = widget.composition.background;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: widget.enabled ? _onScaleStart : null,
          onScaleUpdate: widget.enabled ? _onScaleUpdate : null,
          onScaleEnd: widget.enabled ? _onScaleEnd : null,
          onDoubleTap: widget.enabled ? widget.onDoubleTap : null,
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: background.isBlur
                      ? _blurredBackground(source)
                      : ColoredBox(color: Color(background.argb | 0xFF000000)),
                ),
                Positioned(
                  left: placed.centerX - placed.width / 2,
                  top: placed.centerY - placed.height / 2,
                  width: placed.width,
                  height: placed.height,
                  child: Transform.rotate(
                    angle: placed.rotation,
                    child: _media(source, fit: BoxFit.fill),
                  ),
                ),
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

  Widget _blurredBackground(MediaSource source) {
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
              child: _media(source, fit: BoxFit.fill, lowRes: true),
            ),
          ),
        ),
        ColoredBox(color: Colors.black.withValues(alpha: _blurDim)),
      ],
    );
  }

  Widget _media(MediaSource source,
      {required BoxFit fit, bool lowRes = false}) {
    final video = widget.video;
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
