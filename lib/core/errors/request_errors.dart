// The one place that turns "a request failed" into words a person can act on.
//
// A Dart port of webapp/src/reusables/hooks/errormessages.ts, so both clients
// say the same thing about the same failure. Neither backend answers in a
// single shape:
//
//   Django (user_service)
//     {"status": false, "message": "..."}   the deliberate, human-written case
//     {"detail": "..."}                     DRF permissions/auth/throttling,
//                                           sometimes prefixed with a sentinel
//                                           code (see _codeMessages)
//     {"field": ["..."], ...}               DRF serializer validation
//     {"error": "<python exception>"}       the 500 handlers in newsfeed/views
//
//   Node (server)
//     {"status": false, "message": "..."}   most routes, and every 403 from
//                                           requiresPermission/hasPermission
//     {"success": false, "message": "..."}  routes/messages
//     {"error": "<node exception>"}         routes/webrtc, routes/realms
//
// Two of those carry raw exception text, which is both meaningless to a user
// and a small information leak, so this only ever repeats a server string it
// judges presentable and falls back to the caller's own copy otherwise.
//
// Pure interpretation: nothing here talks to a backend or draws anything.
// CLAlerts (core/ui/cl_alerts.dart) is what shows the result.

import 'dart:io';

import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:dio/dio.dart';

const String genericErrorMessage = 'Something went wrong. Please try again.';

const String _unreachableMessage =
    "We couldn't reach Chatterloop. Check your connection and try again.";
const String _timeoutMessage =
    'That took too long to respond. Check your connection and try again.';
const String _serverMessage =
    'Something went wrong on our end. Please try again in a moment.';

/// Copy of last resort, per status. Only reached when the response carried
/// nothing presentable AND the caller passed no action-specific fallback.
const Map<int, String> _statusMessages = {
  400: "We couldn't process that request. Check the details and try again.",
  401: 'Your session has expired. Please sign in again.',
  403: "You don't have permission to do that.",
  404: "We couldn't find what you were looking for.",
  405: "That action isn't available here.",
  408: _timeoutMessage,
  409: 'That conflicts with something that already exists.',
  410: 'That is no longer available.',
  413: 'That file is too large to upload.',
  415: "That file type isn't supported.",
  422: "Some of the details you entered aren't valid.",
  423: 'That is locked right now. Please try again later.',
  429: "You're doing that a little too often. Wait a moment and try again.",
};

/// Statuses whose meaning is sharper than anything the caller could say about
/// the attempt, so their copy outranks the caller's fallback when the body had
/// nothing of its own. 401 is deliberately not here - the sign-in screens are
/// where it mostly lands, and "Your session has expired" is wrong advice there.
const Set<int> _statusOutranksFallback = {403, 413, 415, 429};

/// Sentinel codes user/backends.py prefixes onto DRF's `detail` when an
/// otherwise-valid session is refused for a compliance reason.
const Map<String, String> _codeMessages = {
  'PROFILE_INCOMPLETE':
      'Finish setting up your profile to continue - we still need your birthdate and gender.',
  'CONSENT_REQUIRED':
      'Please review and accept the latest Terms and Conditions to continue.',
  'ACCOUNT_UNDERAGE':
      "This account doesn't meet the minimum age requirement for Chatterloop.",
  'ACCOUNT_INACTIVE':
      "This account has been deactivated. Contact support if you think that's a mistake.",
};

/// The terse strings the auth backends raise for session problems. They read
/// like server logs, so each gets a plain-language replacement. Keys are
/// lowercased for matching.
const Map<String, String> _detailMessages = {
  'origin blocked':
      'This request was blocked. Please restart Chatterloop and try again.',
  'token not defined': 'You need to be signed in to do that.',
  'authentication credentials were not provided.':
      'You need to be signed in to do that.',
  'no nonce defined': "We couldn't verify this request. Please try again.",
  'error nonce': "We couldn't verify this request. Please try again.",
  'invalid nonce': "We couldn't verify this request. Please try again.",
  // The nonce carries a timestamp taken from THIS device, and both backends
  // reject anything more than a minute off their own clock. The device's own
  // date & time setting is the entire fix.
  'expired nonce':
      "Your phone's date & time appear to be off. Set them to update automatically, then try again.",
  'request expired. please sync your clock.':
      "Your phone's date & time appear to be off. Set them to update automatically, then try again.",
  'device not recognized. try logging in again.':
      "We don't recognise this device. Please sign in again.",
  'device not logged in.':
      'This device has been signed out. Please sign in again.',
  'account does not exist': "We couldn't find an account for those details.",
  'error querying account': _serverMessage,
  'you do not have permission to perform this action.':
      "You don't have permission to do that.",
  // The Node middleware's wording for a nonce it has already seen - which an
  // accidental double-tap also produces.
  'replay attack detected!': 'That request was already sent. Please try again.',
};

