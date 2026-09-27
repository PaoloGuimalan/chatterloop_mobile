/// An EDIT: what to render, independent of screen size - the contract
/// between an editor (which produces it) and a renderer (which reads it).
///
/// Versioned JSON, so a future renderer (a browser one, see the Moments plan)
/// or a newer app can read an older edit. Positions are fractions of the
/// canvas and sizes are relative to "fits inside the canvas", so the same
/// edit renders the same at any output resolution.
///
/// An edit is a run of CLIPS - photos and videos, one after another, each
/// framed on the canvas its own way - over one background; OVERLAYS - more
/// clips laid over that run in LANES, a higher lane drawn on top; and AUDIO
/// tracks along the same timeline, in lanes of their own that play
/// together. It runs as long as whatever ends last. Wherever nothing is -
/// a blank left between clips, the time after the last clip that a layer or
/// a song runs on into - it is black and silent. The JSON leaves room for
/// what comes later: transitions, text, stickers.
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

  @override
  bool operator ==(Object other) =>
      other is LayerTransform &&
      other.cx == cx &&
      other.cy == cy &&
      other.scale == scale &&
      other.rotationDeg == rotationDeg;

  @override
  int get hashCode => Object.hash(cx, cy, scale, rotationDeg);

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

  @override
  bool operator ==(Object other) =>
      other is TrimRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TrimRange($start, $end)';

  Map<String, dynamic> toJson() =>
      {'start_ms': start.inMilliseconds, 'end_ms': end.inMilliseconds};

  factory TrimRange.fromJson(Map<String, dynamic> json) => TrimRange(
        Duration(milliseconds: (json['start_ms'] as num).toInt()),
        Duration(milliseconds: (json['end_ms'] as num).toInt()),
      );
}

/// One CLIP of the edit: a photo or a video, framed on the canvas, for its
/// [length].
@immutable
class MediaLayer {
  /// How long a photo shows unless its card is stretched - the viewers' own
  /// time for a photo.
  static const defaultStill = Duration(seconds: 6);

  final MediaSource source;
  final LayerTransform transform;

  /// Videos only: the part to use. Null = the whole video.
  final TrimRange? trim;

  /// Photos only: how long it shows. Null = [defaultStill].
  final Duration? duration;

  /// Videos only: the level of the video's own sound, 0 (muted) ..2
  /// (1 = as recorded). Mixed with the audio tracks.
  final double volume;

  /// Main clips only: a blank before it in the run - black, silent. Zero
  /// (the usual) sits it straight after the clip before.
  final Duration gapBefore;

  const MediaLayer({
    required this.source,
    this.transform = LayerTransform.fit,
    this.trim,
    this.duration,
    this.volume = 1,
    this.gapBefore = Duration.zero,
  });

  /// How long this clip runs in the edit.
  Duration get length => source.isVideo
      ? (trim?.length ?? source.duration ?? Duration.zero)
      : (duration ?? defaultStill);

  /// Videos: the part used ([trim], else all of it).
  TrimRange get usedRange =>
      trim ?? TrimRange(Duration.zero, source.duration ?? Duration.zero);

  /// Whether the video's own sound is heard in the output.
  bool get soundHeard => source.isVideo && source.hasAudio && volume > 0;

  MediaLayer copyWith({
    LayerTransform? transform,
    TrimRange? trim,
    Duration? duration,
    double? volume,
    Duration? gapBefore,
  }) =>
      MediaLayer(
        source: source,
        transform: transform ?? this.transform,
        trim: trim ?? this.trim,
        duration: duration ?? this.duration,
        volume: volume ?? this.volume,
        gapBefore: gapBefore ?? this.gapBefore,
      );

  Map<String, dynamic> toJson() => {
        'type': 'media',
        'source': source.toJson(),
        'transform': transform.toJson(),
        if (trim != null) 'trim': trim!.toJson(),
        if (duration != null) 'duration_ms': duration!.inMilliseconds,
        'volume': volume,
        if (gapBefore > Duration.zero) 'gap_before_ms': gapBefore.inMilliseconds,
      };

