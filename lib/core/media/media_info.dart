import 'package:chatterloop_app/core/media/composition.dart';

/// What inspecting a picked file tells the editor and the renderer.
///
/// Parsed from ffprobe's JSON (`-show_format -show_streams`), which is what
/// FFprobeKit.getMediaInformation returns - pure, so it is unit-tested with
/// sample JSON.
class MediaInfo {
  final String path;
  final bool hasVideo;
  final bool hasAudio;

  /// The DISPLAYED size: a phone video stored 1920x1080 with a -90 rotation
  /// displays as 1080x1920, and ffmpeg auto-rotates when decoding, so the
  /// displayed size is the one the edit works with.
  final int width;
  final int height;

  /// Clockwise degrees the file asks to be rotated by (0, 90, 180, 270).
  final int rotation;
  final Duration? duration;
  final String? videoCodec;
  final String? audioCodec;
  final String? format;

  const MediaInfo({
    required this.path,
    required this.hasVideo,
    required this.hasAudio,
    required this.width,
    required this.height,
    required this.rotation,
    this.duration,
    this.videoCodec,
    this.audioCodec,
    this.format,
  });

  /// A still: an image format, or a single-frame "video" stream with no length
  /// (how ffprobe reports a JPEG/PNG/HEIC).
  bool get isImage {
    const imageCodecs = {'mjpeg', 'png', 'webp', 'hevc_image', 'bmp', 'gif'};
    final f = format ?? '';
    return f.contains('image2') ||
        f.contains('_pipe') ||
        f == 'webp' ||
        (videoCodec != null &&
            imageCodecs.contains(videoCodec) &&
            (duration == null || duration!.inMilliseconds <= 40));
  }

  MediaSource toSource() => MediaSource(
        path: path,
        kind: isImage ? MediaKind.image : MediaKind.video,
        width: width,
        height: height,
        duration: isImage ? null : duration,
        hasAudio: hasAudio,
      );

  /// From ffprobe's JSON output (the map FFprobeKit exposes as
  /// getAllProperties()).
  factory MediaInfo.fromProbeJson(String path, Map<dynamic, dynamic> json) {
    final streams = (json['streams'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    final format = json['format'] is Map ? json['format'] as Map : const {};
    final video = streams.cast<Map?>().firstWhere(
          (s) => s!['codec_type'] == 'video',
          orElse: () => null,
        );
    final audio = streams.cast<Map?>().firstWhere(
          (s) => s!['codec_type'] == 'audio',
          orElse: () => null,
        );

    final rotation = video == null ? 0 : _rotationOf(video);
    var width = _int(video?['width']);
    var height = _int(video?['height']);
    if (rotation == 90 || rotation == 270) {
      final w = width;
      width = height;
      height = w;
    }

    final seconds =
        double.tryParse('${format['duration'] ?? video?['duration'] ?? ''}');
    return MediaInfo(
      path: path,
      hasVideo: video != null,
      hasAudio: audio != null,
      width: width,
      height: height,
      rotation: rotation,
      duration: seconds == null
          ? null
          : Duration(microseconds: (seconds * 1000000).round()),
      videoCodec: video?['codec_name']?.toString(),
      audioCodec: audio?['codec_name']?.toString(),
      format: format['format_name']?.toString(),
    );
  }

  /// Rotation from the display matrix (current ffprobe: side_data_list) or
  /// the legacy `rotate` tag, normalised to clockwise 0/90/180/270.
  ///
  /// ffprobe reports the display matrix's rotation counter-clockwise (a
  /// portrait phone video shows -90), the legacy tag clockwise (90).
  static int _rotationOf(Map stream) {
    num? ccw;
    final sideData = stream['side_data_list'];
    if (sideData is List) {
      for (final entry in sideData.whereType<Map>()) {
        if (entry['rotation'] is num) {
          ccw = entry['rotation'] as num;
          break;
        }
      }
    }
    int clockwise;
    if (ccw != null) {
      clockwise = (-ccw).round();
    } else {
      final tags = stream['tags'];
      final tag = tags is Map ? num.tryParse('${tags['rotate'] ?? ''}') : null;
      clockwise = (tag ?? 0).round();
    }
    final normalised = ((clockwise % 360) + 360) % 360;
    // Snap to a quarter turn - encoders only ever write those.
    return ((normalised + 45) ~/ 90 * 90) % 360;
  }

  static int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
}