/// Text that is plainly a server-side exception rather than a message meant
/// for a person.
final List<RegExp> _rawErrorSignatures = [
  RegExp(r'matching query does not exist', caseSensitive: false),
  RegExp(r'\btraceback\b', caseSensitive: false),
  RegExp(
      r'\b(?:Key|Type|Value|Attribute|Index|Integrity|Operational|Runtime|Reference)Error\b'),
  RegExp(r'\bException\b'),
  RegExp(r'\bpsycopg\d?\b', caseSensitive: false),
  RegExp(r'duplicate key value', caseSensitive: false),
  RegExp(r'\bE(?:CONNREFUSED|CONNRESET|TIMEDOUT|NOTFOUND|HOSTUNREACH|PIPE)\b'),
  RegExp(r'\bat [\w$.<>]+ \(.*:\d+:\d+\)'),
  RegExp(r'\bundefined is not\b|\bis not a function\b|\bcannot read propert',
      caseSensitive: false),
  RegExp(r'^\s*[\[{<]'),
  RegExp(r'request failed with status code', caseSensitive: false),
  RegExp(r'^network error$', caseSensitive: false),
];

const int _maxPresentableLength = 300;

/// The permission middleware (server/reusables/hooks/permissionChecker.js)
/// names the permission code after its sentence. Without the code it is
/// exactly the sentence a person should see.
String _stripPermissionCode(String text) => text
    .replaceFirst(RegExp(r'\s*\([a-z_]+(?:\.[a-z_]+)+\)(?=\.?\s*$)'), '')
    .trim();

/// A server string is only repeated if it reads like a sentence, not a log.
bool _isPresentable(Object? value) {
  if (value is! String) return false;
  final text = _stripPermissionCode(value.trim());
  if (text.isEmpty || text.length > _maxPresentableLength) return false;
  return !_rawErrorSignatures.any((pattern) => pattern.hasMatch(text));
}

/// Sentence-cases a backend string and gives it closing punctuation, so it
/// sits beside the app's own copy without looking like a different app wrote
/// it.
String _polish(String value) {
  final text =
      _stripPermissionCode(value.trim()).replaceAll(RegExp(r'\s+'), ' ');
  if (text.isEmpty) return text;
  final cased = text[0].toUpperCase() + text.substring(1);
  return RegExp(r'[.!?…]$').hasMatch(cased) ? cased : '$cased.';
}

/// "profile_picture" -> "Profile picture", for DRF field-error keys.
String _humanizeFieldName(String field) =>
    _polish(field.replaceAll(RegExp(r'[_.]+'), ' ').trim())
        .replaceFirst(RegExp(r'\.$'), '');

const Set<String> _fieldlessErrorKeys = {
  'non_field_errors',
  'detail',
  'message',
  'error',
  '__all__',
};

/// Keys that carry PAYLOAD rather than a complaint - so a refusal like
/// `{"status": false, "result": [...]}` never has a sentence lifted out of
/// `result` and shown as if it were the reason.
const Set<String> _nonErrorKeys = {
  'status',
  'success',
  'result',
  'results',
  'data',
  'count',
  'next',
  'previous',
};

String? _firstStringIn(Object? value, [int depth = 0]) {
  if (_isPresentable(value)) return value as String;
  if (depth >= 2) return null;
  if (value is List) {
    for (final item in value) {
      final found = _firstStringIn(item, depth + 1);
      if (found != null) return found;
    }
    return null;
  }
  if (value is Map) {
    for (final item in value.values) {
      final found = _firstStringIn(item, depth + 1);
      if (found != null) return found;
    }
  }
  return null;
}

/// Is this the SHAPE DRF gives a ValidationError - every remaining key mapping
/// to a message or a list of them?
bool _looksLikeFieldErrors(Map data) {
  final entries =
      data.entries.where((e) => !_nonErrorKeys.contains(e.key)).toList();
  if (entries.isEmpty) return false;
  bool isMessageish(Object? item) => item is String || item is List;
  return entries.every((e) {
    final value = e.value;
    if (value is String) return true;
    if (value is List) return value.every(isMessageish);
    if (value is Map) return value.values.every(isMessageish);
    return false;
  });
}

/// `{"email": ["This field is required."]}` -> "Email: This field is
/// required." At most three fields; the alert is small and the form is still
/// on screen.
String? _describeFieldErrors(Map data) {
  if (!_looksLikeFieldErrors(data)) return null;
  final parts = <String>[];
  for (final entry in data.entries) {
    final field = entry.key.toString();
    if (_nonErrorKeys.contains(field)) continue;
    final sentence = _firstStringIn(entry.value);
    if (sentence == null) continue;
    parts.add(_fieldlessErrorKeys.contains(field)
        ? _polish(sentence)
        : '${_humanizeFieldName(field)}: ${_polish(sentence)}');
    if (parts.length == 3) break;
  }
  return parts.isEmpty ? null : parts.join(' ');
}

