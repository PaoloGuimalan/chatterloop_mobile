import 'package:chatterloop_app/core/media/canvas_geometry.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/encoding_profile.dart';
import 'package:chatterloop_app/core/media/ffmpeg_command.dart';
import 'package:chatterloop_app/core/media/media_info.dart';
import 'package:chatterloop_app/core/utils/upload_limits.dart';
import 'package:flutter/services.dart';
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
  name: 'Song',
  fileLength: Duration(seconds: 30),
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

/// Where the engine would have written the watermark asset.
const _watermarkFile = '/tmp/asset-watermark.png';

const _format = 'aformat=sample_rates=44100:channel_layouts=stereo';

RenderCommand _build(
  Composition composition, {
  EncodingProfile profile = _p720,
  H264Encoder encoder = H264Encoder.mediaCodec,
  String? watermarkPath,
}) =>
    buildRenderCommand(
      composition: composition,
      profile: profile,
      encoder: encoder,
      outputPath: '/out/moment.mp4',
      watermarkPath: watermarkPath,
    );

/// The value following [flag] - the first occurrence after [from].
String _after(List<String> args, String flag, {int from = 0}) =>
    args[args.indexOf(flag, from) + 1];

/// Every input file, in input order.
List<String> _inputs(List<String> args) => [
      for (var i = 0; i < args.length - 1; i++)
        if (args[i] == '-i') args[i + 1]
    ];

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
        clips: [
          MediaLayer(
            source: _landscapeVideo,
            transform:
                LayerTransform(cx: 0.4, cy: 0.6, scale: 1.7, rotationDeg: 15),
            trim: TrimRange(Duration(seconds: 1), Duration(seconds: 5)),
            volume: 0.35,
          ),
          MediaLayer(source: _photo, duration: Duration(seconds: 3)),
        ],
        audio: [_song],
      );
      final back = Composition.fromJson(edit.toJson());

      expect(back.toJson(), edit.toJson());
      expect(back.version, 2);
      expect(back.background.argb, 0xFF203040);
      expect(back.clips, hasLength(2));
      expect(back.clips[0].transform.rotationDeg, 15);
      expect(back.clips[0].trim!.length, const Duration(seconds: 4));
      expect(back.clips[0].volume, 0.35);
      expect(back.clips[1].length, const Duration(seconds: 3));
      final track = back.audio.single;
      expect(track.name, 'Song');
      expect(track.fileLength, const Duration(seconds: 30));
      expect(track.start, Duration.zero);
      expect(track.fadeOut, const Duration(seconds: 2));
    });

    test('reads a version 1 edit: one layer, one song, the photo length', () {
      final back = Composition.fromJson({
        'v': 1,
        'background': {'type': 'blur'},
        'layers': [
          {
            'type': 'media',
            'source': _photo.toJson(),
            'transform': {'cx': 0.5, 'cy': 0.5, 'scale': 1, 'rotation': 0},
            'keep_audio': false,
          }
        ],
        'audio': {
          'path': '/in/song.mp3',
          'trim': {'start_ms': 0, 'end_ms': 12000},
          'volume': 1,
        },
        'still_ms': 12000,
      });
      expect(back.clips.single.length, const Duration(seconds: 12));
      expect(back.audio.single.start, Duration.zero);
      expect(back.audio.single.length, const Duration(seconds: 12));
    });

    test('its length is its clips end to end; a photo shows 6s', () {
      const edit = Composition(clips: [
        MediaLayer(source: _photo),
        MediaLayer(
          source: _landscapeVideo,
          trim: TrimRange(Duration(seconds: 1), Duration(seconds: 5)),
        ),
        MediaLayer(source: _photo, duration: Duration(milliseconds: 2500)),
      ], audio: [
        _song
      ]);
      expect(MediaLayer.defaultStill, const Duration(seconds: 6));
      // The music doesn't make it longer.
      expect(edit.naturalDuration, const Duration(milliseconds: 12500));
      expect(edit.clipStarts, const [
        Duration.zero,
        Duration(seconds: 6),
        Duration(seconds: 10),
      ]);
      // A whole video, untrimmed.
      expect(const MediaLayer(source: _landscapeVideo).length,
          const Duration(seconds: 8));
    });

    test('finds the clip under a time, and how far into it', () {
      const edit = Composition(clips: [
        MediaLayer(source: _photo),
        MediaLayer(source: _photo, duration: Duration(seconds: 4)),
      ]);
      expect(edit.locate(Duration.zero), (index: 0, offset: Duration.zero));
      expect(edit.locate(const Duration(seconds: 5)),
          (index: 0, offset: const Duration(seconds: 5)));
      // A boundary belongs to the clip starting there.
      expect(edit.locate(const Duration(seconds: 6)),
          (index: 1, offset: Duration.zero));
      // Past the end: the last clip's end.
      expect(edit.locate(const Duration(seconds: 30)),
          (index: 1, offset: const Duration(seconds: 4)));
    });

    test('has sound only when something audible is left', () {
      const photo = MediaLayer(source: _photo);
      expect(const Composition(clips: [photo]).hasSound, isFalse);
      expect(const Composition(clips: [photo], audio: [_song]).hasSound,
          isTrue);
      expect(
          Composition(clips: const [photo], audio: [_song.copyWith(volume: 0)])
              .hasSound,
          isFalse);
      // A song that starts after the last clip ends is never heard.
      expect(
          Composition(
              clips: const [photo],
              audio: [_song.copyWith(start: const Duration(seconds: 7))])
              .hasSound,
          isFalse);
      expect(
          const Composition(clips: [MediaLayer(source: _landscapeVideo)])
              .hasSound,
          isTrue);
      expect(
          const Composition(
                  clips: [MediaLayer(source: _landscapeVideo, volume: 0)])
              .hasSound,
          isFalse);
    });

    test('all stills: photos only', () {
      expect(
          const Composition(clips: [
            MediaLayer(source: _photo),
            MediaLayer(source: _photo)
          ]).allStills,
          isTrue);
      expect(
          const Composition(clips: [
            MediaLayer(source: _photo),
            MediaLayer(source: _landscapeVideo)
          ]).allStills,
          isFalse);
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
        'trim',
        'tpad',
        'concat',
        'anullsrc',
        'anull',
        'atrim',
        'asetpts',
        'aformat',
        'volume',
        'afade',
        'adelay',
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
        const Composition(clips: [MediaLayer(source: _photo)]),
        Composition(
          background: const CompositionBackground.color(0xFF102030),
          clips: const [
            MediaLayer(
              source: _photo,
              transform: LayerTransform(scale: 2.5, rotationDeg: 30),
            ),
            MediaLayer(source: _landscapeVideo, volume: 0.5),
          ],
          audio: [_song, _song.copyWith(start: const Duration(seconds: 10))],
        ),
        for (final turn in [90.0, 180.0, 270.0])
          Composition(
            clips: [
              MediaLayer(
                source: _landscapeVideo,
                transform: LayerTransform(scale: 1.4, rotationDeg: turn),
              ),
            ],
          ),
        const Composition(
          clips: [
            MediaLayer(source: _photo, transform: LayerTransform(cx: 3))
          ],
        ),
      ];
      for (final edit in edits) {
        for (final watermark in [null, _watermarkFile]) {
          final used = filtersOf(_build(edit,
                  profile: EncodingProfile.moment, watermarkPath: watermark)
              .filterGraph);
          expect(used.difference(bundled), isEmpty, reason: '$used');
        }
      }
    });

    test('a photo alone: 6s of it, with a silent track', () {
      final cmd =
          _build(const Composition(clips: [MediaLayer(source: _photo)]));
      final args = cmd.arguments;

      expect(cmd.duration, const Duration(seconds: 6));
      expect(cmd.hasSound, isFalse);
      // Any image demuxer works: no image2-only `-loop`.
      expect(args, isNot(contains('-loop')));
      expect(_inputs(args), ['/in/photo.jpg']);
      expect(
          cmd.filterGraph,
          contains('[0:v:0]loop=loop=-1:size=1:start=0,setpts=N/(1*TB),'
              'split=2[bgsrc0][fgsrc0]'));
      expect(cmd.filterGraph,
          contains('[fgsrc0]scale=720:540:flags=lanczos,setsar=1[fg0]'));
      // Composed once a second, then up to the frame rate, cut to length.
      expect(
          cmd.filterGraph,
          contains('[bg0][fg0]overlay=x=360.00-w/2:y=640.00-h/2:shortest=1,'
              'fps=30,trim=duration=6.000,setpts=PTS-STARTPTS,'
              'format=yuv420p,setsar=1[v0]'));
      expect(cmd.filterGraph,
          contains('anullsrc=r=44100:cl=stereo,atrim=duration=6.000[a0]'));
      // One clip: nothing to join.
      expect(cmd.filterGraph, isNot(contains('concat')));
      expect(cmd.filterGraph, contains('[v0]format=nv12[v]'));
      expect(cmd.filterGraph, contains('[a0]anull[a]'));
      expect(_after(args, '-filter_complex'), cmd.filterGraph);
    });

    test('output settings match the profile and the server contract', () {
      final args =
          _build(const Composition(clips: [MediaLayer(source: _photo)]))
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
      expect(_after(out, '-t'), '6.000');
      expect(_after(out, '-movflags'), '+faststart');
      expect(_after(out, '-map_metadata'), '-1');
      expect(_after(out, '-f'), 'mp4');
      expect(args.last, '/out/moment.mp4');
    });

    test('clips are joined end to end, each exactly its length', () {
      final cmd = _build(const Composition(clips: [
        MediaLayer(source: _photo),
        MediaLayer(
          source: _landscapeVideo,
          trim: TrimRange(Duration(seconds: 1), Duration(seconds: 5)),
        ),
        MediaLayer(source: _photo, duration: Duration(milliseconds: 2500)),
      ]));
      expect(cmd.duration, const Duration(milliseconds: 12500));
      expect(_inputs(cmd.arguments),
          ['/in/photo.jpg', '/in/clip.mp4', '/in/photo.jpg']);
      expect(_inputOptions(cmd.arguments, '/in/clip.mp4'),
          ['-ss', '1.000', '-t', '4.000']);
      // The video: to 30fps first, held on its last frame should the file
      // run short, then cut to its 4s.
      expect(
          cmd.filterGraph,
          contains('[1:v:0]fps=30,tpad=stop_mode=clone:stop_duration=1,'
              'split=2[bgsrc1][fgsrc1]'));
      expect(cmd.filterGraph, contains('trim=duration=4.000,'));
      expect(cmd.filterGraph, contains('trim=duration=2.500,'));
      // Its sound, held to the same 4s; silence for the photos.
      expect(
          cmd.filterGraph,
          contains('[1:a:0]$_format,apad=whole_dur=4.000,'
              'atrim=duration=4.000,asetpts=PTS-STARTPTS[a1]'));
      expect(cmd.filterGraph,
          contains('anullsrc=r=44100:cl=stereo,atrim=duration=2.500[a2]'));
      expect(
          cmd.filterGraph,
          contains('[v0][a0][v1][a1][v2][a2]concat=n=3:v=1:a=1[vcat][acat]'));
      expect(cmd.filterGraph, contains('[vcat]format=nv12[v]'));
      expect(cmd.filterGraph, contains('[acat]anull[a]'));
      expect(cmd.hasSound, isTrue);
    });

    test('music is laid over from its place in the edit', () {
      final cmd = _build(Composition(
        clips: const [
          MediaLayer(source: _photo),
          MediaLayer(source: _photo, duration: Duration(milliseconds: 6500)),
        ],
        audio: [_song.copyWith(start: const Duration(seconds: 3))],
      ));
      expect(cmd.duration, const Duration(milliseconds: 12500));
      expect(cmd.hasSound, isTrue);
      // Input 2, after the clips: its part of the file.
      expect(_inputs(cmd.arguments)[2], '/in/song.mp3');
      expect(_inputOptions(cmd.arguments, '/in/song.mp3'),
          ['-ss', '2.000', '-t', '7.500']);
      expect(
        cmd.filterGraph,
        contains('[2:a:0]$_format,volume=0.800,afade=t=in:st=0:d=1.000,'
            'afade=t=out:st=5.500:d=2.000,adelay=delays=3000:all=1,'
            'apad=whole_dur=12.500[t0]'),
      );
      expect(
          cmd.filterGraph,
          contains('[acat][t0]amix=inputs=2:duration=first:normalize=0,'
              'alimiter=limit=0.95:level=0[a]'));
    });

    test('music running past the end is cut there, fading within', () {
      final cmd = _build(Composition(
        clips: const [MediaLayer(source: _photo)],
        audio: [_song.copyWith(start: const Duration(seconds: 3))],
      ));
      // 3s of the 7.5s part is heard.
      expect(_inputOptions(cmd.arguments, '/in/song.mp3'),
          ['-ss', '2.000', '-t', '3.000']);
      expect(cmd.filterGraph,
          contains('afade=t=in:st=0:d=1.000,afade=t=out:st=1.000:d=2.000,'));
    });

    test('a muted song, or one after the end, is not read at all', () {
      for (final track in [
        _song.copyWith(volume: 0),
        // Starts after the 8s video is over.
        _song.copyWith(start: const Duration(seconds: 9)),
      ]) {
        final cmd = _build(Composition(
          clips: const [MediaLayer(source: _landscapeVideo)],
          audio: [track],
        ));
        expect(cmd.arguments, isNot(contains('/in/song.mp3')));
        expect(cmd.filterGraph, isNot(contains('amix')));
        expect(cmd.filterGraph, contains('[0:a:0]'));
      }
    });

    test('two songs, each from its place', () {
      final cmd = _build(Composition(
        clips: const [MediaLayer(source: _landscapeVideo)],
        audio: [
          _song.copyWith(
              trim: const TrimRange(Duration.zero, Duration(seconds: 3))),
          _song.copyWith(
              start: const Duration(seconds: 5),
              trim: const TrimRange(Duration.zero, Duration(seconds: 3))),
        ],
      ));
      expect(_inputs(cmd.arguments),
          ['/in/clip.mp4', '/in/song.mp3', '/in/song.mp3']);
      expect(cmd.filterGraph, contains('[1:a:0]'));
      expect(cmd.filterGraph, contains('adelay=delays=5000:all=1'));
      expect(cmd.filterGraph, contains('[a0][t0][t1]amix=inputs=3:'));
    });

    test('a muted video gets silence', () {
      final cmd = _build(const Composition(
        clips: [MediaLayer(source: _landscapeVideo, volume: 0)],
      ));
      expect(cmd.hasSound, isFalse);
      expect(cmd.filterGraph, contains('anullsrc='));
      expect(cmd.filterGraph, isNot(contains('[0:a:0]')));
    });

    test('an edit longer than the profile allows is cut at the cap', () {
      const long = MediaSource(
        path: '/in/long.mp4',
        kind: MediaKind.video,
        width: 1080,
        height: 1920,
        duration: Duration(minutes: 3),
      );
      final cmd = _build(const Composition(clips: [
        MediaLayer(source: long),
        MediaLayer(source: _photo),
      ]));
      expect(cmd.duration, const Duration(minutes: 2));
      // The photo after it doesn't make it in at all.
      expect(_inputs(cmd.arguments), ['/in/long.mp4']);
      expect(_inputOptions(cmd.arguments, '/in/long.mp4'), ['-t', '120.000']);
      final out =
          cmd.arguments.sublist(cmd.arguments.indexOf('-filter_complex'));
      expect(_after(out, '-t'), '120.000');
    });

    test('quarter turns are pixel moves, other angles rotate with alpha', () {
      String rotated(double deg) => _build(Composition(
            clips: [
              MediaLayer(
                source: _landscapeVideo,
                transform: LayerTransform(rotationDeg: deg),
              ),
            ],
          )).filterGraph;

      expect(rotated(90), contains('setsar=1,transpose=clock[fg0]'));
      expect(rotated(-90), contains('setsar=1,transpose=cclock[fg0]'));
      expect(rotated(270), contains('setsar=1,transpose=cclock[fg0]'));
      expect(rotated(180), contains('setsar=1,hflip,vflip[fg0]'));
      expect(rotated(360), contains('setsar=1[fg0]'));
      expect(
        rotated(30),
        contains('format=rgba,rotate=a=0.523599:ow=rotw(0.523599)'
            ':oh=roth(0.523599):c=black@0[fg0]'),
      );
    });

    test('each clip is framed its own way', () {
      final graph = _build(const Composition(clips: [
        MediaLayer(
          source: _landscapeVideo,
          transform: LayerTransform(scale: 1.5),
        ),
        MediaLayer(source: _landscapeVideo),
      ])).filterGraph;
      // The zoomed one is cropped before scaling; the contained one isn't.
      expect(
        graph,
        contains('[fgsrc0]crop=w=iw*854/1280:h=ih*720/720:x=iw*213/1280'
            ':y=ih*0/720:exact=1,scale=720:608:flags=lanczos,setsar=1[fg0]'),
      );
      expect(graph,
          contains('[fgsrc1]scale=720:406:flags=lanczos,setsar=1[fg1]'));
    });

    test('a colour background is a colour source the length of each clip', () {
      final cmd = _build(const Composition(
        background: CompositionBackground.color(0xFF203040),
        clips: [
          MediaLayer(source: _photo, duration: Duration(seconds: 5)),
          MediaLayer(source: _photo, duration: Duration(seconds: 2)),
        ],
      ));
      expect(cmd.filterGraph,
          startsWith('color=c=0x203040:s=720x1280:r=30:d=5.000,setsar=1[bg0];'));
      expect(cmd.filterGraph,
          contains('color=c=0x203040:s=720x1280:r=30:d=2.000,setsar=1[bg1];'));
      expect(cmd.filterGraph, isNot(contains('gblur')));
      expect(cmd.filterGraph, contains('[0:v:0]loop=loop=-1'));
    });

    test('media off the canvas leaves only the background', () {
      final cmd = _build(const Composition(
        clips: [MediaLayer(source: _photo, transform: LayerTransform(cx: 3))],
      ));
      expect(cmd.filterGraph, isNot(contains('overlay')));
      expect(cmd.filterGraph, isNot(contains('split')));
      expect(cmd.filterGraph, contains('[bg0]fps=30,trim=duration=6.000,'));
    });

    test('encoder profile, options and frame format follow the encoder', () {
      List<String> encoderArgs(H264Encoder encoder) {
        final args = _build(
          const Composition(clips: [MediaLayer(source: _photo)]),
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
        const Composition(clips: [MediaLayer(source: _photo)]),
        encoder: H264Encoder.mediaCodecPlanar,
      );
      expect(planar.filterGraph, contains('[v0]format=yuv420p[v]'));
      expect(_after(planar.arguments, '-profile:v'), 'high');
    });

    test('Moments render at 1080x1920, 12Mbps', () {
      const moment = EncodingProfile.moment;
      expect((moment.width, moment.height), (1080, 1920));
      expect(moment.videoBitrate, 12000000);
      // The server takes a longest edge of up to 1920.
      expect(moment.height, lessThanOrEqualTo(1920));
      final cmd = _build(
        const Composition(clips: [MediaLayer(source: _photo)]),
        profile: moment,
      );
      // The blur scales with the canvas: 34px at 720 wide is 51 at 1080,
      // run at a quarter size.
      expect(
          cmd.filterGraph,
          contains('scale=270:480:force_original_aspect_ratio=increase,'
              'crop=270:480,gblur=sigma=12.75,scale=1080:1920,lutyuv='));
      expect(cmd.filterGraph,
          contains('[fgsrc0]scale=1080:810:flags=lanczos,setsar=1[fg0]'));
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
        const Composition(clips: [MediaLayer(source: twoMinutes)]),
        profile: moment,
      );
      expect(_after(cmd.arguments, '-b:v'), '5813930');
    });

    test("QP ceilings: a video's, a still's, and none when asked", () {
      const moment = EncodingProfile.moment;
      RenderCommand build(
        List<MediaLayer> clips, {
        H264Encoder encoder = H264Encoder.mediaCodec,
        bool qpCeilings = true,
      }) =>
          buildRenderCommand(
            composition: Composition(clips: clips),
            profile: moment,
            encoder: encoder,
            outputPath: '/out/moment.mp4',
            qpCeilings: qpCeilings,
          );
      const video = MediaLayer(source: _landscapeVideo);
      const photo = MediaLayer(source: _photo);

      final moving = build([video]);
      expect(moving.usesQpCeilings, isTrue);
      expect(_after(moving.arguments, '-qp_i_max'), '27');
      expect(_after(moving.arguments, '-qp_p_max'), '30');
      expect(_after(moving.arguments, '-g'), '60');

      // Photos only: near-lossless keyframes, 10s apart.
      final still = build([photo, photo]);
      expect(_after(still.arguments, '-qp_i_max'), '20');
      expect(_after(still.arguments, '-qp_p_max'), '24');
      expect(_after(still.arguments, '-g'), '300');

      // A photo among videos moves: the video settings.
      final mixed = build([photo, video]);
      expect(_after(mixed.arguments, '-qp_i_max'), '27');
      expect(_after(mixed.arguments, '-g'), '60');

      final plain = build([video], qpCeilings: false);
      expect(plain.usesQpCeilings, isFalse);
      expect(plain.arguments, isNot(contains('-qp_i_max')));
      expect(plain.arguments, isNot(contains('-qp_p_max')));
      expect(_after(plain.arguments, '-b:v'), '12000000');

      // VideoToolbox has no such option.
      final apple = build([video], encoder: H264Encoder.videoToolbox);
      expect(apple.usesQpCeilings, isFalse);
      expect(apple.arguments, isNot(contains('-qp_i_max')));

      // Every Android candidate takes them.
      for (final encoder in H264Encoder.candidatesFor(TargetPlatform.android)) {
        expect(encoder.takesQpCeilings, isTrue, reason: encoder.pixelFormat);
      }
    });

    test('the profile sets size, rate and bitrates', () {
      final cmd = _build(
        const Composition(clips: [MediaLayer(source: _photo)]),
        profile: _p720.copyWith(
          fps: 24,
          videoBitrate: 4000000,
          audioChannels: 1,
        ),
      );
      expect(cmd.filterGraph, contains('gblur=sigma=8.50,scale=720:1280,'));
      expect(cmd.filterGraph, contains('shortest=1,fps=24,'));
      expect(cmd.filterGraph, contains('cl=mono'));
      expect(_after(cmd.arguments, '-b:v'), '4000000');
      expect(_after(cmd.arguments, '-ac'), '1');
    });

    test('an edit that cannot be rendered is refused', () {
      expect(() => _build(const Composition(clips: [])), throwsArgumentError);
      expect(
        () => _build(const Composition(
          clips: [
            MediaLayer(
              source: _landscapeVideo,
              trim: TrimRange(Duration(seconds: 3), Duration(seconds: 3)),
            ),
          ],
        )),
        throwsArgumentError,
      );
      expect(
        () => _build(const Composition(
          clips: [
            MediaLayer(
              source: MediaSource(
                  path: '/in/x.jpg',
                  kind: MediaKind.image,
                  width: 0,
                  height: 0),
            ),
          ],
        )),
        throwsArgumentError,
      );
    });

    group('watermark', () {
      test('only when asked for: posting is left without it', () {
        final plain = _build(
          const Composition(clips: [MediaLayer(source: _photo)]),
          profile: EncodingProfile.moment,
        );
        expect(EncodingProfile.moment.watermark, Watermark.chatterloop);
        expect(plain.arguments, isNot(contains(_watermarkFile)));
        expect(plain.filterGraph, isNot(contains('[wm]')));
      });

      test('a saved copy: the logo at the left, a little up from the bottom', () {
        final cmd = _build(
          const Composition(clips: [
            MediaLayer(source: _photo),
            MediaLayer(source: _landscapeVideo),
          ], audio: [
            _song
          ]),
          profile: EncodingProfile.moment,
          watermarkPath: _watermarkFile,
        );
        // Last, after the clips and the song.
        expect(_inputs(cmd.arguments).last, _watermarkFile);
        // 22% of 1080 wide, its height kept to the logo's shape; 5% of it
        // (54px) in from the left, 12% (130px) up from the bottom.
        expect(cmd.filterGraph,
            contains('[3:v:0]scale=238:-2:flags=lanczos[wm]'));
        // Over the joined clips.
        expect(
            cmd.filterGraph,
            contains('[vcat][wm]overlay=x=54:y=H-h-130:eof_action=repeat,'
                'format=nv12[v]'));
      });
    });

    test('with a handle, scaled by the logo: a long name runs on, the logo '
        'keeps its size', () {
      final cmd = buildRenderCommand(
        composition: const Composition(clips: [MediaLayer(source: _photo)]),
        profile: EncodingProfile.moment,
        encoder: H264Encoder.mediaCodec,
        outputPath: '/out/moment.mp4',
        watermarkPath: _watermarkFile,
        // The logo is 630 wide in the picture; the picture may be wider.
        watermarkLogoWidth: 630,
      );
      // 238 / 630 of whatever width the picture is.
      expect(
          cmd.filterGraph,
          contains('[1:v:0]scale=trunc(iw*0.377778/2)*2:-2:flags=lanczos'
              '[wm]'));
      final stamp = buildStampCommand(
        inputPath: '/in/moment.mp4',
        watermarkPath: _watermarkFile,
        watermarkLogoWidth: 630,
        outputPath: '/out/saved.mp4',
        width: 1920,
        height: 1080,
        isImage: false,
        profile: EncodingProfile.moment,
        encoder: H264Encoder.mediaCodec,
      );
      expect(stamp.filterGraph,
          startsWith('[1:v:0]scale=trunc(iw*0.377778/2)*2:-2:'));
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

  group('buildStampCommand - a saved copy of a posted Moment', () {
    RenderCommand stamp({
      int width = 1080,
      int height = 1920,
      bool isImage = false,
    }) =>
        buildStampCommand(
          inputPath: '/in/moment.mp4',
          watermarkPath: _watermarkFile,
          outputPath: isImage ? '/out/saved.jpg' : '/out/saved.mp4',
          width: width,
          height: height,
          isImage: isImage,
          profile: EncodingProfile.moment,
          encoder: H264Encoder.mediaCodec,
          duration: const Duration(seconds: 20),
        );

    test('a video: the logo overlaid, its sound kept, re-encoded', () {
      final cmd = stamp();
      expect(_inputs(cmd.arguments), ['/in/moment.mp4', _watermarkFile]);
      expect(
          cmd.filterGraph,
          '[1:v:0]scale=238:-2:flags=lanczos[wm];'
          '[0:v:0][wm]overlay=x=54:y=H-h-130:eof_action=repeat,format=nv12[v]');
      final args = cmd.arguments.join(' ');
      expect(args, contains('-map [v] -map 0:a:0?'));
      expect(_after(cmd.arguments, '-c:v'), 'h264_mediacodec');
      expect(_after(cmd.arguments, '-b:v'), '12000000');
      expect(_after(cmd.arguments, '-qp_i_max'), '27');
      expect(_after(cmd.arguments, '-c:a'), 'aac');
      expect(_after(cmd.arguments, '-movflags'), '+faststart');
      expect(cmd.arguments.last, '/out/saved.mp4');
      expect(cmd.duration, const Duration(seconds: 20));
    });

    test('sized from the shorter side: a landscape video gets the same logo',
        () {
      expect(stamp(width: 1920, height: 1080).filterGraph,
          stamp().filterGraph);
      expect(stamp(width: 720, height: 1280).filterGraph,
          contains('scale=158:-2:flags=lanczos[wm]'));
    });

    test('a photo: one JPEG, no video encoder', () {
      final cmd = stamp(isImage: true);
      expect(cmd.filterGraph, endsWith('eof_action=repeat[v]'));
      expect(cmd.arguments, isNot(contains('-c:v')));
      expect(_after(cmd.arguments, '-frames:v'), '1');
      expect(cmd.arguments.last, '/out/saved.jpg');
    });

    test('a profile without a watermark has nothing to stamp', () {
      expect(
        () => buildStampCommand(
          inputPath: '/in/moment.mp4',
          watermarkPath: _watermarkFile,
          outputPath: '/out/saved.mp4',
          width: 1080,
          height: 1920,
          isImage: false,
          profile: _p720,
          encoder: H264Encoder.mediaCodec,
        ),
        throwsArgumentError,
      );
    });

    test('the logo ships: a PNG with transparency', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final png = await rootBundle.load(Watermark.chatterloop.asset);
      // The PNG signature, then IHDR's colour type 6: RGBA.
      expect(png.getUint32(0), 0x89504E47);
      expect(png.getUint8(25), 6);
      // Big enough for a sharp 1080-wide stamp (twice its 238px).
      expect(png.getUint32(16), greaterThanOrEqualTo(2 * 238));
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

  test("a clip's thumbnail is one small frame from where it starts", () {
    final args = buildThumbnailCommand(
      videoPath: '/in/clip.mp4',
      at: const Duration(milliseconds: 1500),
      outputPath: '/tmp/thumb.jpg',
    );
    expect(_inputOptions(args, '/in/clip.mp4'), ['-ss', '1.500']);
    expect(_after(args, '-frames:v'), '1');
    expect(_after(args, '-vf'), 'scale=240:-2');
    expect(args.last, '/tmp/thumb.jpg');
  });
}