  factory MediaLayer.fromJson(Map<String, dynamic> json,
          {Duration? stillDuration}) =>
      MediaLayer(
        source: MediaSource.fromJson(Map<String, dynamic>.from(json['source'])),
        transform: LayerTransform.fromJson(
            Map<String, dynamic>.from(json['transform'] ?? const {})),
        trim: json['trim'] == null
            ? null
            : TrimRange.fromJson(Map<String, dynamic>.from(json['trim'])),
        duration: json['duration_ms'] == null
            ? stillDuration
            : Duration(milliseconds: (json['duration_ms'] as num).toInt()),
        // Edits saved before volumes had an on/off `keep_audio`.
        volume: (json['volume'] as num?)?.toDouble() ??
            (json['keep_audio'] == false ? 0 : 1),
        gapBefore: Duration(
            milliseconds: (json['gap_before_ms'] as num?)?.toInt() ?? 0),
      );
}

/// Sound laid along the edit - music, a voice-over - from [start], playing
/// the [trim] part of its file. Mixed with the clips' own sound.
@immutable
class AudioTrack {
  final String path;

  /// What the editor calls it (the file's name).
  final String? name;

  /// The whole file's length - how far the editor lets its part stretch.
  final Duration? fileLength;

  /// Where in the edit it starts.
  final Duration start;

  /// The part of the file to use.
  final TrimRange trim;

  /// Its row: tracks in one lane follow one another; the lanes play
  /// together, their sound mixed.
  final int lane;

  /// 0 (muted) ..2 (1 = as recorded).
  final double volume;
  final Duration fadeIn;
  final Duration fadeOut;

  const AudioTrack({
    required this.path,
    required this.trim,
    this.name,
    this.fileLength,
    this.start = Duration.zero,
    this.lane = 0,
    this.volume = 1,
    this.fadeIn = Duration.zero,
    this.fadeOut = Duration.zero,
  });

  bool get heard => volume > 0;

  Duration get length => trim.length;

  /// Where in the edit it stops.
  Duration get end => start + length;

  AudioTrack copyWith({
    Duration? start,
    TrimRange? trim,
    int? lane,
    double? volume,
    Duration? fadeIn,
    Duration? fadeOut,
  }) =>
      AudioTrack(
        path: path,
        name: name,
        fileLength: fileLength,
        start: start ?? this.start,
        trim: trim ?? this.trim,
        lane: lane ?? this.lane,
        volume: volume ?? this.volume,
        fadeIn: fadeIn ?? this.fadeIn,
        fadeOut: fadeOut ?? this.fadeOut,
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        if (name != null) 'name': name,
        if (fileLength != null) 'file_ms': fileLength!.inMilliseconds,
        'start_ms': start.inMilliseconds,
        'trim': trim.toJson(),
        'lane': lane,
        'volume': volume,
        'fade_in_ms': fadeIn.inMilliseconds,
        'fade_out_ms': fadeOut.inMilliseconds,
      };

  factory AudioTrack.fromJson(Map<String, dynamic> json) => AudioTrack(
        path: json['path'] as String,
        name: json['name'] as String?,
        fileLength: json['file_ms'] == null
            ? null
            : Duration(milliseconds: (json['file_ms'] as num).toInt()),
        start: Duration(milliseconds: (json['start_ms'] as num?)?.toInt() ?? 0),
        trim: TrimRange.fromJson(Map<String, dynamic>.from(json['trim'])),
        lane: (json['lane'] as num?)?.toInt() ?? 0,
        volume: (json['volume'] as num?)?.toDouble() ?? 1,
        fadeIn:
            Duration(milliseconds: (json['fade_in_ms'] as num?)?.toInt() ?? 0),
        fadeOut:
            Duration(milliseconds: (json['fade_out_ms'] as num?)?.toInt() ?? 0),
      );
}

/// A clip laid OVER the main run of clips: from [start] in the edit, on
/// overlay [lane] - 0 just above the main clips, each lane over the one
/// before. Framed on the canvas like any clip, but with no background of
/// its own: the picture under it shows around it. Its sound, if any, is
/// mixed in.
@immutable
class OverlayClip {
  final MediaLayer clip;

  /// Where in the edit it starts.
  final Duration start;
  final int lane;

  /// A TEXT layer's words and look - its [clip] is a picture of them (see
  /// text_card_image.dart), drawn and rendered like any photo layer; kept
  /// so the words can be changed and drawn again.
  final TextCard? text;

