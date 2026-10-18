import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/encoding_profile.dart';
import 'package:chatterloop_app/core/media/ffmpeg_command.dart';
import 'package:chatterloop_app/core/media/media_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const photo = MediaSource(
  path: '/in/photo.jpg',
  kind: MediaKind.image,
  width: 1600,
  height: 1200,
);

String after(List<String> args, String flag) => args[args.indexOf(flag) + 1];

void main() {
  test('queued still exposes its stage and cancellation produces no output',
      () async {
    final job = MediaEngine.instance.renderStill(
      const Composition(clips: [MediaLayer(source: photo)]),
      watermark: false,
    );
    expect(job.status.value, 'Queued');
    await job.cancel();
    expect(job.status.value, 'Cancelled');
    expect(job.progress.value, 0);
    await expectLater(job.result, throwsA(isA<RenderCancelled>()));
  });

  test('local export keeps a three minute edit at full quality', () {
    const duration = Duration(minutes: 3, milliseconds: 125);
    final command = buildRenderCommand(
      composition: const Composition(clips: [
        MediaLayer(source: photo, duration: duration),
      ]),
      profile: EncodingProfile.momentExportFor(duration),
      encoder: H264Encoder.mediaCodec,
      outputPath: '/out/local.mp4',
    );
    expect(command.duration, duration);
    expect(after(command.arguments, '-t'), '180.125');
    expect(after(command.arguments, '-b:v'), '12000000');
    expect(command.filterGraph, contains('scale=1080:810'));
    expect(EncodingProfile.momentExportFor(duration).maxBytes, isNull);
    expect(EncodingProfile.moment.maxDuration, const Duration(minutes: 2));
    expect(EncodingProfile.moment.maxBytes, isNotNull);
  });

  test('direct still shares rotated geometry, colour background and watermark',
      () {
    const composition = Composition(
      background: CompositionBackground.color(0xFF203040),
      clips: [
        MediaLayer(
            source: photo,
            transform: LayerTransform(
              cx: 0.4,
              cy: 0.6,
              scale: 1.7,
              rotationDeg: 15,
            ))
      ],
    );
    final command = buildStillCommand(
      composition: composition,
      profile: EncodingProfile.moment,
      outputPath: '/out/still.jpg',
      watermarkPath: '/in/logo.png',
      watermarkLogoWidth: 630,
    );
    final video = buildRenderCommand(
      composition: composition,
      profile: EncodingProfile.moment,
      encoder: H264Encoder.mediaCodec,
      outputPath: '/out/video.mp4',
      watermarkPath: '/in/logo.png',
      watermarkLogoWidth: 630,
    );
    expect(command.filterGraph, startsWith('color=c=0x203040:s=1080x1920'));
    final geometry =
        RegExp(r'scale=\d+:\d+:flags=lanczos,setsar=1,rotate=[^;]+');
    expect(geometry.firstMatch(command.filterGraph)?.group(0),
        geometry.firstMatch(video.filterGraph)?.group(0));
    expect(command.filterGraph, contains('rotate='));
    expect(command.filterGraph, contains('scale=trunc(iw*0.377778/2)*2:-2'));
    expect(command.filterGraph, contains('overlay=x=54:y=H-h-130'));
    expect(after(command.arguments, '-frames:v'), '1');
    expect(command.arguments, isNot(contains('-c:v')));
    expect(command.arguments, isNot(contains('-c:a')));
    expect(command.arguments, isNot(contains('-movflags')));
    expect(command.arguments, contains('-an'));
    expect(command.arguments.last, '/out/still.jpg');
  });

  test('direct still retains blur and rejects a moving composition', () {
    final command = buildStillCommand(
      composition: const Composition(clips: [MediaLayer(source: photo)]),
      profile: EncodingProfile.moment,
      outputPath: '/out/still.jpg',
    );
    expect(command.filterGraph, contains('gblur=sigma=12.75'));
    expect(command.filterGraph, isNot(contains('anullsrc')));
    expect(
        () => buildStillCommand(
              composition: const Composition(clips: [
                MediaLayer(source: photo),
                MediaLayer(source: photo),
              ]),
              profile: EncodingProfile.moment,
              outputPath: '/out/still.jpg',
            ),
        throwsArgumentError);
  });

  test('landscape still and video use the selected output canvas', () {
    final profile = EncodingProfile.momentExportFor(const Duration(minutes: 3))
        .copyWith(width: 1920, height: 1080);
    const composition = Composition(clips: [MediaLayer(source: photo)]);
    final still = buildStillCommand(
        composition: composition,
        profile: profile,
        outputPath: '/out/landscape.jpg',
        watermarkPath: '/in/logo.png');
    final video = buildRenderCommand(
        composition: composition,
        profile: profile,
        encoder: H264Encoder.mediaCodec,
        outputPath: '/out/landscape.mp4',
        watermarkPath: '/in/logo.png');
    for (final command in [still, video]) {
      expect(command.filterGraph, contains('scale=1920:1080'));
      expect(command.filterGraph, contains('scale=1440:1080:flags=lanczos'));
      expect(command.filterGraph, contains('scale=238:-2:flags=lanczos[wm]'));
      expect(command.filterGraph, contains('overlay=x=54:y=H-h-130'));
    }
  });

  test('a silent photo ignores muted audio without starting an encode', () {
    final command = buildStillCommand(
      composition: const Composition(clips: [
        MediaLayer(source: photo)
      ], audio: [
        AudioTrack(
            path: '/in/muted.mp3',
            name: 'Muted',
            fileLength: Duration(seconds: 4),
            trim: TrimRange(Duration.zero, Duration(seconds: 4)),
            volume: 0),
      ]),
      profile: EncodingProfile.moment,
      outputPath: '/out/photo.jpg',
    );
    expect(command.arguments, isNot(contains('/in/muted.mp3')));
    expect(command.arguments, isNot(contains('-c:v')));
    expect(command.arguments, contains('-an'));
  });
}
