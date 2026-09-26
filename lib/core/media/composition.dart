/// An EDIT: what to render, independent of screen size - the contract
/// between an editor (which produces it) and a renderer (which reads it).
///
/// Versioned JSON, so a future renderer (a browser one, see the Moments plan)
/// or a newer app can read an older edit. Positions are fractions of the
/// canvas and sizes are relative to "fits inside the canvas", so the same
/// edit renders the same at any output resolution.
///
/// Today an edit is ONE visual layer (a photo or a video) on a background,
/// plus an optional audio track. `layers` is a list, and the JSON keys leave
/// room, for what comes later: text, stickers (image layers), transitions.
library;

import 'package:flutter/foundation.dart';

enum MediaKind { image, video }

/// A media file as the renderer needs to know it - its DISPLAYED size (after
/// any rotation the file asks for) and, for a video, its length and whether
/// it has sound. Filled from MediaInfo when the file is picked.
@immutable
class MediaSource {
  final String path;
  final MediaKind kind;
  final int width;
  final int height;
  final Duration? duration;
  final bool hasAudio;

  const MediaSource({
    required this.path,
    required this.kind,
    required this.width,
    required this.height,
    this.duration,
    this.hasAudio = false,
  });

  bool get isVideo => kind == MediaKind.video;

  Map<String, dynamic> toJson() => {
        'path': path,
        'kind': kind.name,
        'w': width,
        'h': height,
        if (duration != null) 'duration_ms': duration!.inMilliseconds,
        'has_audio': hasAudio,
      };

  factory MediaSource.fromJson(Map<String, dynamic> json) => MediaSource(
        path: json['path'] as String,
        kind: MediaKind.values.byName(json['kind'] as String),
        width: (json['w'] as num).toInt(),
        height: (json['h'] as num).toInt(),
        duration: json['duration_ms'] == null
            ? null
            : Duration(milliseconds: (json['duration_ms'] as num).toInt()),
        hasAudio: json['has_audio'] == true,
      );
}

/// Where a layer sits on the canvas.
///
///  - [cx], [cy]: the layer's CENTRE, as a fraction of the canvas (0..1).
///  - [scale]: 1 = the whole media fits inside the canvas ("contain"); larger
///    zooms in. See [LayerTransform.fill] for the "cover" value.
///  - [rotationDeg]: clockwise, degrees.
@immutable
class LayerTransform {
  final double cx;
  final double cy;
  final double scale;
  final double rotationDeg;

  const LayerTransform({
    this.cx = 0.5,
    this.cy = 0.5,
    this.scale = 1,
    this.rotationDeg = 0,
  });

  static const fit = LayerTransform();

  /// The scale at which media of [mediaAspect] (w/h) FILLS a canvas of
  /// [canvasAspect] - no bars, edges cropped.
  static double fillScale(double mediaAspect, double canvasAspect) {
    // contain = min(cw/mw, ch/mh), cover = max(...); in aspect terms the
    // ratio of the two is max(r, 1/r) with r = mediaAspect / canvasAspect.
    final r = mediaAspect / canvasAspect;
    return r >= 1 ? r : 1 / r;
  }

  static LayerTransform fill(double mediaAspect, double canvasAspect) =>
      LayerTransform(scale: fillScale(mediaAspect, canvasAspect));

  LayerTransform copyWith({
    double? cx,
    double? cy,
    double? scale,
    double? rotationDeg,
  }) =>
      LayerTransform(
        cx: cx ?? this.cx,
        cy: cy ?? this.cy,
        scale: scale ?? this.scale,
        rotationDeg: rotationDeg ?? this.rotationDeg,
      );

  Map<String, dynamic> toJson() =>
      {'cx': cx, 'cy': cy, 'scale': scale, 'rotation': rotationDeg};

  factory LayerTransform.fromJson(Map<String, dynamic> json) => LayerTransform(
        cx: (json['cx'] as num?)?.toDouble() ?? 0.5,
        cy: (json['cy'] as num?)?.toDouble() ?? 0.5,
        scale: (json['scale'] as num?)?.toDouble() ?? 1,
        rotationDeg: (json['rotation'] as num?)?.toDouble() ?? 0,
      );
}