  const OverlayClip({
    required this.clip,
    this.start = Duration.zero,
    this.lane = 0,
    this.text,
  });

  Duration get length => clip.length;

  /// Where in the edit it stops.
  Duration get end => start + length;

  bool get isText => text != null;

  OverlayClip copyWith(
          {MediaLayer? clip, Duration? start, int? lane, TextCard? text}) =>
      OverlayClip(
        clip: clip ?? this.clip,
        start: start ?? this.start,
        lane: lane ?? this.lane,
        text: text ?? this.text,
      );

  Map<String, dynamic> toJson() => {
        'clip': clip.toJson(),
        'start_ms': start.inMilliseconds,
        'lane': lane,
        if (text != null) 'text': text!.toJson(),
      };

  factory OverlayClip.fromJson(Map<String, dynamic> json) => OverlayClip(
        clip: MediaLayer.fromJson(Map<String, dynamic>.from(json['clip'])),
        start: Duration(milliseconds: (json['start_ms'] as num?)?.toInt() ?? 0),
        lane: (json['lane'] as num?)?.toInt() ?? 0,
        text: json['text'] == null
            ? null
            : TextCard.fromJson(Map<String, dynamic>.from(json['text'])),
      );
}

/// How a text layer's words look. The app's own font; no animation.
@immutable
class TextCard {
  final String text;

  /// The words' colour.
  final int argb;

  /// On a box of a colour that stands out from theirs.
  final bool boxed;
  final bool bold;

  /// "left", "center" or "right".
  final String align;

  const TextCard({
    required this.text,
    this.argb = 0xFFFFFFFF,
    this.boxed = false,
    this.bold = true,
    this.align = 'center',
  });

  TextCard copyWith(
          {String? text, int? argb, bool? boxed, bool? bold, String? align}) =>
      TextCard(
        text: text ?? this.text,
        argb: argb ?? this.argb,
        boxed: boxed ?? this.boxed,
        bold: bold ?? this.bold,
        align: align ?? this.align,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'argb': argb,
        'boxed': boxed,
        'bold': bold,
        'align': align,
      };

  factory TextCard.fromJson(Map<String, dynamic> json) => TextCard(
        text: json['text'] as String? ?? '',
        argb: (json['argb'] as num?)?.toInt() ?? 0xFFFFFFFF,
        boxed: json['boxed'] as bool? ?? false,
        bold: json['bold'] as bool? ?? true,
        align: json['align'] as String? ?? 'center',
      );

  @override
  bool operator ==(Object other) =>
      other is TextCard &&
      other.text == text &&
      other.argb == argb &&
      other.boxed == boxed &&
      other.bold == bold &&
      other.align == align;

  @override
  int get hashCode => Object.hash(text, argb, boxed, bold, align);
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
  /// 2: a list of clips (was one layer) and of audio tracks (was one).
  /// 3: overlays, and lanes for the audio tracks.
  /// 4: blanks - a clip's [MediaLayer.gapBefore] - and an edit as long as
  /// whatever ends last, not only its clips.
  static const currentVersion = 4;

  final int version;
  final CompositionBackground background;

  /// Played one after another - the MAIN run - each after the blank before
  /// it ([MediaLayer.gapBefore]). Empty when only layers or songs are left.
  final List<MediaLayer> clips;

  /// Over the main run, ordered by lane, then start - so in the order they
  /// are drawn. Within a lane they never overlap.
  final List<OverlayClip> overlays;

  /// Ordered by lane, then start. Within a lane they never overlap; across
  /// lanes they play together.
  final List<AudioTrack> audio;

  const Composition({
    this.version = currentVersion,
    this.background = CompositionBackground.blur,
    required this.clips,
    this.overlays = const [],
    this.audio = const [],
  });

  /// How many overlay lanes there are (0 with no overlays).
  int get overlayLanes => overlays.fold(
      0, (int n, overlay) => overlay.lane >= n ? overlay.lane + 1 : n);

  /// How many audio lanes there are (0 with no tracks).
  int get audioLanes =>
      audio.fold(0, (int n, track) => track.lane >= n ? track.lane + 1 : n);

  /// The overlays showing at [at], bottom first - the order they are drawn.
  List<int> overlaysAt(Duration at) => [
        for (var i = 0; i < overlays.length; i++)
          if (at >= overlays[i].start && at < overlays[i].end) i
      ];

