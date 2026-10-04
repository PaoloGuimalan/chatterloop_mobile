// Asks the Django user service whether this build has an update waiting
// (core.Update, GET /api/user/system-update). Public, so it answers on
// the login screen as well as inside the app.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/utils/app_version.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:flutter/foundation.dart';

class SystemUpdateInfo {
  /// Required updates block the app; optional ones can be skipped.
  final bool required;

  /// The latest release - what the user gets by updating.
  final String version;
  final int build;
  final String title;
  final String details;

  /// Where "Update" goes. Empty when the release did not set one.
  final String storeUrl;

  const SystemUpdateInfo({
    required this.required,
    required this.version,
    required this.build,
    required this.title,
    required this.details,
    required this.storeUrl,
  });

  factory SystemUpdateInfo.fromJson(Map<String, dynamic> json) =>
      SystemUpdateInfo(
        required: json['severity'] == 'required',
        version: json['version']?.toString() ?? '',
        build: int.tryParse(json['build']?.toString() ?? '') ?? 0,
        title: json['title']?.toString() ?? '',
        details: json['details']?.toString() ?? '',
        storeUrl: json['store_url']?.toString() ?? '',
      );
}

class SystemUpdateApi {
  final _dio = ApiClient.userService.dio;
  final _endpoints = Endpoints();

  /// The update to offer, or null.
  ///
  /// Null also when this build's own version could not be read, and on any
  /// failure: an update check must never be what stands between someone and
  /// the app, so it fails open.
  Future<SystemUpdateInfo?> check() async {
    await AppVersion.ensureLoaded();
    if (AppVersion.build < 1) return null;
    try {
      final response = await _dio.get(
        _endpoints.systemUpdate,
        queryParameters: {
          'platform': AppVersion.platform,
          'build': AppVersion.build,
        },
      );
      final data = response.data?['data'];
      if (data is! Map) return null;
      return SystemUpdateInfo.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      if (kDebugMode) print("ERROR systemUpdate check: $e");
      return null;
    }
  }
}