/// A time range within a source.
@immutable
class TrimRange {
  final Duration start;
  final Duration end;

  // No `end >= start` assert: Duration can't be compared in a constant
  // expression, and a const range is the common case. A backwards range is
  // simply empty.
  const TrimRange(this.start, this.end);

  Duration get length => end > start ? end - start : Duration.zero;

  Map<String, dynamic> toJson() =>
      {'start_ms': start.inMilliseconds, 'end_ms': end.inMilliseconds};

  factory TrimRange.fromJson(Map<String, dynamic> json) => TrimRange(
        Duration(milliseconds: (json['start_ms'] as num).toInt()),
        Duration(milliseconds: (json['end_ms'] as num).toInt()),
      );
}

/// The one visual layer of today's edits: a photo or a video, placed.
@immutable
class MediaLayer {
  final MediaSource source;
  final LayerTransform transform;

  /// Videos only: the part to use. Null = the whole video.
  final TrimRange? trim;

  /// Videos only: the level of the video's own sound, 0 (muted) ..2
  /// (1 = as recorded). Mixed with the audio track when there is one.
  final double volume;

  const MediaLayer({
    required this.source,
    this.transform = LayerTransform.fit,
    this.trim,
    this.volume = 1,
  });

  /// Whether the video's own sound is heard in the output.
  bool get soundHeard => source.isVideo && source.hasAudio && volume > 0;

  MediaLayer copyWith({
    LayerTransform? transform,
    TrimRange? trim,
    double? volume,
  }) =>
      MediaLayer(
        source: source,
        transform: transform ?? this.transform,
        trim: trim ?? this.trim,
        volume: volume ?? this.volume,
      );

  Map<String, dynamic> toJson() => {
        'type': 'media',
        'source': source.toJson(),
        'transform': transform.toJson(),
        if (trim != null) 'trim': trim!.toJson(),
        'volume': volume,
      };

  factory MediaLayer.fromJson(Map<String, dynamic> json) => MediaLayer(
        source: MediaSource.fromJson(Map<String, dynamic>.from(json['source'])),
        transform: LayerTransform.fromJson(
            Map<String, dynamic>.from(json['transform'] ?? const {})),
        trim: json['trim'] == null
            ? null
            : TrimRange.fromJson(Map<String, dynamic>.from(json['trim'])),
        // Edits saved before volumes had an on/off `keep_audio`.
        volume: (json['volume'] as num?)?.toDouble() ??
            (json['keep_audio'] == false ? 0 : 1),
      );
}

/// Sound laid over the edit - music on a photo, or on a video (mixed with
/// the video's own sound at their two volumes). It starts with the edit.
@immutable
class AudioTrack {
  final String path;

  /// The part of the file to use.
  final TrimRange trim;

  /// 0 (muted) ..2 (1 = as recorded).
  final double volume;
  final Duration fadeIn;
  final Duration fadeOut;

  const AudioTrack({
    required this.path,
    required this.trim,
    this.volume = 1,
    this.fadeIn = Duration.zero,
    this.fadeOut = Duration.zero,
  });

  bool get heard => volume > 0;

  AudioTrack copyWith({
    TrimRange? trim,
    double? volume,
    Duration? fadeIn,
    Duration? fadeOut,
  }) =>
      AudioTrack(
        path: path,
        trim: trim ?? this.trim,
        volume: volume ?? this.volume,
        fadeIn: fadeIn ?? this.fadeIn,
        fadeOut: fadeOut ?? this.fadeOut,
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        'trim': trim.toJson(),
        'volume': volume,
        'fade_in_ms': fadeIn.inMilliseconds,
        'fade_out_ms': fadeOut.inMilliseconds,
      };

