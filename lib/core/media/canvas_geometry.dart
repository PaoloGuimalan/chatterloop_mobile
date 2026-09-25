import 'dart:math' as math;

import 'package:chatterloop_app/core/media/composition.dart';

/// Where a layer lands on a canvas of a given pixel size.
///
/// THE one implementation of the edit's positioning rules: the editor's live
/// preview and the ffmpeg renderer both place layers through [placeLayer], so
/// what the author arranges is what gets encoded, at any resolution.
class LayerPlacement {
  /// The layer's drawn size BEFORE rotation, in canvas pixels.
  final double width;
  final double height;

  /// Its centre, in canvas pixels.
  final double centerX;
  final double centerY;

  /// Clockwise, radians.
  final double rotation;

  const LayerPlacement({
    required this.width,
    required this.height,
    required this.centerX,
    required this.centerY,
    required this.rotation,
  });

  /// The bounding box of the rotated layer - what ffmpeg's rotate filter
  /// outputs (rotw/roth) and so what gets overlaid.
  double get rotatedWidth =>
      (width * math.cos(rotation)).abs() + (height * math.sin(rotation)).abs();
  double get rotatedHeight =>
      (width * math.sin(rotation)).abs() + (height * math.cos(rotation)).abs();
}

/// Places media of [mediaWidth] x [mediaHeight] (its DISPLAYED size) on a
/// [canvasWidth] x [canvasHeight] canvas per [transform].
///
/// Base size is "contain" - the whole media inside the canvas - times
/// `transform.scale`.
LayerPlacement placeLayer({
  required double mediaWidth,
  required double mediaHeight,
  required double canvasWidth,
  required double canvasHeight,
  required LayerTransform transform,
}) {
  final contain =
      math.min(canvasWidth / mediaWidth, canvasHeight / mediaHeight);
  final factor = contain * transform.scale;
  return LayerPlacement(
    width: mediaWidth * factor,
    height: mediaHeight * factor,
    centerX: transform.cx * canvasWidth,
    centerY: transform.cy * canvasHeight,
    rotation: transform.rotationDeg * math.pi / 180,
  );
}

/// The part of a placed layer that can land on the canvas: a rectangle of the
/// media (in its displayed pixels) and where that rectangle is drawn.
///
/// A renderer crops to it before scaling, so a zoomed-in 12MP photo is not
/// scaled whole every frame only for most of it to fall off the canvas.
class VisiblePart {
  /// The media rectangle, in media pixels.
  final int left;
  final int top;
  final int width;
  final int height;

  /// Whether the rectangle is the whole media (nothing to crop).
  final bool isWhole;

  /// Where the rectangle is drawn - same rotation as the layer, centre moved
  /// to the rectangle's own centre.
  final LayerPlacement placement;

  const VisiblePart({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.isWhole,
    required this.placement,
  });
}

