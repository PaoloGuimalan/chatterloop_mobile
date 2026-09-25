import 'package:chatterloop_app/core/media/canvas_geometry.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/encoding_profile.dart';
import 'package:chatterloop_app/core/media/ffmpeg_command.dart';
import 'package:chatterloop_app/core/media/media_info.dart';
import 'package:chatterloop_app/core/utils/upload_limits.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _photo = MediaSource(
  path: '/in/photo.jpg',
  kind: MediaKind.image,
  width: 1600,
  height: 1200,
);

const _landscapeVideo = MediaSource(
  path: '/in/clip.mp4',
  kind: MediaKind.video,
  width: 1280,
  height: 720,
  duration: Duration(seconds: 8),
  hasAudio: true,
);

const _song = AudioTrack(
  path: '/in/song.mp3',
  trim: TrimRange(Duration(seconds: 2), Duration(milliseconds: 9500)),
  volume: 0.8,
  fadeIn: Duration(seconds: 1),
  fadeOut: Duration(seconds: 2),
);

/// A fixed 720x1280 profile, so the geometry below stays in round numbers
/// whatever the Moments profile is set to.
const _p720 = EncodingProfile(
  width: 720,
  height: 1280,
  maxDuration: Duration(minutes: 2),
);

RenderCommand _build(
  Composition composition, {
  EncodingProfile profile = _p720,
  H264Encoder encoder = H264Encoder.mediaCodec,
}) =>
    buildRenderCommand(
      composition: composition,
      profile: profile,
      encoder: encoder,
      outputPath: '/out/moment.mp4',
    );

/// The value following [flag] - the first occurrence after [from].
String _after(List<String> args, String flag, {int from = 0}) =>
    args[args.indexOf(flag, from) + 1];

/// The options given to the input [path]: everything between the previous
/// input (or the leading `-hide_banner -y`) and its `-i`.
List<String> _inputOptions(List<String> args, String path) {
  final dashI = args.indexOf(path) - 1;
  var start = dashI;
  while (args[start - 1] != '-y' && !(start >= 2 && args[start - 2] == '-i')) {
    start--;
  }
  return args.sublist(start, dashI);
}

