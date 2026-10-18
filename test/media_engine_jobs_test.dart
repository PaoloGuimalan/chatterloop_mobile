import 'dart:async';
import 'dart:io';

import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/encoding_profile.dart';
import 'package:chatterloop_app/core/media/media_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _composition = Composition(clips: [
  MediaLayer(
      source: MediaSource(
    path: '/in/photo.jpg',
    kind: MediaKind.image,
    width: 1600,
    height: 1200,
  ))
]);

/// The native encoder is external to a Flutter unit test. Keep the real
/// engine queue, files, recovery, plugin sessions, worker and cleanup;
/// substitute only native method responses and completion/statistics events.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const native = MethodChannel('flutter.arthenica.com/ffmpeg_kit');
  const events = MethodChannel('flutter.arthenica.com/ffmpeg_kit_event');
  final commands = <List<String>>[];
  final sessions = <int, Map<String, dynamic>>{};
  final codes = <int, int>{};
  var nextId = 0;
  var refuseFirst = false;
  var overrunStatistics = false;
  late Directory temp;

  Future<void> emit(Map<String, dynamic> event) async {
    await messenger.handlePlatformMessage(events.name,
        const StandardMethodCodec().encodeSuccessEnvelope(event), (_) {});
  }

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('engine-jobs-');
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => temp.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (call) async => <String, dynamic>{
        'appName': 'Chatterloop',
        'packageName': 'test.app',
        'version': '1.0',
        'buildNumber': '1',
        'buildSignature': '',
      },
    );
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(native, (call) async {
      final args = call.arguments as Map<dynamic, dynamic>?;
      final id = args?['sessionId'] as int?;
      switch (call.method) {
        case 'getPlatform':
          return 'android';
        case 'getArch':
          return 'arm64';
        case 'getPackageName':
          return 'full';
        case 'isLTSBuild':
          return false;
        case 'ffmpegSession':
          final command = (args!['arguments'] as List).cast<String>();
          commands.add(command);
          final sessionId = ++nextId;
          final session = <String, dynamic>{
            'sessionId': sessionId,
            'type': 1,
            'createTime': 1,
            'startTime': 1,
            'command': command.join(' '),
          };
          sessions[sessionId] = session;
          codes[sessionId] = refuseFirst && commands.length == 1 ? 1 : 0;
          await File(command.last).writeAsBytes([1, 2, 3]);
          return session;
        case 'asyncFFmpegSessionExecute':
          unawaited(Future<void>.delayed(Duration.zero, () async {
            await emit({
              'FFmpegKitStatisticsCallbackEvent': {
                'sessionId': id,
                'videoFrameNumber': 10,
                'videoFps': 30.0,
                'videoQuality': 1.0,
                'size': 3,
                'time': overrunStatistics
                    ? 12000
                    : commands.length == 1
                        ? 5000
                        : 1000,
                'bitrate': 1000.0,
                'speed': 1.0,
              }
            });
            await emit({
              'FFmpegKitCompleteCallbackEvent': {'sessionId': id}
            });
          }));
          return null;
        case 'getSession':
          return sessions[id];
        case 'abstractSessionGetReturnCode':
          return codes[id];
        case 'abstractSessionGetAllLogsAsString':
          return 'Error setting option qp_i_max: Option not found';
        default:
          return null;
      }
    });
  });
  tearDownAll(() async {
    await temp.delete(recursive: true);
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(events, null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'), null);
  });
  setUp(() {
    commands.clear();
    refuseFirst = false;
    overrunStatistics = false;
    SharedPreferences.setMockInitialValues({});
  });

  test('still job produces one disposable JPEG without starting video encoding',
      () async {
    final job =
        MediaEngine.instance.renderStill(_composition, watermark: false);
    final result = await job.result;
    expect(result.isImage, isTrue);
    expect(result.path, endsWith('.jpg'));
    expect(await File(result.path).exists(), isTrue);
    expect(commands, hasLength(1));
    expect(commands.single, isNot(contains('-c:v')));
    expect(job.status.value, 'Complete');
    expect(job.progress.value, 1);
    await result.dispose();
    expect(await File(result.path).parent.exists(), isFalse);
  });

  test(
      'retry stages explain monotonic progress through encoding and finalization',
      () async {
    refuseFirst = true;
    final job = MediaEngine.instance.render(_composition);
    final progress = <double>[];
    final stages = <String>[];
    job.progress.addListener(() => progress.add(job.progress.value));
    job.status.addListener(() => stages.add(job.status.value));
    final result = await job.result;
    expect(commands.where((c) => c.contains('-c:v')), hasLength(2));
    expect(stages.any((s) => s.startsWith('Retrying:')), isTrue);
    expect(stages, contains('Finalizing video'));
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }
    expect(progress.last, 1);
    await result.dispose();
  });

  test('cancellation at finalization never publishes a result or leaves media',
      () async {
    overrunStatistics = true;
    final job = MediaEngine.instance.render(_composition,
        profile: EncodingProfile.momentExportFor(const Duration(seconds: 6)));
    job.status.addListener(() {
      if (job.status.value == 'Finalizing video') unawaited(job.cancel());
    });
    await expectLater(job.result, throwsA(isA<RenderCancelled>()));
    expect(job.status.value, 'Cancelled');
    expect(commands, hasLength(1)); // No poster starts after finalization.
    expect(await File(commands.single.last).parent.exists(), isFalse);
    expect(job.progress.value, lessThan(1));
  });

  for (final still in [true, false]) {
    for (final notification in ['progress', 'status']) {
      test(
          '${still ? 'still' : 'video'} success is settled before terminal $notification listeners cancel',
          () async {
        final job = still
            ? MediaEngine.instance.renderStill(_composition, watermark: false)
            : MediaEngine.instance.render(_composition);
        var cancellationRequests = 0;
        void cancelOnCompletion() {
          final completed = notification == 'progress'
              ? job.progress.value == 1
              : job.status.value == 'Complete';
          if (completed) {
            cancellationRequests++;
            unawaited(job.cancel());
          }
        }

        if (notification == 'progress') {
          job.progress.addListener(cancelOnCompletion);
        } else {
          job.status.addListener(cancelOnCompletion);
        }
        final result = await job.result;
        expect(cancellationRequests, 1);
        expect(job.isCancelled, isFalse);
        expect(job.status.value, 'Complete');
        expect(job.progress.value, 1);
        if (result is StampResult) {
          expect(await File(result.path).exists(), isTrue);
          await result.dispose();
          expect(await File(result.path).parent.exists(), isFalse);
        } else {
          final rendered = result as RenderResult;
          expect(await File(rendered.videoPath).exists(), isTrue);
          await rendered.dispose();
          expect(await File(rendered.videoPath).parent.exists(), isFalse);
        }
      });
    }
  }
}
