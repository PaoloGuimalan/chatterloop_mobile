import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'image_byte_cache.dart';

/// A display-only decode. Original bytes are shared across sizes; resized
/// bitmaps live only in Flutter's memory cache. Local previews use the same cap.
@immutable
class DisplayImage extends ImageProvider<DisplayImage> {
  const DisplayImage({
    required this.source,
    required this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.isLocal = false,
    this.maxDimension = 4096,
  })  : assert(width > 0),
        assert(height == null || height > 0);

  final String source;
  final int width;
  final int? height;
  final BoxFit fit;
  final bool isLocal;
  final int maxDimension;

  /// Keep enough pixels for cover's crop, without stretching, upscaling, or
  /// decoding an arbitrarily tall source at its full height.
  Size targetSize(int sourceWidth, int sourceHeight) {
    final sx = width / sourceWidth;
    final sy = height == null ? sx : height! / sourceHeight;
    final desired = height == null
        ? sx
        : fit == BoxFit.cover
            ? math.max(sx, sy)
            : fit == BoxFit.fitWidth
                ? sx
                : fit == BoxFit.fitHeight
                    ? sy
                    : math.min(sx, sy);
    final scale = math.min(1.0,
        math.min(desired, maxDimension / math.max(sourceWidth, sourceHeight)));
    return Size(
      (sourceWidth * scale).ceil().clamp(1, maxDimension).toDouble(),
      (sourceHeight * scale).ceil().clamp(1, maxDimension).toDouble(),
    );
  }

  @override
  Future<DisplayImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          DisplayImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _load(decode),
        scale: 1,
        debugLabel: source,
      );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final generation = ImageByteCache.instance.generation;
    try {
      final bytes = isLocal
          ? await File(source).readAsBytes()
          : await ImageByteCache.instance.bytes(source);
      final codec = await decode(await ui.ImmutableBuffer.fromUint8List(bytes),
          getTargetSize: (w, h) {
        final target = targetSize(w, h);
        return ui.TargetImageSize(
            width: target.width.toInt(), height: target.height.toInt());
      });
      if (!isLocal && generation != ImageByteCache.instance.generation) {
        codec.dispose();
        throw StateError('Image load invalidated by logout');
      }
      return codec;
    } catch (_) {
      scheduleMicrotask(() {
        if (isLocal || generation == ImageByteCache.instance.generation) {
          PaintingBinding.instance.imageCache.evict(this);
        }
      });
      if (!isLocal && generation == ImageByteCache.instance.generation) {
        await ImageByteCache.instance.evict(source);
      }
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DisplayImage &&
      source == other.source &&
      width == other.width &&
      height == other.height &&
      fit == other.fit &&
      isLocal == other.isLocal &&
      maxDimension == other.maxDimension;

  @override
  int get hashCode =>
      Object.hash(source, width, height, fit, isLocal, maxDimension);
}
