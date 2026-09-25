import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chatterloop_app/core/media/composition.dart';

/// Makes a picked photo ready for the editor and the renderer: decoded the
/// way Flutter shows it, at most [maxEdge] on its long side, written as a PNG
/// into [folder].
///
/// Why not hand ffmpeg the original:
///  - Orientation. A phone photo is often stored sideways with an EXIF flag
///    saying "turn me"; Flutter honours it, ffmpeg's JPEG reader may not. The
///    PNG is upright, so the preview and the render agree.
///  - Formats. HEIC and the like are decoded by the platform here, so ffmpeg
///    only ever sees a PNG.
///  - Size. A 48MP original would be rescaled every composed second; 2560 on
///    the long edge is plenty for a 720x1280 canvas even zoomed in.
///
/// Throws if the platform can't decode [path].
Future<MediaSource> prepareStill(
  String path,
  Directory folder, {
  int maxEdge = 2560,
}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(
    await File(path).readAsBytes(),
  );
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (width, height) {
      if (math.max(width, height) <= maxEdge) return ui.TargetImageSize();
      // One side only: the decoder keeps the aspect ratio.
      return width >= height
          ? ui.TargetImageSize(width: maxEdge)
          : ui.TargetImageSize(height: maxEdge);
    },
  );
  final frame = await codec.getNextFrame();
  codec.dispose();
  final image = frame.image;
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) {
      throw const FormatException("Couldn't encode the photo");
    }
    final out = File(
      '${folder.path}/still-${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await out.writeAsBytes(
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      flush: true,
    );
    return MediaSource(
      path: out.path,
      kind: MediaKind.image,
      width: image.width,
      height: image.height,
    );
  } finally {
    image.dispose();
  }
}
