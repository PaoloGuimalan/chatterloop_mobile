/// Turns an edit ([Composition]) into ffmpeg arguments.
///
/// Pure - no ffmpeg, no files - so every edit shape is unit-tested as the
/// exact argument list it produces. The media engine runs what this builds.
///
/// The output is what the server's strict Moment check accepts
/// (server/reusables/hooks/momentMedia.js): H.264 + AAC in an MP4 with the
/// index up front (faststart), sized and capped by the [EncodingProfile].
library;

import 'dart:math' as math;

import 'package:chatterloop_app/core/media/canvas_geometry.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/encoding_profile.dart';
import 'package:flutter/foundation.dart';

/// An H.264 encoder in the bundled ffmpeg (an LGPL build: hardware encoders
/// only - there is no software x264/openh264 to fall back to).
@immutable
class H264Encoder {
  /// ffmpeg's encoder name (`-c:v`).
  final String name;

  /// The frame format fed to it.
  final String pixelFormat;

  /// The H.264 profile asked for (`-profile:v`), or null for the encoder's
  /// own default. "high" matters: Android's encoders default to Baseline
  /// (no B-frames, weaker entropy coding), which at the same bitrate comes
  /// out visibly softer and blockier.
  final String? profile;

  /// Encoder-specific options, placed after `-c:v`.
  final List<String> options;

  /// Whether it takes QP ceilings ([EncodingProfile.videoQp]) - MediaCodec
  /// does (`-qp_i_max` / `-qp_p_max`, Android 12+; older Androids ignore
  /// them).
  final bool takesQpCeilings;

  const H264Encoder(
    this.name, {
    this.pixelFormat = 'nv12',
    this.profile,
    this.options = const [],
    this.takesQpCeilings = false,
  });

  /// Android's hardware encoder (MediaCodec), High profile, fed NV12 - the
  /// semi-planar layout most vendors' encoders take. (FFmpeg pads widths
  /// that are not a multiple of 16, like 1080, and marks the padding to be
  /// cropped off.)
  ///
  /// No `-level`: FFmpeg 8's MediaCodec encoder writes the PROFILE value
  /// into the level key, so setting one only confuses the codec.
  static const mediaCodec =
      H264Encoder('h264_mediacodec', profile: 'high', takesQpCeilings: true);

  /// The same fed planar YUV, for devices whose encoder refuses NV12.
  static const mediaCodecPlanar = H264Encoder('h264_mediacodec',
      pixelFormat: 'yuv420p', profile: 'high', takesQpCeilings: true);

  /// Last resort: the device's default profile, for an encoder that turns
  /// High down.
  static const mediaCodecDefault =
      H264Encoder('h264_mediacodec', takesQpCeilings: true);

  /// Apple's VideoToolbox, High profile. `allow_sw` lets it use Apple's own
  /// software encoder where there is no hardware one (the simulator).
  static const videoToolbox = H264Encoder('h264_videotoolbox',
      profile: 'high', options: ['-allow_sw', '1']);

  static const videoToolboxDefault =
      H264Encoder('h264_videotoolbox', options: ['-allow_sw', '1']);

  /// What to try on [platform], best first - the engine moves to the next
  /// only when an encode fails.
  static List<H264Encoder> candidatesFor(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.iOS || TargetPlatform.macOS => const [
            videoToolbox,
            videoToolboxDefault
          ],
        _ => const [mediaCodec, mediaCodecPlanar, mediaCodecDefault],
      };
}

/// A built render: the arguments, plus what the output will be.
@immutable
class RenderCommand {
  final List<String> arguments;

  /// The `-filter_complex` graph (also inside [arguments]) - kept apart for
  /// logs and tests.
  final String filterGraph;

  /// The output's length: the edit's natural length, capped by the profile.
  final Duration duration;

  /// Whether the output carries real sound, not only the silent track every
  /// output gets.
  final bool hasSound;

  /// Whether it asks the encoder for QP ceilings - so whether the same
  /// render without them is worth trying (a device that refuses them, an
  /// output that came out too big).
  final bool usesQpCeilings;

  const RenderCommand({
    required this.arguments,
    required this.filterGraph,
    required this.duration,
    required this.hasSound,
    this.usesQpCeilings = false,
  });
}

/// A still is composed this many times a second and each frame repeated up
/// to the profile's frame rate - one scale/blur per second instead of one
/// per output frame. (A still that moves - a pan, a zoom - will need the
/// full rate.)
const _stillComposeFps = 1;

