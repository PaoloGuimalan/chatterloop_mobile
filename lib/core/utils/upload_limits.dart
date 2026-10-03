import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The one upload size cap, for every surface that attaches a file.
//
// One constant because the number has to match the SERVER's - the multipart
// parsers on /posts/upload and /users/sendFiles both reject anything larger
// (server/reusables/vars/uploads.js). A client check that's more permissive
// than the server's just means the user waits for the whole upload before
// being told no; three separate copies of it here means they eventually
// disagree with each other too.
//
// Surfaces using it: the post composer, diary attachments, message
// attachments.
//
// Supplied at BUILD time rather than runtime - Dart has no process env on a
// phone, so this comes through `--dart-define-from-file=env.json` (see
// env.example.json) or `--dart-define=MAX_UPLOAD_FILE_SIZE_MB=...`, the same
// route SECRET_KEY takes. That means changing it needs a new build, unlike the
// server's, which is why the two are allowed to differ: as long as the app's
// cap is the smaller of the two, an older build just rejects a file the server
// would have accepted, rather than uploading one it will refuse.

/// Megabytes, straight from the define. Absent -> 0, which is why the value
/// below is guarded rather than used directly.
const int _definedMaxUploadMb =
    int.fromEnvironment('MAX_UPLOAD_FILE_SIZE_MB', defaultValue: 0);

/// The hardcoded fallback: what applies with no define, and the safety net for
/// a nonsensical one. A define of 0 or a negative number would otherwise be a
/// cap that rejects every file, and there is no runtime check to catch it -
/// `int.fromEnvironment` only substitutes its default when the key is entirely
/// absent, and a non-integer value fails the build outright.
const int _kDefaultMaxUploadMb = 100;

/// Effective cap in megabytes.
const int kMaxUploadMb =
    _definedMaxUploadMb > 0 ? _definedMaxUploadMb : _kDefaultMaxUploadMb;

const int kMaxUploadBytes = kMaxUploadMb * 1024 * 1024;

/// For user-facing copy - "Up to 100MB per file", "over 100MB".
const String kMaxUploadLabel = "${kMaxUploadMb}MB";

// ---------------------------------------------------------------------------
// Per-feature limits, as the SERVER enforces them.
//
// The constants above stay as the build-time ceiling (the Moments encoder
// sizes its output against kMaxUploadBytes, which has to be const). What a
// file may actually be is decided per feature by the platform settings table
// (core_variable, edited in the Django admin), served by GET /media/config.
// UploadLimits.load() fetches it on every app start; until it answers - or if
// it never does - the defaults below apply. They mirror the server's own
// defaults (server/reusables/media/config.js).
//
// The server checks again at upload time and storage refuses a wrong size
// itself, so a stale limit here only means hearing "too big" a step later.
// ---------------------------------------------------------------------------

/// What an upload is for - the keys of the server's upload_limits.
enum UploadFeature {
  message('message'),
  voiceNote('voice_note'),
  postMedia('post_media'),
  moment('moment'),
  momentPoster('moment_poster'),
  diary('diary'),
  avatar('avatar'),
  cover('cover'),
  comment('comment');

  const UploadFeature(this.key);
  final String key;
}

class UploadLimit {
  const UploadLimit(this.maxMB, this.types);
  final double maxMB;
  final List<String> types;

  int get maxBytes => (maxMB * 1024 * 1024).floor();

  /// For user-facing copy - "Files here can be at most 100MB".
  String get label =>
      maxMB == maxMB.roundToDouble() ? '${maxMB.round()}MB' : '${maxMB}MB';

  /// Whether [mime] matches a pattern ("*", "image/*", "video/mp4").
  bool allows(String mime) {
    final value = mime.toLowerCase();
    return types.any((pattern) {
      final p = pattern.toLowerCase();
      if (p == '*' || p == '*/*') return true;
      if (p.endsWith('/*')) return value.startsWith(p.substring(0, p.length - 1));
      return value == p;
    });
  }
}

class UploadTransfer {
  const UploadTransfer({
    this.multipartThresholdMB = 16,
    this.partSizeMB = 8,
    this.concurrency = 4,
  });
  final double multipartThresholdMB;
  final double partSizeMB;
  final int concurrency;
}

class UploadLimits {
  UploadLimits._();

  static const Map<String, UploadLimit> defaults = {
    'message': UploadLimit(100, ['*']),
    'voice_note': UploadLimit(25, ['audio/*']),
    'post_media': UploadLimit(100, ['image/*', 'video/*']),
    'moment': UploadLimit(100, ['image/*', 'video/mp4']),
    'moment_poster': UploadLimit(10, ['image/jpeg', 'image/png']),
    'diary': UploadLimit(100, ['*']),
    'avatar': UploadLimit(10, ['image/*']),
    'cover': UploadLimit(10, ['image/*']),
    'comment': UploadLimit(10, ['image/*']),
  };

  static const _prefsKey = 'chatterloop.media_config';

  static Map<String, UploadLimit> _limits = Map.of(defaults);
  static UploadTransfer _transfer = const UploadTransfer();

  static UploadLimit of(UploadFeature feature) =>
      _limits[feature.key] ?? defaults[feature.key]!;

  static UploadTransfer get transfer => _transfer;

  /// Reads the last config this device loaded, then fetches a fresh one.
  /// Call once at startup; never throws.
  static Future<void> load({required String apiUrl, Dio? dio}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_prefsKey);
      if (cached != null) applyJson(jsonDecode(cached));
      final response = await (dio ?? Dio()).get(
        '$apiUrl/media/config',
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      if (response.data is Map) {
        applyJson(response.data);
        await prefs.setString(
          _prefsKey,
          jsonEncode({
            'limits': response.data['limits'],
            'transfer': response.data['transfer'],
          }),
        );
      }
    } catch (_) {
      // Offline, or the server is down: keep what we have.
    }
  }

  /// Applies a /media/config body; a broken entry keeps its default.
  @visibleForTesting
  static void applyJson(dynamic body) {
    if (body is! Map) return;
    final rawLimits = body['limits'];
    if (rawLimits is Map) {
      final next = Map.of(defaults);
      rawLimits.forEach((feature, value) {
        final maxMB = value is Map ? value['maxMB'] : null;
        if (maxMB is num && maxMB > 0) {
          final types = value['types'] is List
              ? (value['types'] as List).whereType<String>().toList()
              : <String>[];
          next['$feature'] = UploadLimit(
            maxMB.toDouble(),
            types.isEmpty ? const ['*'] : types,
          );
        }
      });
      _limits = next;
    }
    final t = body['transfer'];
    if (t is Map) {
      double positive(dynamic v, double fallback) =>
          v is num && v > 0 ? v.toDouble() : fallback;
      _transfer = UploadTransfer(
        multipartThresholdMB: positive(t['multipartThresholdMB'], 16),
        partSizeMB: positive(t['partSizeMB'], 8).clamp(5, double.infinity),
        concurrency: positive(t['concurrency'], 4).round().clamp(1, 8),
      );
    }
  }

  @visibleForTesting
  static void reset() {
    _limits = Map.of(defaults);
    _transfer = const UploadTransfer();
  }
}
