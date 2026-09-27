import 'dart:io';
import 'dart:ui' as ui;

import 'package:chatterloop_app/core/media/composition.dart';
import 'package:flutter/material.dart';

/// A text layer's words drawn into a see-through PNG - so the preview shows
/// it, and the render lays it over the video, just like a photo layer (no
/// ffmpeg text filter, which the app's ffmpeg build may not have).
///
/// Drawn as if on a [referenceWidth]-wide canvas: [framingScale] sizes it
/// on the real one to match.
class TextCardImage {
  TextCardImage._();

  static const referenceWidth = 1080.0;
  static const fontSize = 80.0;
  static const _maxLineWidth = 940.0;

  static TextAlign alignOf(TextCard card) => switch (card.align) {
        'left' => TextAlign.left,
        'right' => TextAlign.right,
        _ => TextAlign.center,
      };

  /// The box behind boxed words: dark behind light words, light behind dark.
  static Color boxColorFor(Color text) => text.computeLuminance() > 0.5
      ? const Color(0xCC000000)
      : const Color(0xEEFFFFFF);

  static TextStyle styleOf(TextCard card,
          {double size = fontSize, String? fontFamily}) =>
      TextStyle(
        fontSize: size,
        height: 1.2,
        color: Color(card.argb),
        fontFamily: fontFamily,
        fontWeight: card.bold ? FontWeight.w800 : FontWeight.w500,
        // Unboxed, a soft shadow keeps them readable on any picture.
        shadows: card.boxed
            ? null
            : [Shadow(color: Colors.black54, blurRadius: size * 0.08)],
      );

  /// [card] drawn into a PNG in [dir]: the photo to lay on the canvas.
  static Future<MediaSource> render(TextCard card, Directory dir,
      {String? fontFamily}) async {
    final painter = TextPainter(
      text: TextSpan(
          text: card.text, style: styleOf(card, fontFamily: fontFamily)),
      textAlign: alignOf(card),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _maxLineWidth);
    final pad = card.boxed ? fontSize * 0.45 : fontSize * 0.15;
    final width = (painter.width + pad * 2).ceil();
    final height = (painter.height + pad * 2).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (card.boxed) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
            const Radius.circular(fontSize * 0.3)),
        Paint()..color = boxColorFor(Color(card.argb)),
      );
    }
    painter.paint(canvas, Offset(pad, pad));
    final image = await recorder.endRecording().toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    painter.dispose();

    final file = File(
        '${dir.path}/text_${DateTime.now().microsecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
    return MediaSource(
        path: file.path, kind: MediaKind.image, width: width, height: height);
  }

  /// The layer scale that shows [source] (a render of words) as big on a
  /// canvas of [canvasAspect] as it was drawn on the reference one - scale
  /// being relative to "fits inside the canvas".
  static double framingScale(MediaSource source, double canvasAspect) {
    final aspect = source.width / source.height;
    // The share of the canvas's width it takes at scale 1 (fitted).
    final fitted = aspect >= canvasAspect ? 1.0 : aspect / canvasAspect;
    return (source.width / referenceWidth) / fitted;
  }
}