/// The blurred background: drawn at a quarter of the canvas size (cheap),
/// Gaussian-blurred, scaled back up and darkened a little so the media
/// stands out. The blur is a fraction of the canvas width - the editor's
/// preview uses the same (34px at 720 wide) - so it looks alike at any
/// output size.
///
/// ONLY LGPL filters: the app bundles an LGPL FFmpeg, which leaves out the
/// GPL ones - boxblur and eq among them, which is what this first used and
/// every blurred render failed on ("No option name near '10:2'"). The
/// allowed set is checked against the bundled build in the tests.
const _blurDownscale = 4;
const _blurSigmaPerWidth = 34 / 720;

/// Luma scaled by 0.88 about video black (16) - a light darkening.
const _blurDim = 'lutyuv=y=16+(val-16)*0.88';

/// How the media is resized onto the canvas: Lanczos keeps a downscaled 4K
/// frame or a 2560px photo sharp, where the default (bicubic) softens them.
const _scaleFlags = 'lanczos';

/// The ffmpeg arguments that render [composition] to an MP4 at
/// [outputPath], encoded per [profile] with [encoder].
///
/// Each clip is composed on its own - framed over the background, cut to
/// exactly its length, with its own sound or silence as long - and the clips
/// are joined end to end, with a black, silent piece for every blank: one
/// left before a clip, and the time after the last clip that a layer or a
/// song runs on into. The overlays are drawn over that, lane by lane
/// (a higher lane over a lower), each framed the same way but with no
/// background, from its place in the edit. The audio tracks and the
/// overlays' own sound are mixed in, each from its place. An edit longer
/// than the profile allows is cut there.
///
/// [qpCeilings] false leaves the profile's QP ceilings out - for the retry
/// when an encoder refuses them, or when they pushed the file past
/// [EncodingProfile.maxBytes].
///
/// [watermarkPath]: stamp the profile's [EncodingProfile.watermark] (that
/// image, as a file) into the corner - for a copy saved to the phone. What
/// gets posted is left without it. [watermarkLogoWidth] is the logo's width
/// in that image: the image is scaled by what brings the logo to its size,
/// so a handle longer than the logo (see watermark_image.dart) runs on to
/// the right at the same scale instead of shrinking the logo. Without it,
/// the whole image is sized as the logo.
///
/// Throws an [ArgumentError] for an edit that cannot be rendered (no
/// length, a clip with no media size).
RenderCommand buildRenderCommand({
  required Composition composition,
  required EncodingProfile profile,
  required H264Encoder encoder,
  required String outputPath,
  bool qpCeilings = true,
  String? watermarkPath,
  int? watermarkLogoWidth,
}) {
  for (final clip in [
    ...composition.clips,
    for (final overlay in composition.overlays) overlay.clip,
  ]) {
    if (clip.source.width <= 0 || clip.source.height <= 0) {
      throw ArgumentError.value(
          clip.source.path, 'composition', 'media has no known size');
    }
  }
  final natural = composition.naturalDuration;
  final duration =
      natural > profile.maxDuration ? profile.maxDuration : natural;
  if (duration <= Duration.zero) {
    throw ArgumentError.value(duration, 'composition', 'has no length');
  }

  final w = profile.width;
  final h = profile.height;
  final fps = profile.fps;
  final seconds = _seconds(duration);

  // The main run as it plays out, each piece as long as it plays - a clip
  // (with its input), or a blank (null) - the ones past the profile's cap
  // cut short or left out.
  final pieces = <(MediaLayer?, Duration)>[];
  var left = duration;
  void piece(MediaLayer? clip, Duration length) {
    final used = _atMost(length, left);
    if (used <= Duration.zero) return;
    pieces.add((clip, used));
    left -= used;
  }

  for (final clip in composition.clips) {
    if (clip.gapBefore > Duration.zero) piece(null, clip.gapBefore);
    piece(clip, clip.length);
  }
  // Layers or songs running on past the clips: blank under them.
  if (left > Duration.zero) piece(null, left);

  // ---- Inputs: the clips in order, then each heard audio track, then the
  // overlays, then the watermark. Blanks read nothing.
  final args = <String>['-hide_banner', '-y'];
  final inputOf = <int, int>{};
  for (final (i, (clip, length)) in pieces.indexed) {
    if (clip == null) continue;
    inputOf[i] = inputOf.length;
    if (clip.source.isVideo) {
      final start = clip.usedRange.start;
      if (start > Duration.zero) args.addAll(['-ss', _seconds(start)]);
      args.addAll(['-t', _seconds(length), '-i', clip.source.path]);
    } else {
      // One frame, repeated by the loop filter below - that works for any
      // image demuxer, where `-loop 1` only exists on image2.
      args.addAll(['-i', clip.source.path]);
    }
  }
  final clipInputs = inputOf.length;

  // A muted track, or one starting after the end, isn't read at all.
  final tracks = <(int, AudioTrack, Duration)>[];
  for (final track in composition.audio) {
    if (!track.heard || track.start >= duration) continue;
    final used = _atMost(track.length, duration - track.start);
    if (used < const Duration(milliseconds: 10)) continue;
    final input = clipInputs + tracks.length;
    if (track.trim.start > Duration.zero) {
      args.addAll(['-ss', _seconds(track.trim.start)]);
    }
    args.addAll(['-t', _seconds(used), '-i', track.path]);
    tracks.add((input, track, used));
  }

  // The overlays that show before the end, each for as long as it shows -
  // drawn in list order, which is lane order: bottom first.
  final overlays = <(int, OverlayClip, Duration)>[];
  for (final overlay in composition.overlays) {
    if (overlay.start >= duration) continue;
    final used = _atMost(overlay.length, duration - overlay.start);
    if (used < const Duration(milliseconds: 10)) continue;
    final input = clipInputs + tracks.length + overlays.length;
    final source = overlay.clip.source;
    if (source.isVideo) {
      final start = overlay.clip.usedRange.start;
      if (start > Duration.zero) args.addAll(['-ss', _seconds(start)]);
      args.addAll(['-t', _seconds(used), '-i', source.path]);
    } else {
      args.addAll(['-i', source.path]);
    }
    overlays.add((input, overlay, used));
  }

  final watermark = watermarkPath == null ? null : profile.watermark;
  final watermarkInput = clipInputs + tracks.length + overlays.length;
  if (watermark != null) args.addAll(['-i', watermarkPath!]);

  // ---- Each piece: [v<i>] and [a<i>], exactly its length.
  final graph = <String>[];
  final layout = profile.audioChannels == 1 ? 'mono' : 'stereo';
  final rate = profile.audioSampleRate;
  final format = 'aformat=sample_rates=$rate:channel_layouts=$layout';
  for (final (i, (clip, length)) in pieces.indexed) {
    if (clip == null) {
      // A blank: black, and silence as long.
      graph.add('color=c=black:s=${w}x$h:r=$fps:d=${_seconds(length)},'
          'format=yuv420p,setsar=1[v$i]');
      graph.add('anullsrc=r=$rate:cl=$layout,atrim=duration=${_seconds(length)}'
          '[a$i]');
      continue;
    }
    final input = inputOf[i]!;
    graph.addAll(_clipVideo(
      clip: clip,
      input: input,
      label: '[v$i]',
      length: length,
      background: composition.background,
      width: w,
      height: h,
      fps: fps,
    ));
    graph.add(clip.soundHeard
        ? _chain('[$input:a:0]', [
            format,
            ..._volume(clip.volume),
            // Held to the clip's length whatever the file's sound runs to.
            'apad=whole_dur=${_seconds(length)}',
            'atrim=duration=${_seconds(length)}',
            'asetpts=PTS-STARTPTS',
          ], '[a$i]')
        : 'anullsrc=r=$rate:cl=$layout,atrim=duration=${_seconds(length)}'
            '[a$i]');
  }

  // ---- The clips joined.
  var videoOut = '[v0]';
  var audioOut = '[a0]';
  if (pieces.length > 1) {
    final inputs = [
      for (var i = 0; i < pieces.length; i++) '[v$i][a$i]'
    ].join();
    graph.add('${inputs}concat=n=${pieces.length}:v=1:a=1[vcat][acat]');
    videoOut = '[vcat]';
    audioOut = '[acat]';
  }

  // ---- The overlays, each over what is under it: from its start, gone
  // again at its end (eof_action=pass lets the picture under it through).
  for (final (j, (input, overlay, used)) in overlays.indexed) {
    final chain = _overlayVideo(
      clip: overlay.clip,
      start: overlay.start,
      length: used,
      width: w,
      height: h,
      fps: fps,
    );
    if (chain == null) continue; // None of it on the canvas.
    final (filters, place) = chain;
    graph.add(_chain('[$input:v:0]', filters, '[ov$j]'));
    graph.add(_chain('$videoOut[ov$j]',
        ['overlay=$place:eof_action=pass'], '[vo$j]'));
    videoOut = '[vo$j]';
  }

  // ---- The picture out: stamped, when asked, then in the encoder's format.
  if (watermark == null) {
    graph.add(_chain(videoOut, ['format=${encoder.pixelFormat}'], '[v]'));
  } else {
    final (scale, place) =
        _watermarkFilters(watermark, w, h, logoWidth: watermarkLogoWidth);
    graph.add(_chain('[$watermarkInput:v:0]', [scale], '[wm]'));
    graph.add(_chain(
        '$videoOut[wm]', [place, 'format=${encoder.pixelFormat}'], '[v]'));
  }

  // ---- The sound out: the clips' own, with each track and each overlay's
  // own sound laid over from its place in the edit.
  final heardOverlays = [
    for (final (j, (input, overlay, used)) in overlays.indexed)
      if (overlay.clip.soundHeard) (j, input, overlay, used)
  ];
  if (tracks.isEmpty && heardOverlays.isEmpty) {
    graph.add(_chain(audioOut, ['anull'], '[a]'));
  } else {
    final labels = [audioOut];
    for (final (j, (input, track, used)) in tracks.indexed) {
      final delay = track.start.inMilliseconds;
      graph.add(_chain('[$input:a:0]', [
        format,
        ..._volume(track.volume),
        ..._fades(track, used),
        if (delay > 0) 'adelay=delays=$delay:all=1',
        'apad=whole_dur=$seconds',
      ], '[t$j]'));
      labels.add('[t$j]');
    }
    for (final (j, input, overlay, used) in heardOverlays) {
      final delay = overlay.start.inMilliseconds;
      graph.add(_chain('[$input:a:0]', [
        format,
        ..._volume(overlay.clip.volume),
        'apad=whole_dur=${_seconds(used)}',
        'atrim=duration=${_seconds(used)}',
        'asetpts=PTS-STARTPTS',
        if (delay > 0) 'adelay=delays=$delay:all=1',
        'apad=whole_dur=$seconds',
      ], '[oa$j]'));
      labels.add('[oa$j]');
    }
    // duration=first: as long as the clips. normalize=0: the volumes are
    // the author's, not divided by the number of sounds. The limiter keeps
    // loud ones from clipping together.
    graph.add(_chain(labels.join(), [
      'amix=inputs=${labels.length}:duration=first:normalize=0',
      'alimiter=limit=0.95:level=0',
    ], '[a]'));
  }

  final filterGraph = graph.join(';');
  final still = composition.allStills;
  final ceiling = still ? profile.stillQp : profile.videoQp;
  final withCeilings = qpCeilings && encoder.takesQpCeilings && ceiling != null;
  final keyframeInterval = still
      ? profile.stillKeyframeInterval ?? profile.keyframeInterval
      : profile.keyframeInterval;
  args.addAll([
    '-filter_complex', filterGraph,
    '-map', '[v]',
    '-map', '[a]',
    ..._videoEncoding(encoder, profile, duration, keyframeInterval,
        withCeilings ? ceiling : null),
    '-r', '$fps',
    '-c:a', 'aac',
    '-b:a', '${profile.audioBitrate}',
    '-ar', '$rate',
    '-ac', '${profile.audioChannels}',
    '-t', seconds,
    // Nothing from the source files' metadata - a phone video's carries
    // where it was shot.
    '-map_metadata', '-1',
    '-map_chapters', '-1',
    // The index at the front, so playback starts before the whole file
    // has downloaded (and the server's check requires it).
    '-movflags', '+faststart',
    '-f', 'mp4',
    outputPath,
  ]);

  return RenderCommand(
    arguments: List.unmodifiable(args),
    filterGraph: filterGraph,
    duration: duration,
    hasSound: pieces.any((piece) => piece.$1?.soundHeard == true) ||
        tracks.isNotEmpty ||
        heardOverlays.isNotEmpty,
    usesQpCeilings: withCeilings,
  );
}