  /// Where the main run ends: its clips and the blanks between them.
  Duration get mainEnd => clips.fold(
      Duration.zero, (sum, clip) => sum + clip.gapBefore + clip.length);

  /// The edit's length before any profile cap: to the end of whatever ends
  /// last - the main clips, a layer, a song. Past the main clips, blank.
  Duration get naturalDuration {
    var end = mainEnd;
    for (final overlay in overlays) {
      if (overlay.end > end) end = overlay.end;
    }
    for (final track in audio) {
      if (track.end > end) end = track.end;
    }
    return end;
  }

  /// Where each main clip starts in the edit.
  List<Duration> get clipStarts {
    final starts = <Duration>[];
    var at = Duration.zero;
    for (final clip in clips) {
      at += clip.gapBefore;
      starts.add(at);
      at += clip.length;
    }
    return starts;
  }

  /// The main clip playing at [at], and how far into it - null in a blank
  /// (between clips, or before or past them). At the very end of an edit
  /// the last clip ends: its last moment.
  ({int index, Duration offset})? locate(Duration at) {
    var start = Duration.zero;
    for (var i = 0; i < clips.length; i++) {
      start += clips[i].gapBefore;
      final end = start + clips[i].length;
      if (at >= start && at < end) return (index: i, offset: at - start);
      start = end;
    }
    if (clips.isNotEmpty && at >= start && start == naturalDuration) {
      return (index: clips.length - 1, offset: clips.last.length);
    }
    return null;
  }

  /// Only photos (and blanks) - a still, or a slideshow - overlays
  /// included.
  bool get allStills =>
      clips.every((clip) => !clip.source.isVideo) &&
      overlays.every((overlay) => !overlay.clip.source.isVideo);

  /// Whether the output will carry REAL sound (not only a silent track).
  bool get hasSound {
    final end = naturalDuration;
    return clips.any((clip) => clip.soundHeard) ||
        overlays.any((o) => o.clip.soundHeard && o.start < end) ||
        audio.any((track) => track.heard && track.start < end);
  }

  Composition copyWith({
    CompositionBackground? background,
    List<MediaLayer>? clips,
    List<OverlayClip>? overlays,
    List<AudioTrack>? audio,
  }) =>
      Composition(
        version: version,
        background: background ?? this.background,
        clips: clips ?? this.clips,
        overlays: overlays ?? this.overlays,
        audio: audio ?? this.audio,
      );

  Map<String, dynamic> toJson() => {
        'v': version,
        'background': background.toJson(),
        'clips': [for (final clip in clips) clip.toJson()],
        'overlays': [for (final overlay in overlays) overlay.toJson()],
        'audio': [for (final track in audio) track.toJson()],
      };

  factory Composition.fromJson(Map<String, dynamic> json) {
    final background = CompositionBackground.fromJson(
        Map<String, dynamic>.from(json['background'] ?? const {}));
    if (json['clips'] == null) {
      // Version 1: one layer, one optional track, and the photo's length.
      final still =
          Duration(milliseconds: (json['still_ms'] as num?)?.toInt() ?? 30000);
      final layers = (json['layers'] as List).cast<Map>();
      final audio = json['audio'];
      return Composition(
        background: background,
        clips: [
          MediaLayer.fromJson(Map<String, dynamic>.from(layers.first),
              stillDuration: still)
        ],
        audio: [
          if (audio is Map) AudioTrack.fromJson(Map<String, dynamic>.from(audio))
        ],
      );
    }
    return Composition(
      version: (json['v'] as num?)?.toInt() ?? currentVersion,
      background: background,
      clips: [
        for (final clip in (json['clips'] as List).cast<Map>())
          MediaLayer.fromJson(Map<String, dynamic>.from(clip))
      ],
      // Version 2 had none, and its tracks all in one lane.
      overlays: [
        for (final overlay
            in (json['overlays'] as List? ?? const []).cast<Map>())
          OverlayClip.fromJson(Map<String, dynamic>.from(overlay))
      ],
      audio: [
        for (final track in (json['audio'] as List? ?? const []).cast<Map>())
          AudioTrack.fromJson(Map<String, dynamic>.from(track))
      ],
    );
  }
}
