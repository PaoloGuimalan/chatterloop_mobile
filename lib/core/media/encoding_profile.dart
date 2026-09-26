import 'dart:math' as math;

import 'package:chatterloop_app/core/utils/upload_limits.dart';
import 'package:flutter/foundation.dart';

/// The coarsest quantizer an encoder may use (H.264: 0 finest .. 51
/// coarsest), for keyframes and for the frames between them.
///
/// A bitrate is only a target: on a hard scene - low light, grain, fast
/// motion - an encoder holding to it codes the frame coarsely, which is what
/// "grainy and noisy" looks like. A ceiling stops that; the frame takes the
/// bits it needs instead.
@immutable
class QpCeiling {
  final int keyframe;
  final int other;

  const QpCeiling({required this.keyframe, required this.other})
      : assert(keyframe >= 0 && keyframe <= 51),
        assert(other >= 0 && other <= 51);
}

/// A logo stamped into the bottom-left corner of a picture.
///
/// Only on copies SAVED to the phone - the editor's Save, a posted Moment
/// downloaded from the viewer. What is posted stays without it. This is how
/// it looks, per kind of output ([EncodingProfile.watermark]).
///
/// Sizes are fractions of the picture's SHORTER side (a portrait Moment's
/// width), so a landscape video gets the same size of logo as a portrait one.
@immutable
class Watermark {
  /// A Flutter asset: a PNG with transparency, its shadow baked in
  /// (tool/make_watermark.py builds the Chatterloop one).
  final String asset;

  /// A Flutter asset: where the wordmark sits in [asset] - the handle goes
  /// under it (the tool writes it next to the PNG). Null: under the logo.
  final String? layout;

  /// Its width.
  final double width;

  /// Its gap from the left edge.
  final double left;

  /// Its gap from the bottom edge.
  final double bottom;

  /// The size of the handle under the logo ("@paolo") - its own, so the
  /// logo can be resized without the name going with it.
  final double handleSize;

  const Watermark({
    required this.asset,
    this.layout,
    this.width = 0.22,
    this.left = 0.05,
    this.bottom = 0.12,
    this.handleSize = 0.022,
  })  : assert(width > 0 && width < 1),
        assert(left >= 0 && left + width < 1),
        assert(bottom >= 0 && bottom < 1),
        assert(handleSize > 0);

  /// The Chatterloop logo, 22% of the width, near the left edge and lifted
  /// a little off the bottom, the handle under it at 2.2% (24px at 1080).
  static const chatterloop = Watermark(
    asset: 'assets/images/watermark.png',
    layout: 'assets/images/watermark.json',
  );
}

/// What an encode produces - resolution, frame rate, bitrates, length cap.
///
/// One place to change output quality. A feature picks a profile (Moments use
/// [EncodingProfile.moment]); a future feature with other needs (a post
/// video, a reel) declares its own rather than editing this one.
///
/// Everything here must stay inside what the server accepts for that feature
/// - for Moments see server/reusables/hooks/momentMedia.js (H.264 + AAC,
/// longest edge <= 1920, <= 2 minutes).
class EncodingProfile {
  /// Output frame size in pixels (portrait for Moments). Both EVEN - H.264
  /// with 4:2:0 chroma needs it. Android hardware encoders want multiples of
  /// 16; FFmpeg's MediaCodec encoder pads to that and marks the padding to
  /// be cropped off, so 1080 works.
  final int width;
  final int height;
  final int fps;

  /// The video bitrate, bits per second - what a short edit is encoded at.
  /// A longer one gets less when [maxBytes] says so ([videoBitrateFor]).
  final int videoBitrate;

  /// The most one output may weigh - the server's upload cap. Edits long
  /// enough that [videoBitrate] would come near it get a lower bitrate, and
  /// a render that still comes out over is redone without the QP ceilings.
  /// Null: no size limit.
  final int? maxBytes;

  /// A keyframe every this many frames (2s at 30fps) - seeking and
  /// start-of-playback both land on keyframes.
  final int keyframeInterval;

  /// Quality floors for a video, and for a still (a photo). Only encoders
  /// that take them use them (Android 12+ MediaCodec); null: none.
  final QpCeiling? videoQp;
  final QpCeiling? stillQp;

  /// A still's keyframe spacing, in frames. Nothing moves, so keyframes far
  /// apart cost much less and look the same. Null: [keyframeInterval].
  final int? stillKeyframeInterval;

