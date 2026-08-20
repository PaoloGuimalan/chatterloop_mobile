// This install's own identity: which build of the app is actually running.
//
// The source of truth is the platform manifest (Android PackageManager, iOS
// Info.plist), NOT pubspec.yaml - `flutter build` can override both parts with
// --build-name/--build-number, so what was compiled in is the only honest
// answer. Reading it here rather than from a --dart-define means the value
// cannot drift out of sync with the artifact it describes.
//
// Sent on every request as X-App-Version/X-Platform (see api_client.dart), so
// the server can tell old clients apart from new ones - the prerequisite for
// retiring a broken build, branching a wire format on client version, or
// attributing a bug report to a build.

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersion {
  AppVersion._();

  static Future<PackageInfo>? _pending;
  static PackageInfo? _info;

  /// Resolves the platform channel once per isolate and caches the result.
  ///
  /// Concurrent callers share one in-flight read: the request interceptor
  /// fires this on every request, and the first few can easily overlap.
  ///
  /// Failures are swallowed deliberately. This runs from the FCM background
  /// isolate too, where plugin registration is a precondition rather than a
  /// guarantee, and a request must never fail because a cosmetic header could
  /// not be built. A failed read leaves [isReady] false and is retried on the
  /// next call.
  static Future<void> ensureLoaded() async {
    if (_info != null) return;
    try {
      _info = await (_pending ??= PackageInfo.fromPlatform());
    } catch (_) {
      // Left unresolved on purpose - callers fall back to omitting the header.
    } finally {
      _pending = null;
    }
  }

  /// Whether a successful read has happened. False before [ensureLoaded]
  /// completes, and after a read that failed.
  static bool get isReady => _info != null;

  /// Marketing version, e.g. `1.0.0`. Android versionName / iOS
  /// CFBundleShortVersionString. Empty until loaded.
  static String get name => _info?.version ?? '';

  /// Android versionCode / iOS CFBundleVersion, as an int.
  ///
  /// The ONLY part safe to compare - it is the value Play forces to increase
  /// on every upload, whereas `name` is a human-facing string that can move in
  /// any direction. Returns 0 when unknown, which no real build can be, so a
  /// `build < minSupported` check fails open rather than locking out a client
  /// whose version simply could not be read.
  static int get build => int.tryParse(_info?.buildNumber ?? '') ?? 0;

  /// Wire form for X-App-Version: `1.0.0+1`, mirroring pubspec's notation.
  /// Null when unknown, so the caller can leave the header off entirely rather
  /// than send a placeholder the server would have to special-case.
  static String? get header {
    final info = _info;
    if (info == null || info.version.isEmpty) return null;
    return '${info.version}+${info.buildNumber}';
  }

  /// Wire form for X-Platform: `android`, `ios`, `web`, ...
  ///
  /// Lowercased because TargetPlatform's own names are mixed case (`iOS`,
  /// `macOS`) and a header value the server string-compares should not be.
  static String get platform =>
      kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();
}
