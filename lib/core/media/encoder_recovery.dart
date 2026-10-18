import 'dart:convert';
import 'dart:math' as math;

import 'package:chatterloop_app/core/media/ffmpeg_command.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A configuration that actually encoded successfully on this install.
class EncoderSettings {
  final H264Encoder encoder;
  final bool qpCeilings;
  const EncoderSettings(this.encoder, this.qpCeilings);
}

/// Device-local preferences, namespaced by platform/OS and app build.
/// Preference failures never prevent an export.
class EncoderPreferenceStore {
  final String namespace;
  const EncoderPreferenceStore(this.namespace);
  String get _key => 'media_encoder.v1.$namespace';

  Future<EncoderSettings?> load(List<H264Encoder> candidates) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return null;
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      for (final encoder in candidates) {
        if (saved['name'] == encoder.name &&
            saved['format'] == encoder.pixelFormat &&
            saved['profile'] == encoder.profile &&
            saved['options'] == jsonEncode(encoder.options) &&
            saved['qp'] is bool) {
          return EncoderSettings(encoder, saved['qp'] as bool);
        }
      }
    } catch (_) {
      // Missing platform preferences or a stale/corrupt entry: try defaults.
    }
    return null;
  }

  Future<void> remember(EncoderSettings settings) async {
    try {
      final encoder = settings.encoder;
      await (await SharedPreferences.getInstance()).setString(
          _key,
          jsonEncode({
            'name': encoder.name,
            'format': encoder.pixelFormat,
            'profile': encoder.profile,
            'options': jsonEncode(encoder.options),
            'qp': settings.qpCeilings,
          }));
    } catch (_) {
      // Learning is optional; the completed render remains usable.
    }
  }
}

class EncodeAttempt<T> {
  final bool ok;
  final bool oversized;
  final T? value;
  final int bytes;
  final String? logs;
  const EncodeAttempt.success(this.value, this.bytes)
      : ok = true,
        oversized = false,
        logs = null;
  const EncodeAttempt.failed(this.logs)
      : ok = false,
        oversized = false,
        value = null,
        bytes = 0;
  const EncodeAttempt.tooLarge(this.value, this.bytes)
      : ok = false,
        oversized = true,
        logs = null;
}

/// Only explicit encoder configuration failures justify trying another
/// configuration. Input, storage, resource and unknown failures stop early
/// and never change what this device is remembered as supporting.
bool isEncoderConfigurationFailure(String? logs) {
  final text = (logs ?? '').toLowerCase();
  if (RegExp('invalid data|decoding|no such file|permission denied|no space|'
          'resource temporarily unavailable|out of memory|cannot allocate|'
          'device busy|timed out|i/o error|failed to configure output pad|'
          'error reinitializing filters|error while filtering|for filter')
      .hasMatch(text)) {
    return false;
  }
  const option = '(qp_i_max|qp_p_max|profile|pixel_format|pix_fmt)';
  return RegExp('unknown encoder|encoder .+ not found|'
          'error setting option $option|option $option.+not found|'
          'unsupported (pixel format|profile)|'
          'pixel format .+ not supported|failed to configure (the )?(encoder|codec)|'
          '(amediacodec|mediacodec).*(configure failed|unsupported configuration)|'
          'profile .+ not supported|no capable devices found')
      .hasMatch(text);
}

class EncoderRecovery {
  final EncoderPreferenceStore store;
  const EncoderRecovery(this.store);

  Future<EncodeAttempt<T>> encode<T>({
    required List<H264Encoder> candidates,
    required Future<EncodeAttempt<T>> Function(EncoderSettings, double) run,
    int? maxBytes,
    void Function(String)? onStatus,
  }) async {
    final saved = await store.load(candidates);
    final ordered = [
      if (saved != null) saved.encoder,
      ...candidates.where((encoder) => encoder != saved?.encoder),
    ];
    EncodeAttempt<T> outcome = const EncodeAttempt.failed(null);
    var attempt = 0;
    for (final encoder in ordered) {
      var settings = EncoderSettings(
          encoder,
          encoder == saved?.encoder
              ? saved!.qpCeilings
              : encoder.takesQpCeilings);
      void stage(String detail) => onStatus
          ?.call('${attempt++ == 0 ? 'Encoding' : 'Retrying'}: $detail');
      stage('preparing video');
      outcome = await run(settings, 1);
      if (!outcome.ok &&
          settings.qpCeilings &&
          isEncoderConfigurationFailure(outcome.logs)) {
        settings = EncoderSettings(encoder, false);
        stage('using compatible encoder settings');
        outcome = await run(settings, 1);
      }
      if (outcome.ok) {
        final learned = settings;
        if (maxBytes != null && outcome.bytes > maxBytes) {
          // Content-dependent overshoot must not teach the device that it
          // cannot support QP ceilings. Retry once with a conservative target.
          final scale = math.min(0.85, maxBytes * 0.85 / outcome.bytes);
          stage('reducing size for sharing');
          outcome = await run(EncoderSettings(encoder, false), scale);
          if (outcome.ok && outcome.bytes > maxBytes) {
            return EncodeAttempt.tooLarge(outcome.value, outcome.bytes);
          }
          if (!outcome.ok) return outcome;
        }
        await store.remember(learned);
        return outcome;
      }
      if (!isEncoderConfigurationFailure(outcome.logs)) return outcome;
    }
    return outcome;
  }
}
