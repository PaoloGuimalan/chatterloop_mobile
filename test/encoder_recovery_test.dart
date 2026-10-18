import 'package:chatterloop_app/core/media/encoder_recovery.dart';
import 'package:chatterloop_app/core/media/ffmpeg_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'successful fallback persists across store instances and app builds isolate it',
      () async {
    final store = EncoderPreferenceStore('android/device/1+2');
    await store
        .remember(const EncoderSettings(H264Encoder.mediaCodecPlanar, false));
    final settings = await EncoderPreferenceStore('android/device/1+2').load(
      [H264Encoder.mediaCodec, H264Encoder.mediaCodecPlanar],
    );
    expect(settings?.encoder.pixelFormat, 'yuv420p');
    expect(settings?.qpCeilings, isFalse);
    expect(
        await EncoderPreferenceStore('android/device/1+3').load(
          [H264Encoder.mediaCodecPlanar],
        ),
        isNull);
  });

  test(
      'input and transient errors stop recovery without poisoning saved settings',
      () async {
    final store = EncoderPreferenceStore('device');
    await store.remember(const EncoderSettings(H264Encoder.mediaCodec, true));
    for (final logs in [
      'Error while decoding stream: Invalid data found when processing input',
      'Error opening encoder: Resource temporarily unavailable',
      'Error initializing output stream: No space left on device',
      'Failed to configure output pad on Parsed_scale_0',
      'Error setting option sigma to value invalid for filter gblur',
      'Unknown failure',
    ]) {
      var calls = 0;
      final recovery = EncoderRecovery(store);
      final result = await recovery.encode<int>(
        candidates: [H264Encoder.mediaCodec, H264Encoder.mediaCodecPlanar],
        run: (settings, scale) async {
          calls++;
          return EncodeAttempt.failed(logs);
        },
      );
      expect(result.ok, isFalse);
      expect(calls, 1, reason: logs);
      expect((await store.load([H264Encoder.mediaCodec]))?.qpCeilings, isTrue);
    }
  });

  test('configuration rejection retries without QP and remembers the success',
      () async {
    final store = EncoderPreferenceStore('device');
    final attempts = <(String, bool)>[];
    final stages = <String>[];
    final result = await EncoderRecovery(store).encode<String>(
      candidates: [H264Encoder.mediaCodec, H264Encoder.mediaCodecPlanar],
      onStatus: stages.add,
      run: (settings, scale) async {
        attempts.add((settings.encoder.pixelFormat, settings.qpCeilings));
        return settings.qpCeilings
            ? const EncodeAttempt.failed(
                'Error setting option qp_i_max: Option not found')
            : const EncodeAttempt.success('file', 90);
      },
    );
    expect(result.value, 'file');
    expect(attempts, [('nv12', true), ('nv12', false)]);
    expect(stages.any((s) => s.contains('Retrying')), isTrue);
    expect((await store.load([H264Encoder.mediaCodec]))?.qpCeilings, isFalse);
  });

  test(
      'overshoot retries conservatively but keeps QP capability for future content',
      () async {
    final store = EncoderPreferenceStore('device');
    final attempts = <(bool, double)>[];
    final result = await EncoderRecovery(store).encode<String>(
      candidates: [H264Encoder.mediaCodec],
      maxBytes: 100,
      run: (settings, scale) async {
        attempts.add((settings.qpCeilings, scale));
        return EncodeAttempt.success('file', attempts.length == 1 ? 150 : 85);
      },
    );
    expect(result.ok, isTrue);
    expect(attempts.first, (true, 1.0));
    expect(attempts.last.$1, isFalse);
    expect(attempts.last.$2, closeTo(0.5666667, 0.00001));
    expect((await store.load([H264Encoder.mediaCodec]))?.qpCeilings, isTrue);
  });

  test('repeated oversized output is bounded and never saved as a capability',
      () async {
    final store = EncoderPreferenceStore('device');
    var calls = 0;
    final result = await EncoderRecovery(store).encode<String>(
      candidates: [H264Encoder.mediaCodec, H264Encoder.mediaCodecPlanar],
      maxBytes: 100,
      run: (settings, scale) async {
        calls++;
        return const EncodeAttempt.success('too big', 180);
      },
    );
    expect(result.oversized, isTrue);
    expect(calls, 2);
    expect(await store.load([H264Encoder.mediaCodec]), isNull);
  });
}
