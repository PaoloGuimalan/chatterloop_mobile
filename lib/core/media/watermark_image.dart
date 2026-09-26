import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// The watermark with whose Moment it is on it - "@paolo", or a page's
/// "@its-slug" - just under the "Chatterloop" wordmark, beside the icon, as
/// one PNG which ffmpeg overlays whole.
///
/// Drawn by Flutter rather than ffmpeg's drawtext: the app's own font
/// (Inter), and nothing to hand ffmpeg but a picture.
///
/// [logoPng] is the watermark asset (tool/make_watermark.py): the logo in a
/// small margin, its shadow and transparency baked in. [wordmark] is where
/// the wordmark sits in it (the tool's watermark.json); the handle starts
/// under its left edge and is shown whole, however long - a long one runs
/// on to the right, the picture made wider for it (the encoder scales by the
/// logo's width, so the logo keeps its size). Set to match: white, as
/// see-through as the logo, the same soft shadow. Without [wordmark], it
/// goes under the whole logo.
///
/// [fontSize] is the handle's size as a fraction of the logo's width - so
/// once ffmpeg scales the whole picture, the name comes out the size asked
/// for whatever size the logo is (Watermark.handleSize / Watermark.width).
Future<Uint8List> watermarkWithHandle(
  Uint8List logoPng,
  String handle, {
  required double fontSize,
  Rect? wordmark,
}) async {
  final codec = await ui.instantiateImageCodec(logoPng);
  final logo = (await codec.getNextFrame()).image;
  codec.dispose();
  try {
    // Everything in proportion to the asset, which is 600px of logo in a
    // 15px margin (tool/make_watermark.py): the numbers below are that
    // file's, scaled.
    final w = logo.width.toDouble();
    final unit = w / 630;
    final margin = 15 * unit;
    final size = fontSize * w;
    final under = wordmark ??
        Rect.fromLTRB(margin, margin, w - margin, logo.height - margin);
    final text = TextPainter(
      text: TextSpan(
        text: handle,
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: size,
          letterSpacing: -0.004 * size,
          // The logo's OPACITY.
          color: const Color(0xBFFFFFFF),
          shadows: [
            // Its SHADOW_BLUR / SHADOW_DROP / SHADOW_ALPHA, at 75%.
            Shadow(
              color: const Color(0x86000000),
              blurRadius: 12 * unit,
              offset: Offset(0, 3 * unit),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    // Its capitals start where the wordmark's letters end (the line box has
    // room above them - taken back here).
    final top = under.bottom - 0.2 * size;
    final height = math.max(logo.height, (top + text.height + margin).ceil());
    // Wider than the logo when the handle runs past it (room for its
    // shadow too).
    final width =
        math.max(logo.width, (under.left + text.width + margin).ceil());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(logo, Offset.zero, Paint());
    text.paint(canvas, Offset(under.left, top));
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError("couldn't encode the watermark");
      return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    logo.dispose();
  }
}