/// Reads a body in the order the backends actually populate it. Null when it
/// held nothing a person should be shown - the signal to fall back to the
/// caller's own copy.
String? messageFromBody(Object? data) {
  if (data == null) return null;

  if (data is List) {
    final sentence = _firstStringIn(data);
    return sentence == null ? null : _polish(sentence);
  }

  // A string body is an HTML error page or a proxy's notice - never written
  // for this user.
  if (data is! Map) return null;

  final detail = data['detail'];
  if (detail is String) {
    final code = detail.trim().split(':').first;
    final coded = _codeMessages[code];
    if (coded != null) return coded;
    final mapped = _detailMessages[detail.trim().toLowerCase()];
    if (mapped != null) return mapped;
  }

  for (final key in const ['message', 'error', 'detail']) {
    final value = data[key];
    if (_isPresentable(value)) {
      final text = value as String;
      return _detailMessages[_stripPermissionCode(text).toLowerCase()] ??
          _polish(text);
    }
  }

  final nested = data['errors'] ?? data['error'];
  if (nested is Map) {
    final described = _describeFieldErrors(nested);
    if (described != null) return described;
  }

  return _describeFieldErrors(data);
}

/// What to show for a failed request, and how.
class RequestErrorDescription {
  final CLAlertType type;
  final String message;

  /// HTTP status, or 0 when the request never got an answer.
  final int status;

  /// True for a cancelled request - not worth telling anyone about.
  final bool silent;

  const RequestErrorDescription({
    required this.type,
    required this.message,
    required this.status,
    this.silent = false,
  });
}

/// 4xx is something the user can act on; anything else is on us.
CLAlertType _alertTypeFor(int status) =>
    status >= 400 && status < 500 ? CLAlertType.warning : CLAlertType.error;

/// A request that never reached the server is a connection problem, not a
/// problem with what the user asked for.
///
/// Anything that is NOT a transport failure - a file that could not be read
/// before an upload, a bug on this side - is not the network's fault either,
/// and "check your connection" would send the user after the wrong thing. That
/// gets the caller's own description of the attempt.
String _describeTransportFailure(Object error, String? fallback) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return _timeoutMessage;
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
        return _unreachableMessage;
      default:
        // `unknown` wraps whatever was thrown underneath - a lost socket is
        // the network, anything else is not.
        final cause = error.error;
        if (cause is SocketException || cause is HttpException) {
          return _unreachableMessage;
        }
        return fallback ?? genericErrorMessage;
    }
  }
  if (error is SocketException || error is HttpException) {
    return _unreachableMessage;
  }
  return fallback ?? genericErrorMessage;
}

/// The single entry point: everything else here is in service of this.
///
/// [fallback] is the caller's own description of what was being attempted
/// ("We couldn't create that channel.") and is used whenever the response had
/// nothing to say - it is almost always more useful than generic status copy,
/// so it wins over the status table except where the status is more specific
/// than any caller could be.
RequestErrorDescription describeRequestError(Object error, {String? fallback}) {
  if (error is DioException && error.type == DioExceptionType.cancel) {
    return const RequestErrorDescription(
        type: CLAlertType.info, message: '', status: 0, silent: true);
  }

  final response = error is DioException ? error.response : null;
  if (response == null) {
    return RequestErrorDescription(
      type: CLAlertType.error,
      message: _describeTransportFailure(error, fallback),
      status: 0,
    );
  }

  final status = response.statusCode ?? 0;

  // 5xx bodies are `{"error": str(exception)}` on both backends - nothing in
  // there for a user.
  if (status >= 500) {
    return RequestErrorDescription(
      type: CLAlertType.error,
      message: fallback != null
          ? '${_polish(fallback)} Please try again in a moment.'
          : _serverMessage,
      status: status,
    );
  }

  final fromServer = messageFromBody(response.data);
  if (fromServer != null) {
    return RequestErrorDescription(
        type: _alertTypeFor(status), message: fromServer, status: status);
  }

  if (_statusOutranksFallback.contains(status) &&
      _statusMessages.containsKey(status)) {
    return RequestErrorDescription(
        type: _alertTypeFor(status),
        message: _statusMessages[status]!,
        status: status);
  }

  return RequestErrorDescription(
    type: _alertTypeFor(status),
    message: fallback ?? _statusMessages[status] ?? genericErrorMessage,
    status: status,
  );
}

/// The server's own reason for [error], or null to let the caller use its own
/// words - for API methods that hand a message back to their screen rather
/// than showing it.
///
/// The server's presentable message when it gave one, the connection copy
/// when it never answered - and null for a server-side crash, a cancelled
/// request, or anything that isn't a request failure at all.
String? serverReason(Object error) {
  if (error is! DioException || error.type == DioExceptionType.cancel) {
    return null;
  }
  final response = error.response;
  if (response == null) {
    final message = describeRequestError(error).message;
    return message == genericErrorMessage ? null : message;
  }
  if ((response.statusCode ?? 0) >= 500) return null;
  return messageFromBody(response.data);
}

/// The friendly sentence on its own, for callers that render their own UI.
String resolveErrorMessage(Object error, {String? fallback}) {
  final described = describeRequestError(error, fallback: fallback);
  return described.message.isNotEmpty
      ? described.message
      : (fallback ?? genericErrorMessage);
}

/// Both backends also refuse work inside a 200 - `{"status": false,
/// "message": ...}` - so a success-path refusal needs the same guard.
/// Accepts a Dio [Response] or the body already unwrapped from one.
String resolveResponseMessage(Object? response, String fallback) {
  final body = response is Response ? response.data : response;
  return messageFromBody(body) ?? fallback;
}