  factory AudioTrack.fromJson(Map<String, dynamic> json) => AudioTrack(
        path: json['path'] as String,
        trim: TrimRange.fromJson(Map<String, dynamic>.from(json['trim'])),
        volume: (json['volume'] as num?)?.toDouble() ?? 1,
        fadeIn:
            Duration(milliseconds: (json['fade_in_ms'] as num?)?.toInt() ?? 0),
        fadeOut:
            Duration(milliseconds: (json['fade_out_ms'] as num?)?.toInt() ?? 0),
      );
}

/// What fills the canvas around the media.
@immutable
class CompositionBackground {
  /// "blur": a blurred, darkened copy of the media, filling the canvas.
  /// "color": a solid [argb] colour.
  final String type;
  final int argb;

  const CompositionBackground._(this.type, this.argb);

  static const blur = CompositionBackground._('blur', 0xFF000000);

  const CompositionBackground.color(int argb) : this._('color', argb);

  bool get isBlur => type == 'blur';

  Map<String, dynamic> toJson() => {'type': type, if (!isBlur) 'argb': argb};

  factory CompositionBackground.fromJson(Map<String, dynamic> json) =>
      json['type'] == 'color'
          ? CompositionBackground.color((json['argb'] as num).toInt())
          : blur;
}

@immutable
class Composition {
  /// Bump when the meaning of a field changes; readers check it.
  static const currentVersion = 1;

  final int version;
  final CompositionBackground background;
  final MediaLayer layer;
  final AudioTrack? audio;

  /// How long a photo lasts when nothing else sets the length (no audio
  /// track). Ignored for videos and for photos with an audio track.
  final Duration stillDuration;

  /// Whether the output is stamped with the profile's watermark (when the
  /// profile has one - EncodingProfile.watermark, which sets its look). On
  /// unless the edit opts out - the switch for posting without it.
  final bool watermark;

  const Composition({
    this.version = currentVersion,
    this.background = CompositionBackground.blur,
    required this.layer,
    this.audio,
    this.stillDuration = const Duration(seconds: 30),
    this.watermark = true,
  });

  /// The edit's length before any profile cap: the video's (trimmed) length,
  /// else the audio track's, else [stillDuration].
  Duration get naturalDuration {
    final source = layer.source;
    if (source.isVideo) {
      return layer.trim?.length ?? source.duration ?? Duration.zero;
    }
    if (audio != null) return audio!.trim.length;
    return stillDuration;
  }

  /// Whether the output will carry REAL sound (not only a silent track).
  bool get hasSound => (audio?.heard ?? false) || layer.soundHeard;

  Composition copyWith({
    CompositionBackground? background,
    MediaLayer? layer,
    AudioTrack? audio,
    bool clearAudio = false,
    Duration? stillDuration,
    bool? watermark,
  }) =>
      Composition(
        version: version,
        background: background ?? this.background,
        layer: layer ?? this.layer,
        audio: clearAudio ? null : (audio ?? this.audio),
        stillDuration: stillDuration ?? this.stillDuration,
        watermark: watermark ?? this.watermark,
      );

  Map<String, dynamic> toJson() => {
        'v': version,
        'background': background.toJson(),
        'layers': [layer.toJson()],
        if (audio != null) 'audio': audio!.toJson(),
        'still_ms': stillDuration.inMilliseconds,
        'watermark': watermark,
      };

  factory Composition.fromJson(Map<String, dynamic> json) {
    final layers = (json['layers'] as List).cast<Map>();
    return Composition(
      version: (json['v'] as num?)?.toInt() ?? currentVersion,
      background: CompositionBackground.fromJson(
          Map<String, dynamic>.from(json['background'] ?? const {})),
      layer: MediaLayer.fromJson(Map<String, dynamic>.from(layers.first)),
      audio: json['audio'] == null
          ? null
          : AudioTrack.fromJson(Map<String, dynamic>.from(json['audio'])),
      stillDuration:
          Duration(milliseconds: (json['still_ms'] as num?)?.toInt() ?? 30000),
      // Edits from before the switch were all stamped.
      watermark: json['watermark'] != false,
    );
  }
}
