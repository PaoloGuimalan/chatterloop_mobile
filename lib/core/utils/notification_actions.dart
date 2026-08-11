// Executes the server-driven notification buttons and resolves the row's
// destination.
//
// The server sends `redirects`/`actions` as flat arrays with one entry per
// platform; NotificationV2.fromJson has already filtered them to this build's
// platform, so everything here is addressed to us. Anything unrecognised is
// skipped rather than guessed at - that is what lets the server introduce an
// action type without breaking already-shipped apps.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_v2_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Whether this client can actually carry the action out, in a shape that is
/// safe to carry out. An action failing this renders NO button rather than one
/// that misbehaves when pressed.
///
/// The two url rules are the security boundary, not tidiness:
///
///  - "api-request" must be a PATH. An absolute url would let a stored record
///    aim an AUTHENTICATED request at a host of its choosing - and notification
///    rows are generated from other users' actions, so that is a reachable
///    path, not a hypothetical. A path can only ever resolve against a base
///    compiled into this build.
///
///  - "external-api-request" must be ABSOLUTE, precisely so it can never be
///    mistaken for first-party and pick up our credentials.
bool isRunnableAction(NotificationAction a) {
  switch (a.type) {
    case 'in-app-redirect':
      return a.route.isNotEmpty;
    case 'external-redirect':
      return _isAbsolute(a.url);
    case 'api-request':
      return _isFirstPartyPath(a.url) && a.method.isNotEmpty;
    case 'external-api-request':
      return _isAbsolute(a.url) && a.method.isNotEmpty;
    default:
      return false;
  }
}

bool _isAbsolute(String url) =>
    RegExp(r'^[a-z][a-z0-9+.\-]*:', caseSensitive: false).hasMatch(url);

/// A first-party path: leading slash, and NOT protocol-relative.
///
/// Tested positively rather than as "not absolute": `//evil.tld/steal` carries
/// no scheme, so a not-absolute check waves it through, and anything that later
/// resolves it against a base would land on another origin carrying our token.
bool _isFirstPartyPath(String url) =>
    url.startsWith('/') && !url.startsWith('//') && !_isAbsolute(url);

/// Result of running one action. Navigation is RETURNED rather than performed,
/// so routing stays with the widget that owns a BuildContext.
class NotificationActionOutcome {
  final bool ok;
  final String? navigateTo;
  final String? message;

  const NotificationActionOutcome({
    required this.ok,
    this.navigateTo,
    this.message,
  });
}

/// A Dio with NO interceptors, for third-party calls.
///
/// ApiClient's instances attach `x-access-token`, `device-token`, `X-Nonce`,
/// `origin` and `fcm-token` on every request. The access token is a bearer
/// credential for the whole account and the rest identify the user and the
/// install - none of which has any business being sent to a host a stored
/// notification happened to name. So an external call goes through a client
/// that has no interceptors on it at all, rather than one we remember to strip.
final Dio _externalDio = Dio();

Dio _firstPartyDioFor(String service) =>
    service == 'realtime' ? ApiClient.instance.dio : ApiClient.userService.dio;

/// Runs one action.
Future<NotificationActionOutcome> runNotificationAction(
    NotificationAction action) async {
  if (!isRunnableAction(action)) {
    return const NotificationActionOutcome(
        ok: false, message: 'Unsupported action');
  }

  if (action.type == 'in-app-redirect') {
    return NotificationActionOutcome(ok: true, navigateTo: action.route);
  }

  if (action.type == 'external-redirect') {
    final launched = await _openExternal(action.url);
    return NotificationActionOutcome(
      ok: launched,
      message: launched ? null : 'Could not open that link.',
    );
  }

  // FIRST-PARTY vs EXTERNAL decides both the client and whether credentials go
  // along, and it is decided structurally rather than by trusting `type`: a
  // first-party call is a PATH against a base compiled into this build.
  final isExternal = action.type == 'external-api-request';

  try {
    final response = isExternal
        ? await _externalDio.request(
            action.url,
            data: action.payload,
            options: Options(
              method: action.method,
              headers: action.headers?.map((k, v) => MapEntry(k, v)),
            ),
          )
        : await _firstPartyDioFor(action.service).request(
            action.url,
            data: action.payload,
            options: Options(
              method: action.method,
              // Row-supplied headers, applied on top of the interceptor's.
              // Needed by real actions - the contact and follow endpoints both
              // take approve/decline as an `action` header rather than in the
              // body.
              headers: action.headers?.map((k, v) => MapEntry(k, v)),
            ),
          );

    final data = response.data;
    final ok = data is Map ? data['status'] != false : true;
    return NotificationActionOutcome(
      ok: ok,
      message: data is Map ? data['message']?.toString() : null,
    );
  } on DioException catch (e) {
    if (kDebugMode) print('[notificationAction] ${action.id} failed: $e');
    final data = e.response?.data;
    return NotificationActionOutcome(
      ok: false,
      message: data is Map
          ? data['message']?.toString()
          : 'Something went wrong. Please try again.',
    );
  } catch (e) {
    if (kDebugMode) print('[notificationAction] ${action.id} failed: $e');
    return const NotificationActionOutcome(
        ok: false, message: 'Something went wrong. Please try again.');
  }
}

/// Opens the row's destination, or returns false when it is external and could
/// not be launched. In-app routes are returned to the caller instead.
Future<bool> _openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Opens a redirect. Returns the in-app route to navigate to, or null when it
/// was external (already handled) or unusable.
Future<String?> resolveRedirect(NotificationRedirect redirect) async {
  if (redirect.route.isEmpty) return null;
  if (redirect.isExternal) {
    await _openExternal(redirect.route);
    return null;
  }
  return redirect.route;
}