/// The [VisiblePart] of media placed per [transform], or null when none of
/// it can reach the canvas.
///
/// Maps the canvas corners back into media pixels and keeps their bounding
/// box, widened to whole pixels and clamped to the media. For a rotated layer
/// that box can include a few pixels that still fall outside the canvas -
/// harmless, they are simply drawn off-canvas.
VisiblePart? visiblePart({
  required int mediaWidth,
  required int mediaHeight,
  required double canvasWidth,
  required double canvasHeight,
  required LayerTransform transform,
}) {
  final placement = placeLayer(
    mediaWidth: mediaWidth.toDouble(),
    mediaHeight: mediaHeight.toDouble(),
    canvasWidth: canvasWidth,
    canvasHeight: canvasHeight,
    transform: transform,
  );
  // Canvas pixels per media pixel.
  final factor = placement.width / mediaWidth;
  final cos = math.cos(placement.rotation);
  final sin = math.sin(placement.rotation);

  var minU = double.infinity, minV = double.infinity;
  var maxU = double.negativeInfinity, maxV = double.negativeInfinity;
  for (final (x, y) in [
    (0.0, 0.0),
    (canvasWidth, 0.0),
    (0.0, canvasHeight),
    (canvasWidth, canvasHeight),
  ]) {
    // Undo the translation, then the clockwise rotation, then the scale.
    final dx = x - placement.centerX, dy = y - placement.centerY;
    final u = (dx * cos + dy * sin) / factor + mediaWidth / 2;
    final v = (-dx * sin + dy * cos) / factor + mediaHeight / 2;
    minU = math.min(minU, u);
    maxU = math.max(maxU, u);
    minV = math.min(minV, v);
    maxV = math.max(maxV, v);
  }

  // A hair of tolerance so float noise on an exact edge doesn't cost a
  // whole pixel row.
  const eps = 1e-6;
  final left = math.max(0, (minU + eps).floor());
  final top = math.max(0, (minV + eps).floor());
  final right = math.min(mediaWidth, (maxU - eps).ceil());
  final bottom = math.min(mediaHeight, (maxV - eps).ceil());
  if (right <= left || bottom <= top) return null;

  // The kept rectangle's centre, as an offset from the media's centre in
  // canvas pixels, rotated like the layer.
  final ou = ((left + right) / 2 - mediaWidth / 2) * factor;
  final ov = ((top + bottom) / 2 - mediaHeight / 2) * factor;
  return VisiblePart(
    left: left,
    top: top,
    width: right - left,
    height: bottom - top,
    isWhole:
        left == 0 && top == 0 && right == mediaWidth && bottom == mediaHeight,
    placement: LayerPlacement(
      width: (right - left) * factor,
      height: (bottom - top) * factor,
      centerX: placement.centerX + ou * cos - ov * sin,
      centerY: placement.centerY + ou * sin + ov * cos,
      rotation: placement.rotation,
    ),
  );
}

/// What a drag / pinch / twist does to a layer that was at [start] when the
/// gesture began: the point under the fingers stays under them - moved to
/// the new focal point, scaled by [scale] and turned by [rotation] (radians,
/// clockwise) about it.
///
/// Positions are canvas pixels; [scale] and [rotation] are the gesture's
/// totals since it began (Flutter's ScaleUpdateDetails). The centre is kept
/// on the canvas, so a layer can't be lost off an edge, and the scale within
/// [minScale]..[maxScale].
LayerTransform transformForGesture({
  required LayerTransform start,
  required double canvasWidth,
  required double canvasHeight,
  required double startFocalX,
  required double startFocalY,
  required double focalX,
  required double focalY,
  double scale = 1,
  double rotation = 0,
  double minScale = 0.2,
  double maxScale = 10,
}) {
  final newScale = (start.scale * scale).clamp(minScale, maxScale);
  final ratio = newScale / start.scale;
  // The layer centre relative to the fingers, turned and scaled with them.
  final vx = start.cx * canvasWidth - startFocalX;
  final vy = start.cy * canvasHeight - startFocalY;
  final cos = math.cos(rotation), sin = math.sin(rotation);
  final x = focalX + (vx * cos - vy * sin) * ratio;
  final y = focalY + (vx * sin + vy * cos) * ratio;
  return LayerTransform(
    cx: (x / canvasWidth).clamp(0.0, 1.0),
    cy: (y / canvasHeight).clamp(0.0, 1.0),
    scale: newScale,
    rotationDeg: start.rotationDeg + rotation * 180 / math.pi,
  );
}

/// [degrees] pulled onto the nearest quarter turn when within [within]
/// degrees of it - so "straight" is easy to hit with two fingers.
double snapRotation(double degrees, {double within = 4}) {
  final nearest = (degrees / 90).round() * 90.0;
  return (degrees - nearest).abs() <= within ? nearest : degrees;
}

/// Rounds to the nearest even integer, at least 2 - ffmpeg's yuv420p frames
/// need even dimensions.
int evenPixels(double value) {
  final rounded = (value / 2).round() * 2;
  return rounded < 2 ? 2 : rounded;
}