  final int audioBitrate;
  final int audioSampleRate;
  final int audioChannels;

  /// Hard cap on the output length - an edit longer than this is cut here.
  final Duration maxDuration;

  /// Poster JPEG quality on ffmpeg's -q:v scale: 2 (best) .. 31 (worst).
  final int posterQuality;

  /// The logo a SAVED copy of this kind of output is stamped with, or null
  /// for none. Renders for posting leave it out.
  final Watermark? watermark;

  const EncodingProfile({
    required this.width,
    required this.height,
    this.fps = 30,
    this.videoBitrate = 2500000,
    this.maxBytes,
    this.keyframeInterval = 60,
    this.videoQp,
    this.stillQp,
    this.stillKeyframeInterval,
    this.audioBitrate = 128000,
    this.audioSampleRate = 44100,
    this.audioChannels = 2,
    required this.maxDuration,
    this.posterQuality = 3,
    this.watermark,
  })  : assert(width > 0 && width % 2 == 0),
        assert(height > 0 && height % 2 == 0);

  /// Moments: 1080p portrait, up to 2 minutes.
  ///
  /// History, all from phone tests: 720p at 2.5Mbps looked soft and noisy
  /// full-screen; 1080p at 5Mbps (H.264 High) was still grainy - a phone's
  /// hardware encoder needs far more than x264 for the same picture. Now
  /// 12Mbps, which clips up to about a minute get; longer ones are held to
  /// what keeps them under the upload cap ([kMaxUploadBytes], 100MB) -
  /// ~5.8Mbps at 2 minutes - and the QP ceilings keep those from breaking up
  /// on hard scenes.
  static const moment = EncodingProfile(
    width: 1080,
    height: 1920,
    videoBitrate: 12000000,
    maxBytes: kMaxUploadBytes,
    videoQp: QpCeiling(keyframe: 27, other: 30),
    // A photo should look like the photo: its keyframes near-lossless. They
    // are rare (every 10s) and the frames between cost next to nothing.
    stillQp: QpCeiling(keyframe: 20, other: 24),
    stillKeyframeInterval: 300,
    maxDuration: Duration(minutes: 2),
    watermark: Watermark.chatterloop,
  );

  /// The share of [maxBytes] a bitrate is chosen to fill - encoders
  /// overshoot a little, and the MP4's index weighs something too.
  static const _budgetShare = 0.85;

  /// The least a long edit is given, however long.
  static const _minVideoBitrate = 2000000;

  double get aspectRatio => width / height;

  /// The video bitrate for an output [duration] long: [videoBitrate], or
  /// less when that would take the file past its share of [maxBytes].
  int videoBitrateFor(Duration duration) {
    final limit = maxBytes;
    final seconds = duration.inMicroseconds / 1e6;
    if (limit == null || seconds <= 0) return videoBitrate;
    final budget = (limit * _budgetShare * 8 / seconds - audioBitrate).floor();
    return math.max(_minVideoBitrate, math.min(videoBitrate, budget));
  }

  EncodingProfile copyWith({
    int? width,
    int? height,
    int? fps,
    int? videoBitrate,
    int? maxBytes,
    int? keyframeInterval,
    QpCeiling? videoQp,
    QpCeiling? stillQp,
    int? stillKeyframeInterval,
    int? audioBitrate,
    int? audioSampleRate,
    int? audioChannels,
    Duration? maxDuration,
    int? posterQuality,
    Watermark? watermark,
    bool clearWatermark = false,
  }) =>
      EncodingProfile(
        width: width ?? this.width,
        height: height ?? this.height,
        fps: fps ?? this.fps,
        videoBitrate: videoBitrate ?? this.videoBitrate,
        maxBytes: maxBytes ?? this.maxBytes,
        keyframeInterval: keyframeInterval ?? this.keyframeInterval,
        videoQp: videoQp ?? this.videoQp,
        stillQp: stillQp ?? this.stillQp,
        stillKeyframeInterval:
            stillKeyframeInterval ?? this.stillKeyframeInterval,
        audioBitrate: audioBitrate ?? this.audioBitrate,
        audioSampleRate: audioSampleRate ?? this.audioSampleRate,
        audioChannels: audioChannels ?? this.audioChannels,
        maxDuration: maxDuration ?? this.maxDuration,
        posterQuality: posterQuality ?? this.posterQuality,
        watermark: clearWatermark ? null : (watermark ?? this.watermark),
      );
}
