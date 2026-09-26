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
/// [qpCeilings] false leaves the profile's QP ceilings out - for the retry
/// when an encoder refuses them, or when they pushed the file past
/// [EncodingProfile.maxBytes].
///
/// [watermarkPath] is the profile's [EncodingProfile.watermark] image as a
/// file - needed when the profile has one and the edit keeps it
/// ([Composition.watermark]).
///
/// Throws an [ArgumentError] for an edit that cannot be rendered (no length,
/// no media size), or a watermark without its file.
RenderCommand buildRenderCommand({
  required Composition composition,
  required EncodingProfile profile,
  required H264Encoder encoder,
  required String outputPath,
  bool qpCeilings = true,
  String? watermarkPath,
}) {
  final layer = composition.layer;
  final source = layer.source;
  if (source.width <= 0 || source.height <= 0) {
    throw ArgumentError.value(
        source.path, 'composition', 'media has no known size');
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

  // ---- Inputs: 0 = the media, then the audio track and the watermark
  // (each when there is one).
  final args = <String>['-hide_banner', '-y'];
  if (source.isVideo) {
    final start = layer.trim?.start ?? Duration.zero;
    if (start > Duration.zero) args.addAll(['-ss', _seconds(start)]);
    args.addAll(['-t', seconds, '-i', source.path]);
  } else {
    // One frame, repeated by the loop filter below - that works for any
    // image demuxer, where `-loop 1` only exists on image2.
    args.addAll(['-i', source.path]);
  }

  // Input 1 only when the track is heard - a muted track isn't read at all.
  final track = (composition.audio?.heard ?? false) ? composition.audio : null;
  final trackLength =
      track == null ? duration : _atMost(track.trim.length, duration);
  if (track != null) {
    if (track.trim.start > Duration.zero) {
      args.addAll(['-ss', _seconds(track.trim.start)]);
    }
    args.addAll(['-t', _seconds(trackLength), '-i', track.path]);
  }

  final watermark = composition.watermark ? profile.watermark : null;
  if (watermark != null && watermarkPath == null) {
    throw ArgumentError.value(
        watermarkPath, 'watermarkPath', 'the profile stamps a watermark');
  }
  final watermarkInput = track == null ? 1 : 2;
  if (watermark != null) args.addAll(['-i', watermarkPath!]);

  // ---- Video.
  final graph = <String>[];
  // A video is brought to the output rate first (a 60fps source then costs
  // half); a still becomes an endless run of one frame at _stillComposeFps.
  final prepare = source.isVideo
      ? ['fps=$fps']
      : [
          'loop=loop=-1:size=1:start=0',
          'setpts=N/($_stillComposeFps*TB)',
        ];
  // Stills are brought up to the output rate at the very end.
  final finish = [
    if (!source.isVideo) 'fps=$fps',
    'format=${encoder.pixelFormat}',
  ];

  final part = visiblePart(
    mediaWidth: source.width,
    mediaHeight: source.height,
    canvasWidth: w.toDouble(),
    canvasHeight: h.toDouble(),
    transform: layer.transform,
  );

  String? foregroundIn;
  final foreground = <String>[];
  if (composition.background.isBlur) {
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
      graph.add(_chain('[0:v:0]', [...prepare, ...blur], '[bg]'));
    } else {
      graph.add(_chain('[0:v:0]', [...prepare, 'split=2'], '[bgsrc][fgsrc]'));
      graph.add(_chain('[bgsrc]', blur, '[bg]'));
      foregroundIn = '[fgsrc]';
    }
  } else {
    final rgb = (composition.background.argb & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0');
    graph.add('color=c=0x$rgb:s=${w}x$h:r=$fps:d=$seconds,setsar=1[bg]');
    if (part != null) {
      foregroundIn = '[0:v:0]';
      foreground.addAll(prepare);
    }
  }

  // The composed frame: its input(s), and the filters that make it. When
  // nothing of the media reaches the canvas, the background is the frame.
  var frameIn = '[bg]';
  final frame = <String>[];
  if (part != null && foregroundIn != null) {
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
    graph.add(_chain(foregroundIn, foreground, '[fg]'));
    // overlay's w/h are the (rotated) foreground's own size, so this centres
    // it whatever the rotation made its bounding box.
    final x = placed.centerX.toStringAsFixed(2);
    final y = placed.centerY.toStringAsFixed(2);
    frameIn = '[bg][fg]';
    frame.add('overlay=x=$x-w/2:y=$y-h/2:shortest=1');
  }

  if (watermark == null) {
    graph.add(_chain(frameIn, [...frame, ...finish], '[v]'));
  } else {
    // Stamped last, over the composed frame - and before a still is brought
    // up to the output rate, so once a second rather than on every frame.
    // The logo is a single image: overlay holds it for every frame.
    if (frame.isNotEmpty) {
      graph.add(_chain(frameIn, frame, '[frame]'));
      frameIn = '[frame]';
    }
    graph.add(_chain(
      '[$watermarkInput:v:0]',
      ['scale=${evenPixels(w * watermark.width)}:-2:flags=$_scaleFlags'],
      '[wm]',
    ));
    final left = (w * watermark.left).round();
    final bottom = (h * watermark.bottom).round();
    graph.add(_chain(
      '$frameIn[wm]',
      ['overlay=x=$left:y=H-h-$bottom:eof_action=repeat', ...finish],
      '[v]',
    ));
  }

  // ---- Audio: every output has a track (silent when there is no sound),
  // spanning the whole video. The video's own sound and the audio track
  // each get their volume, then are mixed.
  final layout = profile.audioChannels == 1 ? 'mono' : 'stereo';
  final rate = profile.audioSampleRate;
  final format = 'aformat=sample_rates=$rate:channel_layouts=$layout';
  // Each heard sound as (input, filters); padded with silence to the end so
  // a short song doesn't end the mix early.
  final sounds = <(String, List<String>)>[
    if (layer.soundHeard) ('[0:a:0]', [format, ..._volume(layer.volume)]),
    if (track != null)
      (
        '[1:a:0]',
        [
          format,
          ..._volume(track.volume),
          ..._fades(track, trackLength),
        ]
      ),
  ];
  final pad = 'apad=whole_dur=$seconds';
  switch (sounds) {
    case []:
      graph.add('anullsrc=r=$rate:cl=$layout,atrim=duration=$seconds[a]');
    case [final only]:
      graph.add(_chain(only.$1, [...only.$2, pad], '[a]'));
    default:
      final labels = <String>[];
      for (final (i, sound) in sounds.indexed) {
        labels.add('[s$i]');
        graph.add(_chain(sound.$1, [...sound.$2, pad], '[s$i]'));
      }
      // normalize=0: the volumes are the author's, not divided by the
      // number of sounds. The limiter keeps two loud sounds from clipping.
      graph.add(_chain(
        labels.join(),
        [
          'amix=inputs=${labels.length}:duration=longest:normalize=0',
          'alimiter=limit=0.95:level=0',
        ],
        '[a]',
      ));
  }

  final filterGraph = graph.join(';');
  final still = !source.isVideo;
  final ceiling = still ? profile.stillQp : profile.videoQp;
  final withCeilings = qpCeilings && encoder.takesQpCeilings && ceiling != null;
  final keyframeInterval = still
      ? profile.stillKeyframeInterval ?? profile.keyframeInterval
      : profile.keyframeInterval;
  args.addAll([
    '-filter_complex', filterGraph,
    '-map', '[v]',
    '-map', '[a]',
    '-c:v', encoder.name,
    if (encoder.profile != null) ...['-profile:v', encoder.profile!],
    ...encoder.options,
    '-b:v', '${profile.videoBitrateFor(duration)}',
    if (withCeilings) ...[
      '-qp_i_max',
      '${ceiling.keyframe}',
      '-qp_p_max',
      '${ceiling.other}',
    ],
    '-g', '$keyframeInterval',
    '-r', '$fps',
    '-c:a', 'aac',
    '-b:a', '${profile.audioBitrate}',
    '-ar', '$rate',
    '-ac', '${profile.audioChannels}',
    '-t', seconds,
    // Nothing from the source file's metadata - a phone video's carries
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
    hasSound: composition.hasSound,
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
