// User ACTIONS' requests - create, join, save, delete, send - that must never
// fail silently.
//
// The API methods for these used to reduce every outcome to a bool or a null:
// refused or crashed, the screen only learned "it didn't work" and could only
// say "Could not create the channel. Please try again." - even when the
// server had said exactly why ("You are not allowed to create channels in this
// server."). These keep the bool/null contract and show the reason
// themselves.

import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:dio/dio.dart';

/// Both backends' in-band refusal: `{"status": false}`, or Node's
/// routes/messages `{"success": false}`.
bool _isRefusal(Object? data) =>
    data is Map && (data['status'] == false || data['success'] == false);

/// Sends [request] and resolves true when the server accepted it.
///
/// Otherwise shows why over the app - the server's own message when it sent a
/// presentable one, [failure] when it did not - and resolves false. The caller
/// only has to undo its own state (a spinner, an optimistic toggle); it must
/// NOT show a failure of its own, or the user gets two.
///
/// Any 2xx is acceptance unless its body is a refusal, or [accepted] decides
/// differently.
Future<bool> reportedAction(
  Future<Response<dynamic>> Function() request, {
  required String failure,
  bool Function(Response<dynamic> response)? accepted,
}) async {
  final result = await reportedRequest<bool>(
    request,
    failure: failure,
    accepted: accepted,
    parse: (_) => true,
  );
  return result ?? false;
}

/// [reportedAction] for a request whose RESULT the caller needs: resolves
/// [parse]'s value when the server accepted it, null otherwise - with the
/// reason already shown.
///
/// An accepted response [parse] cannot use (null, or it throws) is reported as
/// [failure]: the server said nothing wrong, so there is nothing of its to
/// repeat, but the action still did not give the caller what it needed.
Future<T?> reportedRequest<T>(
  Future<Response<dynamic>> Function() request, {
  required String failure,
  required T? Function(Response<dynamic> response) parse,
  bool Function(Response<dynamic> response)? accepted,
}) async {
  final Response<dynamic> response;
  try {
    response = await request();
  } catch (e) {
    CLAlerts.requestError(e, fallback: failure);
    return null;
  }

  final ok = accepted != null ? accepted(response) : !_isRefusal(response.data);
  if (!ok) {
    CLAlerts.responseFailure(response, failure);
    return null;
  }

  T? value;
  try {
    value = parse(response);
  } catch (_) {
    value = null;
  }
  if (value == null) CLAlerts.error(failure);
  return value;
}