/// One clip's picture, framed on the canvas and cut to [length]: the chains
/// that end in [label].
List<String> _clipVideo({
  required MediaLayer clip,
  required int input,
  required String label,
  required Duration length,
  required CompositionBackground background,
  required int width,
  required int height,
  required int fps,
}) {
  final w = width, h = height;
  final source = clip.source;
  final graph = <String>[];
  final n = input;
  // A video is brought to the output rate first (a 60fps source then costs
  // half), and held on its last frame a moment in case the file runs a
  // little short of what its probe said; a still becomes an endless run of
  // one frame at _stillComposeFps.
  final prepare = source.isVideo
      ? ['fps=$fps', 'tpad=stop_mode=clone:stop_duration=1']
      : [
          'loop=loop=-1:size=1:start=0',
          'setpts=N/($_stillComposeFps*TB)',
        ];
  // Then exactly the clip's length, from 0 - the join needs both.
  final finish = [
    if (!source.isVideo) 'fps=$fps',
    'trim=duration=${_seconds(length)}',
    'setpts=PTS-STARTPTS',
    'format=yuv420p',
    'setsar=1',
  ];

  final part = visiblePart(
    mediaWidth: source.width,
    mediaHeight: source.height,
    canvasWidth: w.toDouble(),
    canvasHeight: h.toDouble(),
    transform: clip.transform,
  );

  String? foregroundIn;
  final foreground = <String>[];
  if (background.isBlur) {
    final bw = evenPixels(w / _blurDownscale);
    final bh = evenPixels(h / _blurDownscale);
    final blur = [
      'scale=$bw:$bh:force_original_aspect_ratio=increase',
      'crop=$bw:$bh',
      // Sigma at the quarter size the blur runs at.
      'gblur=sigma=${(_blurSigmaPerWidth * w / _blurDownscale).toStringAsFixed(2)}',
      'scale=$w:$h',
      _blurDim,
      'setsar=1',
    ];
    if (part == null) {
      graph.add(_chain('[$n:v:0]', [...prepare, ...blur], '[bg$n]'));
    } else {
      graph.add(
          _chain('[$n:v:0]', [...prepare, 'split=2'], '[bgsrc$n][fgsrc$n]'));
      graph.add(_chain('[bgsrc$n]', blur, '[bg$n]'));
      foregroundIn = '[fgsrc$n]';
    }
  } else {
    final rgb = (background.argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    graph.add('color=c=0x$rgb:s=${w}x$h:r=$fps:d=${_seconds(length)},'
        'setsar=1[bg$n]');
    if (part != null) {
      foregroundIn = '[$n:v:0]';
      foreground.addAll(prepare);
    }
  }

  if (part == null || foregroundIn == null) {
    // Nothing of the media reaches the canvas: the background is the frame.
    graph.add(_chain('[bg$n]', finish, label));
    return graph;
  }
  final placed = part.placement;
  if (!part.isWhole) {
    // As fractions of the decoded frame, so a probe that was a pixel off
    // can never ask for a crop outside it.
    final mw = source.width, mh = source.height;
    foreground.add('crop=w=iw*${part.width}/$mw:h=ih*${part.height}/$mh'
        ':x=iw*${part.left}/$mw:y=ih*${part.top}/$mh:exact=1');
  }
  foreground
    ..add('scale=${evenPixels(placed.width)}:${evenPixels(placed.height)}'
        ':flags=$_scaleFlags')
    ..add('setsar=1')
    ..addAll(_rotationFilters(placed.rotation));
  graph.add(_chain(foregroundIn, foreground, '[fg$n]'));
  // overlay's w/h are the (rotated) foreground's own size, so this centres
  // it whatever the rotation made its bounding box.
  final x = placed.centerX.toStringAsFixed(2);
  final y = placed.centerY.toStringAsFixed(2);
  graph.add(_chain(
    '[bg$n][fg$n]',
    ['overlay=x=$x-w/2:y=$y-h/2:shortest=1', ...finish],
    label,
  ));
  return graph;
}

/// An overlay's picture, framed on the canvas with nothing around it, cut to
/// [length] and moved to [start] in the edit: its filters, and where
/// overlay puts it (`x=..:y=..`). Null when none of it reaches the canvas.
(List<String>, String)? _overlayVideo({
  required MediaLayer clip,
  required Duration start,
  required Duration length,
  required int width,
  required int height,
  required int fps,
}) {
  final source = clip.source;
  final part = visiblePart(
    mediaWidth: source.width,
    mediaHeight: source.height,
    canvasWidth: width.toDouble(),
    canvasHeight: height.toDouble(),
    transform: clip.transform,
  );
  if (part == null) return null;
  final placed = part.placement;
  final mw = source.width, mh = source.height;
  final filters = [
    // As a clip's: a video at the output rate and held on its last frame;
    // a still composed once a second.
    if (source.isVideo) ...[
      'fps=$fps',
      'tpad=stop_mode=clone:stop_duration=1',
    ] else ...[
      'loop=loop=-1:size=1:start=0',
      'setpts=N/($_stillComposeFps*TB)',
    ],
    if (!part.isWhole)
      'crop=w=iw*${part.width}/$mw:h=ih*${part.height}/$mh'
          ':x=iw*${part.left}/$mw:y=ih*${part.top}/$mh:exact=1',
    'scale=${evenPixels(placed.width)}:${evenPixels(placed.height)}'
        ':flags=$_scaleFlags',
    'setsar=1',
    ..._rotationFilters(placed.rotation),
    if (!source.isVideo) 'fps=$fps',
    'trim=duration=${_seconds(length)}',
    // From its place in the edit: overlay shows nothing of it before.
    start > Duration.zero
        ? 'setpts=PTS-STARTPTS+${_seconds(start)}/TB'
        : 'setpts=PTS-STARTPTS',
  ];
  final x = placed.centerX.toStringAsFixed(2);
  final y = placed.centerY.toStringAsFixed(2);
  return (filters, 'x=$x-w/2:y=$y-h/2');
}

/// The watermark's two filters for a [width] x [height] picture: its scale
/// (sized from the picture's shorter side, so a landscape video gets the
/// same size of logo as a portrait one) and its overlay, at the left, a
/// little up from the bottom. The logo is one image: overlay holds it for every frame.
(String, String) _watermarkFilters(
  Watermark watermark,
  int width,
  int height, {
  int? logoWidth,
}) {
  final side = math.min(width, height);
  final target = evenPixels(side * watermark.width);
  // By a factor when the logo's own width in the image is known: the image
  // may be wider (a long handle), the logo must still come out [target].
  final scale = logoWidth == null || logoWidth <= 0
      ? 'scale=$target:-2:flags=$_scaleFlags'
      : 'scale=trunc(iw*${(target / logoWidth).toStringAsFixed(6)}/2)*2:-2'
          ':flags=$_scaleFlags';
  final left = (side * watermark.left).round();
  final bottom = (side * watermark.bottom).round();
  return (
    scale,
    'overlay=x=$left:y=H-h-$bottom:eof_action=repeat',
  );
}

/// The video encoder's arguments: codec, profile, bitrate, the QP [ceiling]
/// when given, keyframes.
List<String> _videoEncoding(
  H264Encoder encoder,
  EncodingProfile profile,
  Duration duration,
  int keyframeInterval,
  QpCeiling? ceiling,
) =>
    [
      '-c:v', encoder.name,
      if (encoder.profile != null) ...['-profile:v', encoder.profile!],
      ...encoder.options,
      '-b:v', '${profile.videoBitrateFor(duration)}',
      if (ceiling != null) ...[
        '-qp_i_max',
        '${ceiling.keyframe}',
        '-qp_p_max',
        '${ceiling.other}',
      ],
      '-g', '$keyframeInterval',
    ];

/// The ffmpeg arguments that stamp the profile's watermark onto a copy of
/// the media at [inputPath] (a posted Moment, downloaded to be saved): a
/// video re-encoded to an MP4, a photo written as a JPEG, at [outputPath].
///
/// [width] x [height] is the media's displayed size (ffprobe's, rotation
/// applied - ffmpeg turns the frames upright as it reads them); [duration]
/// a video's length, for the bitrate and progress.
RenderCommand buildStampCommand({
  required String inputPath,
  required String watermarkPath,
  int? watermarkLogoWidth,
  required String outputPath,
  required int width,
  required int height,
  required bool isImage,
  required EncodingProfile profile,
  required H264Encoder encoder,
  Duration duration = Duration.zero,
  bool qpCeilings = true,
}) {
  final watermark = profile.watermark;
  if (watermark == null) {
    throw ArgumentError.value(profile, 'profile', 'has no watermark');
  }
  if (width <= 0 || height <= 0) {
    throw ArgumentError.value(inputPath, 'inputPath', 'media has no known size');
  }
  final (scale, place) = _watermarkFilters(watermark, width, height,
      logoWidth: watermarkLogoWidth);
  final filterGraph = [
    _chain('[1:v:0]', [scale], '[wm]'),
    _chain('[0:v:0][wm]',
        [place, if (!isImage) 'format=${encoder.pixelFormat}'], '[v]'),
  ].join(';');
  final inputs = [
    '-hide_banner', '-y',
    '-i', inputPath,
    '-i', watermarkPath,
    '-filter_complex', filterGraph,
    '-map', '[v]',
  ];
  if (isImage) {
    return RenderCommand(
      arguments: List.unmodifiable([
        ...inputs,
        '-frames:v', '1',
        '-q:v', '2',
        '-update', '1',
        '-map_metadata', '-1',
        outputPath,
      ]),
      filterGraph: filterGraph,
      duration: Duration.zero,
      hasSound: false,
    );
  }
  final ceiling = profile.videoQp;
  final withCeilings = qpCeilings && encoder.takesQpCeilings && ceiling != null;
  return RenderCommand(
    arguments: List.unmodifiable([
      ...inputs,
      // Its sound as it was, when it has any.
      '-map', '0:a:0?',
      ..._videoEncoding(encoder, profile, duration, profile.keyframeInterval,
          withCeilings ? ceiling : null),
      '-c:a', 'aac',
      '-b:a', '${profile.audioBitrate}',
      '-map_metadata', '-1',
      '-map_chapters', '-1',
      '-movflags', '+faststart',
      '-f', 'mp4',
      outputPath,
    ]),
    filterGraph: filterGraph,
    duration: duration,
    hasSound: true,
    usesQpCeilings: withCeilings,
  );
}

/// The ffmpeg arguments that save [videoPath]'s first frame as a JPEG at
/// [posterPath] - the frame a viewer sees before the video plays.
List<String> buildPosterCommand({
  required String videoPath,
  required String posterPath,
  required EncodingProfile profile,
}) =>
    List.unmodifiable([
      '-hide_banner',
      '-y',
      '-i', videoPath,
      '-an',
      '-frames:v', '1',
      '-q:v', '${profile.posterQuality}',
      // One image, not a numbered sequence.
      '-update', '1',
      posterPath,
    ]);

/// The ffmpeg arguments for a small JPEG of [videoPath] at [at] - a video
/// clip's picture on its timeline card.
List<String> buildThumbnailCommand({
  required String videoPath,
  required Duration at,
  required String outputPath,
  int width = 240,
}) =>
    List.unmodifiable([
      '-hide_banner',
      '-y',
      '-ss', _seconds(at),
      '-i', videoPath,
      '-an',
      '-frames:v', '1',
      '-vf', 'scale=$width:-2',
      '-q:v', '5',
      '-update', '1',
      outputPath,
    ]);

/// The filters that turn a layer by [radians] clockwise. Quarter turns are
/// exact pixel moves; any other angle needs alpha so the corners the turn
/// opens up show the background.
List<String> _rotationFilters(double radians) {
  final degrees = ((radians * 180 / math.pi) % 360 + 360) % 360;
  bool near(double target) => (degrees - target).abs() < 0.01;
  if (near(0) || near(360)) return const [];
  if (near(90)) return const ['transpose=clock'];
  if (near(180)) return const ['hflip', 'vflip'];
  if (near(270)) return const ['transpose=cclock'];
  final a = (degrees * math.pi / 180).toStringAsFixed(6);
  return [
    'format=rgba',
    'rotate=a=$a:ow=rotw($a):oh=roth($a):c=black@0',
  ];
}

String _chain(String input, List<String> filters, String output) =>
    '$input${filters.join(',')}$output';

List<String> _volume(double volume) => (volume - 1).abs() > 0.001
    ? ['volume=${volume.toStringAsFixed(3)}']
    : const [];

/// The track's fades, within the [length] of it that is used.
List<String> _fades(AudioTrack track, Duration length) {
  final fadeIn = _atMost(track.fadeIn, length);
  final fadeOut = _atMost(track.fadeOut, length);
  return [
    if (fadeIn > Duration.zero) 'afade=t=in:st=0:d=${_seconds(fadeIn)}',
    if (fadeOut > Duration.zero)
      'afade=t=out:st=${_seconds(length - fadeOut)}:d=${_seconds(fadeOut)}',
  ];
}

Duration _atMost(Duration value, Duration cap) => value > cap ? cap : value;

/// Seconds with millisecond precision - what ffmpeg's time options take.
String _seconds(Duration d) => (d.inMicroseconds / 1e6).toStringAsFixed(3);