void main() {
  group('Composition', () {
    test('round-trips through JSON', () {
      const edit = Composition(
        background: CompositionBackground.color(0xFF203040),
        layer: MediaLayer(
          source: _landscapeVideo,
          transform:
              LayerTransform(cx: 0.4, cy: 0.6, scale: 1.7, rotationDeg: 15),
          trim: TrimRange(Duration(seconds: 1), Duration(seconds: 5)),
          volume: 0.35,
        ),
        audio: _song,
        stillDuration: Duration(seconds: 12),
      );
      final back = Composition.fromJson(edit.toJson());

      expect(back.toJson(), edit.toJson());
      expect(back.version, Composition.currentVersion);
      expect(back.background.isBlur, isFalse);
      expect(back.background.argb, 0xFF203040);
      expect(back.layer.source.duration, const Duration(seconds: 8));
      expect(back.layer.transform.rotationDeg, 15);
      expect(back.layer.trim!.length, const Duration(seconds: 4));
      expect(back.layer.volume, 0.35);
      expect(back.audio!.volume, 0.8);
      expect(back.audio!.fadeOut, const Duration(seconds: 2));
      expect(back.stillDuration, const Duration(seconds: 12));
    });

    test('an edit saved with on/off video sound reads as a volume', () {
      final json = const Composition(layer: MediaLayer(source: _landscapeVideo))
          .toJson();
      final layer = Map<String, dynamic>.from((json['layers'] as List).first)
        ..remove('volume');
      Composition read(bool keep) => Composition.fromJson({
            ...json,
            'layers': [
              {...layer, 'keep_audio': keep}
            ],
          });
      expect(read(false).layer.volume, 0);
      expect(read(true).layer.volume, 1);
    });

    test('an edit without optional parts reads back with defaults', () {
      final back = Composition.fromJson(
          const Composition(layer: MediaLayer(source: _photo)).toJson());
      expect(back.background.isBlur, isTrue);
      expect(back.audio, isNull);
      expect(back.layer.trim, isNull);
      expect(back.layer.transform.scale, 1);
      expect(back.stillDuration, const Duration(seconds: 30));
    });

    test('natural length: trimmed video, else the audio track, else the still',
        () {
      expect(
        const Composition(
          layer: MediaLayer(
            source: _landscapeVideo,
            trim: TrimRange(Duration(seconds: 1), Duration(seconds: 5)),
          ),
          audio: _song,
        ).naturalDuration,
        const Duration(seconds: 4),
      );
      expect(
        const Composition(layer: MediaLayer(source: _landscapeVideo))
            .naturalDuration,
        const Duration(seconds: 8),
      );
      expect(
        const Composition(layer: MediaLayer(source: _photo), audio: _song)
            .naturalDuration,
        const Duration(milliseconds: 7500),
      );
      expect(
        const Composition(layer: MediaLayer(source: _photo)).naturalDuration,
        const Duration(seconds: 30),
      );
    });

    test('has sound only when something audible is left', () {
      expect(const Composition(layer: MediaLayer(source: _photo)).hasSound,
          isFalse);
      expect(
          const Composition(layer: MediaLayer(source: _photo), audio: _song)
              .hasSound,
          isTrue);
      expect(
          Composition(
            layer: const MediaLayer(source: _photo),
            audio: _song.copyWith(volume: 0),
          ).hasSound,
          isFalse);
      expect(
          const Composition(layer: MediaLayer(source: _landscapeVideo))
              .hasSound,
          isTrue);
      expect(
          const Composition(
                  layer: MediaLayer(source: _landscapeVideo, volume: 0))
              .hasSound,
          isFalse);
      expect(
          const Composition(
            layer: MediaLayer(source: _landscapeVideo, volume: 0),
            audio: _song,
          ).hasSound,
          isTrue);
    });

    test('a backwards trim is empty, not negative', () {
      expect(
        const TrimRange(Duration(seconds: 5), Duration(seconds: 2)).length,
        Duration.zero,
      );
    });
  });

  group('canvas geometry', () {
    const canvasW = 720.0, canvasH = 1280.0;

    test('fill scale covers the canvas', () {
      // Landscape 16:9 media on a 9:16 canvas: (16/9) / (9/16).
      expect(LayerTransform.fillScale(16 / 9, 9 / 16), closeTo(3.1605, 1e-3));
      expect(LayerTransform.fillScale(9 / 16, 9 / 16), 1);
      final fill = LayerTransform.fill(16 / 9, 9 / 16);
      final placed = placeLayer(
        mediaWidth: 1280,
        mediaHeight: 720,
        canvasWidth: canvasW,
        canvasHeight: canvasH,
        transform: fill,
      );
      expect(placed.height, closeTo(canvasH, 1e-6));
      expect(placed.width, greaterThan(canvasW));
    });

    test('scale 1 contains the media, centred', () {
      final placed = placeLayer(
        mediaWidth: 1600,
        mediaHeight: 1200,
        canvasWidth: canvasW,
        canvasHeight: canvasH,
        transform: LayerTransform.fit,
      );
      expect(placed.width, closeTo(720, 1e-6));
      expect(placed.height, closeTo(540, 1e-6));
      expect(placed.centerX, 360);
      expect(placed.centerY, 640);
      expect(placed.rotation, 0);
    });

    test('a quarter turn swaps the bounding box', () {
      final placed = placeLayer(
        mediaWidth: 1280,
        mediaHeight: 720,
        canvasWidth: canvasW,
        canvasHeight: canvasH,
        transform: const LayerTransform(rotationDeg: 90),
      );
      expect(placed.rotatedWidth, closeTo(placed.height, 1e-6));
      expect(placed.rotatedHeight, closeTo(placed.width, 1e-6));
    });

    test('media inside the canvas is kept whole', () {
      final part = visiblePart(
        mediaWidth: 1600,
        mediaHeight: 1200,
        canvasWidth: canvasW,
        canvasHeight: canvasH,
        transform: LayerTransform.fit,
      )!;
      expect(part.isWhole, isTrue);
      expect(
          (part.left, part.top, part.width, part.height), (0, 0, 1600, 1200));
    });

    test('a zoom keeps only the columns that reach the canvas', () {
      final part = visiblePart(
        mediaWidth: 1280,
        mediaHeight: 720,
        canvasWidth: canvasW,
        canvasHeight: canvasH,
        transform: const LayerTransform(scale: 1.5),
      )!;
      // 720 canvas px / (0.5625 * 1.5) = 853.3 media px, centred.
      expect(part.isWhole, isFalse);
      expect(part.left, 213);
      expect(part.width, 854);
      expect((part.top, part.height), (0, 720));
      expect(part.placement.centerX, closeTo(360, 0.5));
      expect(part.placement.centerY, closeTo(640, 1e-6));
      expect(part.placement.width, closeTo(720, 1));
    });

    test('an off-centre zoom keeps the part under the canvas', () {
      // Centre pushed right: the media's LEFT side is what shows.
      final part = visiblePart(
        mediaWidth: 1280,
        mediaHeight: 720,
        canvasWidth: canvasW,
        canvasHeight: canvasH,
        transform: const LayerTransform(cx: 0.9, scale: 1.5),
      )!;
      expect(part.left, 0);
      expect(part.width, lessThan(1280));
      // The kept part is drawn where it sat in the full placement.
      final full = placeLayer(
        mediaWidth: 1280,
        mediaHeight: 720,
        canvasWidth: canvasW,
        canvasHeight: canvasH,
        transform: const LayerTransform(cx: 0.9, scale: 1.5),
      );
      final factor = full.width / 1280;
      final leftEdge = full.centerX - full.width / 2;
      expect(part.placement.centerX,
          closeTo(leftEdge + part.width * factor / 2, 1e-6));
    });

    test('rotated crops map the kept centre through the rotation', () {
      // Layer centred on the canvas's TOP edge and turned 90° clockwise: the
      // canvas is below its centre, and a clockwise turn puts the media's
      // RIGHT half there.
      final part = visiblePart(
        mediaWidth: 1000,
        mediaHeight: 1000,
        canvasWidth: 1000,
        canvasHeight: 1000,
        transform: const LayerTransform(cy: 0, rotationDeg: 90),
      )!;
      expect((part.left, part.width), (500, 500));
      expect((part.top, part.height), (0, 1000));
      expect(part.placement.centerX, closeTo(500, 1e-6));
      expect(part.placement.centerY, closeTo(250, 1e-6));
    });

    test('media dragged off the canvas has no visible part', () {
      expect(
        visiblePart(
          mediaWidth: 1600,
          mediaHeight: 1200,
          canvasWidth: canvasW,
          canvasHeight: canvasH,
          transform: const LayerTransform(cx: 3),
        ),
        isNull,
      );
    });

    test('even pixels round to even, at least 2', () {
      expect(evenPixels(405), 406);
      expect(evenPixels(720.4), 720);
      expect(evenPixels(0.4), 2);
    });
  });

  group('MediaInfo from ffprobe JSON', () {
    // Trimmed from real ffprobe output (the flags FFprobeKit uses).
    Map<String, dynamic> video({
      List<Map<String, dynamic>>? sideData,
      Map<String, dynamic>? tags,
    }) =>
        {
          'streams': [
            {
              'codec_name': 'h264',
              'codec_type': 'video',
              'width': 1920,
              'height': 1080,
              'duration': '6.000000',
              if (tags != null) 'tags': tags,
              if (sideData != null) 'side_data_list': sideData,
            },
            {
              'codec_name': 'aac',
              'codec_type': 'audio',
              'duration': '6.000000'
            },
          ],
          'format': {
            'format_name': 'mov,mp4,m4a,3gp,3g2,mj2',
            'duration': '6.000000',
          },
        };

    test('a phone video stored sideways reports its upright size', () {
      // ffprobe gives the display matrix's rotation counter-clockwise.
      final info = MediaInfo.fromProbeJson(
          '/v.mp4',
          video(sideData: [
            {'side_data_type': 'Display Matrix', 'rotation': 90},
          ]));
      expect((info.width, info.height), (1080, 1920));
      expect(info.rotation, 270);
      expect(info.duration, const Duration(seconds: 6));
      expect(info.hasVideo && info.hasAudio, isTrue);
      expect(info.videoCodec, 'h264');
      expect(info.isImage, isFalse);
      final source = info.toSource();
      expect(source.kind, MediaKind.video);
      expect(source.duration, const Duration(seconds: 6));
      expect(source.hasAudio, isTrue);
    });

    test('the usual iPhone portrait matrix (-90) is a clockwise quarter turn',
        () {
      final info = MediaInfo.fromProbeJson(
          '/v.mp4',
          video(sideData: [
            {'side_data_type': 'Display Matrix', 'rotation': -90},
          ]));
      expect(info.rotation, 90);
      expect((info.width, info.height), (1080, 1920));
    });

    test('the legacy rotate tag is read clockwise', () {
      final info =
          MediaInfo.fromProbeJson('/v.mp4', video(tags: {'rotate': '180'}));
      expect(info.rotation, 180);
      expect((info.width, info.height), (1920, 1080));
    });

    test('a JPEG is an image with no length', () {
      final info = MediaInfo.fromProbeJson('/p.jpg', {
        'streams': [
          {
            'codec_name': 'mjpeg',
            'codec_type': 'video',
            'width': 1600,
            'height': 1200,
            'duration': '0.040000',
          },
        ],
        'format': {'format_name': 'image2', 'duration': '0.040000'},
      });
      expect(info.isImage, isTrue);
      final source = info.toSource();
      expect(source.kind, MediaKind.image);
      expect(source.duration, isNull);
      expect((source.width, source.height), (1600, 1200));
    });

    test('an audio file has sound and no picture', () {
      final info = MediaInfo.fromProbeJson('/s.mp3', {
        'streams': [
          {'codec_name': 'mp3', 'codec_type': 'audio', 'duration': '12.042449'},
        ],
        'format': {'format_name': 'mp3', 'duration': '12.042449'},
      });
      expect(info.hasVideo, isFalse);
      expect(info.hasAudio, isTrue);
      expect(info.duration!.inMilliseconds, 12042);
    });
  });

  group('buildRenderCommand', () {
    test('uses only filters the bundled (LGPL) FFmpeg has', () {
      // Checked by name against the app's libavfilter.so. GPL-only filters
      // (boxblur, eq, ...) are NOT in it - a graph naming one fails on the
      // phone however well it runs on a desktop ffmpeg.
      const bundled = {
        'scale',
        'crop',
        'split',
        'overlay',
        'rotate',
        'transpose',
        'hflip',
        'vflip',
        'loop',
        'setpts',
        'fps',
        'format',
        'setsar',
        'color',
        'anullsrc',
        'atrim',
        'aformat',
        'volume',
        'afade',
        'apad',
        'amix',
        'alimiter',
        'gblur',
        'lutyuv',
      };
      Set<String> filtersOf(String graph) => {
            for (final chain in graph.split(';'))
              for (final filter in chain.split(','))
                filter.replaceAll(RegExp(r'\[[^\]]*\]'), '').split('=').first,
          };
      final edits = [
        const Composition(layer: MediaLayer(source: _photo)),
        const Composition(
          background: CompositionBackground.color(0xFF102030),
          layer: MediaLayer(
            source: _photo,
            transform: LayerTransform(scale: 2.5, rotationDeg: 30),
          ),
          audio: _song,
        ),
        for (final turn in [90.0, 180.0, 270.0])
          Composition(
            layer: MediaLayer(
              source: _landscapeVideo,
              transform: LayerTransform(scale: 1.4, rotationDeg: turn),
              volume: 0.5,
            ),
            audio: _song,
          ),
        const Composition(
          layer: MediaLayer(source: _landscapeVideo, volume: 0),
        ),
        const Composition(
          layer: MediaLayer(source: _photo, transform: LayerTransform(cx: 3)),
        ),
      ];
      for (final edit in edits) {
        final used = filtersOf(_build(edit).filterGraph);
        expect(used.difference(bundled), isEmpty, reason: '$used');
      }
    });

    test('a photo alone is a 30s still with a silent track', () {
      final cmd = _build(const Composition(layer: MediaLayer(source: _photo)));
      final args = cmd.arguments;

      expect(cmd.duration, const Duration(seconds: 30));
      expect(cmd.hasSound, isFalse);
      // Any image demuxer works: no image2-only `-loop`.
      expect(args, isNot(contains('-loop')));
      expect(_after(args, '-i'), '/in/photo.jpg');
      expect(
          cmd.filterGraph,
          contains(
              '[0:v:0]loop=loop=-1:size=1:start=0,setpts=N/(1*TB),split=2'));
      expect(cmd.filterGraph,
          contains('[fgsrc]scale=720:540:flags=lanczos,setsar=1[fg]'));
      expect(
          cmd.filterGraph,
          contains(
              'overlay=x=360.00-w/2:y=640.00-h/2:shortest=1,fps=30,format=nv12[v]'));
      expect(cmd.filterGraph,
          contains('anullsrc=r=44100:cl=stereo,atrim=duration=30.000[a]'));
      expect(_after(args, '-filter_complex'), cmd.filterGraph);
    });

    test('output settings match the profile and the server contract', () {
      final args = _build(const Composition(layer: MediaLayer(source: _photo)))
          .arguments;
      final out = args.sublist(args.indexOf('-filter_complex'));
      expect(out.join(' '), contains('-map [v] -map [a]'));
      expect(_after(out, '-c:v'), 'h264_mediacodec');
      expect(_after(out, '-b:v'), '2500000');
      expect(_after(out, '-g'), '60');
      expect(_after(out, '-r'), '30');
      expect(_after(out, '-c:a'), 'aac');
      expect(_after(out, '-b:a'), '128000');
      expect(_after(out, '-ar'), '44100');
      expect(_after(out, '-ac'), '2');
      expect(_after(out, '-t'), '30.000');
      expect(_after(out, '-movflags'), '+faststart');
      expect(_after(out, '-map_metadata'), '-1');
      expect(_after(out, '-f'), 'mp4');
      expect(args.last, '/out/moment.mp4');
    });

    test('a photo with music lasts as long as the chosen segment', () {
      final cmd = _build(const Composition(
        layer: MediaLayer(source: _photo),
        audio: _song,
      ));
      expect(cmd.duration, const Duration(milliseconds: 7500));
      expect(cmd.hasSound, isTrue);
      expect(_inputOptions(cmd.arguments, '/in/song.mp3'),
          ['-ss', '2.000', '-t', '7.500']);
      expect(
        cmd.filterGraph,
        contains('[1:a:0]aformat=sample_rates=44100:channel_layouts=stereo,'
            'volume=0.800,afade=t=in:st=0:d=1.000,'
            'afade=t=out:st=5.500:d=2.000,apad=whole_dur=7.500[a]'),
      );
    });

    test('music on a video is mixed with its sound, each at its volume', () {
      final cmd = _build(const Composition(
        layer: MediaLayer(source: _landscapeVideo, volume: 0.4),
        audio: AudioTrack(
          path: '/in/song.mp3',
          trim: TrimRange(Duration.zero, Duration(seconds: 12)),
          volume: 0.9,
        ),
      ));
      // The video sets the length; the longer song is cut to it.
      expect(cmd.duration, const Duration(seconds: 8));
      expect(_inputOptions(cmd.arguments, '/in/song.mp3'), ['-t', '8.000']);
      const format = 'aformat=sample_rates=44100:channel_layouts=stereo';
      expect(
        cmd.filterGraph,
        contains('[0:a:0]$format,volume=0.400,apad=whole_dur=8.000[s0];'
            '[1:a:0]$format,volume=0.900,apad=whole_dur=8.000[s1];'
            '[s0][s1]amix=inputs=2:duration=longest:normalize=0,'
            'alimiter=limit=0.95:level=0[a]'),
      );
      expect(cmd.hasSound, isTrue);
    });

    test('a muted song is left out; a muted video sound too', () {
      final songMuted = _build(Composition(
        layer: const MediaLayer(source: _landscapeVideo),
        audio: _song.copyWith(volume: 0),
      ));
      expect(songMuted.arguments, isNot(contains('/in/song.mp3')));
      expect(songMuted.filterGraph, isNot(contains('amix')));
      expect(songMuted.filterGraph, contains('[0:a:0]'));

      final videoMuted = _build(const Composition(
        layer: MediaLayer(source: _landscapeVideo, volume: 0),
        audio: _song,
      ));
      expect(videoMuted.filterGraph, isNot(contains('[0:a:0]')));
      expect(videoMuted.filterGraph, isNot(contains('amix')));
      // The song is input 1 all the same, and ends in a fade within the 7.5s
      // of it used.
      expect(
          videoMuted.filterGraph,
          contains('[1:a:0]aformat=sample_rates=44100:channel_layouts=stereo,'
              'volume=0.800,afade=t=in:st=0:d=1.000,'
              'afade=t=out:st=5.500:d=2.000,apad=whole_dur=8.000[a]'));
    });

    test('a trimmed video keeps its own sound and goes to 30fps first', () {
      final cmd = _build(const Composition(
        layer: MediaLayer(
          source: _landscapeVideo,
          trim: TrimRange(Duration(seconds: 1), Duration(seconds: 5)),
        ),
      ));
      expect(cmd.duration, const Duration(seconds: 4));
      expect(_inputOptions(cmd.arguments, '/in/clip.mp4'),
          ['-ss', '1.000', '-t', '4.000']);
      expect(cmd.filterGraph, startsWith('[0:v:0]fps=30,split=2'));
      expect(
          cmd.filterGraph,
          contains('[0:a:0]aformat=sample_rates=44100:channel_layouts=stereo,'
              'apad=whole_dur=4.000[a]'));
      // Videos are already at the output rate at the overlay.
      expect(cmd.filterGraph, contains('shortest=1,format=nv12[v]'));
    });

    test('a muted video gets the silent track', () {
      final cmd = _build(const Composition(
        layer: MediaLayer(source: _landscapeVideo, volume: 0),
      ));
      expect(cmd.hasSound, isFalse);
      expect(cmd.filterGraph, contains('anullsrc='));
      expect(cmd.filterGraph, isNot(contains('[0:a:0]')));
    });

    test('a video longer than the profile allows is cut at the cap', () {
      const long = MediaSource(
        path: '/in/long.mp4',
        kind: MediaKind.video,
        width: 1080,
        height: 1920,
        duration: Duration(minutes: 3),
      );
      final cmd = _build(const Composition(layer: MediaLayer(source: long)));
      expect(cmd.duration, const Duration(minutes: 2));
      expect(_inputOptions(cmd.arguments, '/in/long.mp4'), ['-t', '120.000']);
      final out =
          cmd.arguments.sublist(cmd.arguments.indexOf('-filter_complex'));
      expect(_after(out, '-t'), '120.000');
    });

    test('quarter turns are pixel moves, other angles rotate with alpha', () {
      String rotated(double deg) => _build(Composition(
            layer: MediaLayer(
              source: _landscapeVideo,
              transform: LayerTransform(rotationDeg: deg),
            ),
          )).filterGraph;

      expect(rotated(90), contains('setsar=1,transpose=clock[fg]'));
      expect(rotated(-90), contains('setsar=1,transpose=cclock[fg]'));
      expect(rotated(270), contains('setsar=1,transpose=cclock[fg]'));
      expect(rotated(180), contains('setsar=1,hflip,vflip[fg]'));
      expect(rotated(360), contains('setsar=1[fg]'));
      expect(
        rotated(30),
        contains('format=rgba,rotate=a=0.523599:ow=rotw(0.523599)'
            ':oh=roth(0.523599):c=black@0[fg]'),
      );
    });

    test('a zoom crops before scaling; a contained layer does not', () {
      final zoomed = _build(const Composition(
        layer: MediaLayer(
          source: _landscapeVideo,
          transform: LayerTransform(scale: 1.5),
        ),
      )).filterGraph;
      expect(
        zoomed,
        contains('[fgsrc]crop=w=iw*854/1280:h=ih*720/720:x=iw*213/1280'
            ':y=ih*0/720:exact=1,scale=720:608:flags=lanczos,setsar=1[fg]'),
      );
      final contained =
          _build(const Composition(layer: MediaLayer(source: _landscapeVideo)))
              .filterGraph;
      expect(contained, isNot(contains('crop=w=')));
    });

    test('a colour background is a colour source the length of the output', () {
      final cmd = _build(const Composition(
        background: CompositionBackground.color(0xFF203040),
        layer: MediaLayer(source: _photo),
        stillDuration: Duration(seconds: 5),
      ));
      expect(cmd.filterGraph,
          startsWith('color=c=0x203040:s=720x1280:r=30:d=5.000,setsar=1[bg];'));
      expect(cmd.filterGraph, isNot(contains('gblur')));
      expect(cmd.filterGraph, contains('[0:v:0]loop=loop=-1'));
    });

    test('media off the canvas leaves only the background', () {
      final cmd = _build(const Composition(
        layer: MediaLayer(source: _photo, transform: LayerTransform(cx: 3)),
      ));
      expect(cmd.filterGraph, isNot(contains('overlay')));
      expect(cmd.filterGraph, isNot(contains('split')));
      expect(cmd.filterGraph, contains('[bg]fps=30,format=nv12[v]'));
    });

    test('encoder profile, options and frame format follow the encoder', () {
      List<String> encoderArgs(H264Encoder encoder) {
        final args = _build(
          const Composition(layer: MediaLayer(source: _photo)),
          encoder: encoder,
        ).arguments;
        final at = args.indexOf('-c:v');
        return args.sublist(at, args.indexOf('-b:v'));
      }

      expect(encoderArgs(H264Encoder.mediaCodec),
          ['-c:v', 'h264_mediacodec', '-profile:v', 'high']);
      expect(encoderArgs(H264Encoder.mediaCodecDefault),
          ['-c:v', 'h264_mediacodec']);
      expect(encoderArgs(H264Encoder.videoToolbox), [
        '-c:v',
        'h264_videotoolbox',
        '-profile:v',
        'high',
        '-allow_sw',
        '1',
      ]);
      expect(encoderArgs(H264Encoder.videoToolboxDefault),
          ['-c:v', 'h264_videotoolbox', '-allow_sw', '1']);

      final planar = _build(
        const Composition(layer: MediaLayer(source: _photo)),
        encoder: H264Encoder.mediaCodecPlanar,
      );
      expect(planar.filterGraph, contains('format=yuv420p[v]'));
      expect(_after(planar.arguments, '-profile:v'), 'high');
    });

    test('Moments render at 1080x1920, 12Mbps', () {
      const moment = EncodingProfile.moment;
      expect((moment.width, moment.height), (1080, 1920));
      expect(moment.videoBitrate, 12000000);
      // The server takes a longest edge of up to 1920.
      expect(moment.height, lessThanOrEqualTo(1920));
      final cmd = _build(
        const Composition(layer: MediaLayer(source: _photo)),
        profile: moment,
      );
      // The blur scales with the canvas: 34px at 720 wide is 51 at 1080,
      // run at a quarter size.
      expect(
          cmd.filterGraph,
          contains('scale=270:480:force_original_aspect_ratio=increase,'
              'crop=270:480,gblur=sigma=12.75,scale=1080:1920,lutyuv='));
      expect(cmd.filterGraph,
          contains('[fgsrc]scale=1080:810:flags=lanczos,setsar=1[fg]'));
      expect(_after(cmd.arguments, '-b:v'), '12000000');
    });

    test('a long Moment gets the bitrate that keeps it under the upload cap',
        () {
      const moment = EncodingProfile.moment;
      // The app's one upload cap (100MB without a build define).
      const cap = 100 * 1024 * 1024;
      expect(kMaxUploadBytes, cap);
      expect(moment.maxBytes, kMaxUploadBytes);
      // Short: the full rate.
      expect(moment.videoBitrateFor(const Duration(seconds: 30)), 12000000);
      // 2 minutes: 85% of the cap over 120s, less the audio.
      final long = moment.videoBitrateFor(const Duration(minutes: 2));
      expect(long, 5813930);
      final bytes = (long + moment.audioBitrate) * 120 / 8;
      expect(bytes, lessThan(cap * 0.86));
      // No cap: the profile's rate whatever the length.
      expect(_p720.videoBitrateFor(const Duration(minutes: 2)), 2500000);

      const twoMinutes = MediaSource(
        path: '/in/long.mp4',
        kind: MediaKind.video,
        width: 1080,
        height: 1920,
        duration: Duration(minutes: 2),
      );
      final cmd = _build(
        const Composition(layer: MediaLayer(source: twoMinutes)),
        profile: moment,
      );
      expect(_after(cmd.arguments, '-b:v'), '5813930');
    });

    test("QP ceilings: a video's, a still's, and none when asked", () {
      const moment = EncodingProfile.moment;
      RenderCommand build(
        MediaSource source, {
        H264Encoder encoder = H264Encoder.mediaCodec,
        bool qpCeilings = true,
      }) =>
          buildRenderCommand(
            composition: Composition(layer: MediaLayer(source: source)),
            profile: moment,
            encoder: encoder,
            outputPath: '/out/moment.mp4',
            qpCeilings: qpCeilings,
          );

      final video = build(_landscapeVideo);
      expect(video.usesQpCeilings, isTrue);
      expect(_after(video.arguments, '-qp_i_max'), '27');
      expect(_after(video.arguments, '-qp_p_max'), '30');
      expect(_after(video.arguments, '-g'), '60');

      // A photo: near-lossless keyframes, 10s apart.
      final still = build(_photo);
      expect(_after(still.arguments, '-qp_i_max'), '20');
      expect(_after(still.arguments, '-qp_p_max'), '24');
      expect(_after(still.arguments, '-g'), '300');

      final plain = build(_landscapeVideo, qpCeilings: false);
      expect(plain.usesQpCeilings, isFalse);
      expect(plain.arguments, isNot(contains('-qp_i_max')));
      expect(plain.arguments, isNot(contains('-qp_p_max')));
      expect(_after(plain.arguments, '-b:v'), '12000000');

      // VideoToolbox has no such option.
      final apple = build(_landscapeVideo, encoder: H264Encoder.videoToolbox);
      expect(apple.usesQpCeilings, isFalse);
      expect(apple.arguments, isNot(contains('-qp_i_max')));

      // Every Android candidate takes them.
      for (final encoder in H264Encoder.candidatesFor(TargetPlatform.android)) {
        expect(encoder.takesQpCeilings, isTrue, reason: encoder.pixelFormat);
      }
    });

    test('the profile sets size, rate and bitrates', () {
      final cmd = _build(
        const Composition(layer: MediaLayer(source: _photo)),
        profile: _p720.copyWith(
          fps: 24,
          videoBitrate: 4000000,
          audioChannels: 1,
        ),
      );
      expect(cmd.filterGraph, contains('gblur=sigma=8.50,scale=720:1280,'));
      expect(cmd.filterGraph, contains('fps=24,format=nv12[v]'));
      expect(cmd.filterGraph, contains('cl=mono'));
      expect(_after(cmd.arguments, '-b:v'), '4000000');
      expect(_after(cmd.arguments, '-ac'), '1');
    });

    test('an edit that cannot be rendered is refused', () {
      expect(
        () => _build(const Composition(
          layer: MediaLayer(
            source: _landscapeVideo,
            trim: TrimRange(Duration(seconds: 3), Duration(seconds: 3)),
          ),
        )),
        throwsArgumentError,
      );
      expect(
        () => _build(const Composition(
          layer: MediaLayer(
            source: MediaSource(
                path: '/in/x.jpg', kind: MediaKind.image, width: 0, height: 0),
          ),
        )),
        throwsArgumentError,
      );
    });

    test('encoders are tried hardware-first per platform', () {
      expect(H264Encoder.candidatesFor(TargetPlatform.iOS),
          [H264Encoder.videoToolbox, H264Encoder.videoToolboxDefault]);
      expect(H264Encoder.candidatesFor(TargetPlatform.android), [
        H264Encoder.mediaCodec,
        H264Encoder.mediaCodecPlanar,
        H264Encoder.mediaCodecDefault,
      ]);
    });
  });

  test('the poster is the first frame as one JPEG', () {
    final args = buildPosterCommand(
      videoPath: '/out/moment.mp4',
      posterPath: '/out/poster.jpg',
      profile: EncodingProfile.moment,
    );
    expect(_after(args, '-i'), '/out/moment.mp4');
    expect(_after(args, '-frames:v'), '1');
    expect(_after(args, '-q:v'), '3');
    expect(_after(args, '-update'), '1');
    expect(args, contains('-an'));
    expect(args.last, '/out/poster.jpg');
  });
}
