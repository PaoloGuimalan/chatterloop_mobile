// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/utils/content_validator.dart';
import 'package:chatterloop_app/core/utils/device_token.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/core/requests/patched_sse_client.dart';
import 'package:chatterloop_app/core/utils/jwt_tools.dart';
import 'package:chatterloop_app/core/utils/sse_events.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// import 'package:http/http.dart' as http;

final EventBus eventBus = EventBus();

class SseConnection {
  final storage = FlutterSecureStorage();

  /// Static, not per-instance - SSEClient's own connection state
  /// (flutter_client_sse's `_client`) is static too, and every call site
  /// (AuthenticatedShell, EntityApi's post-switch refresh, logout) each
  /// construct their own `SseConnection()`, so this has to be shared to
  /// actually track "the one subscription currently in effect."
  static StreamSubscription? _subscription;

  /// Uses PatchedSSEClient (patched_sse_client.dart), a vendored copy of
  /// the flutter_client_sse-2.0.3 package's SSEClient, not the package
  /// itself - the original's unsubscribeFromSSE() only closes the
  /// underlying http.Client, which raises an error the package's OWN retry
  /// logic treats as a dropped connection worth auto-retrying after 5s,
  /// using the *original* url/token closure. There's no flag in the
  /// original to say "this close was intentional" - so every explicit
  /// disconnect (logout, or re-initializing after an entity switch)
  /// silently reconnected itself 5s later as the PREVIOUS identity. Since
  /// this server ties presence/online-status to having a live SSE session,
  /// that wasn't just a wasted request - it kept the old identity showing
  /// online to other users indefinitely (retried forever, not once). The
  /// vendored copy fixes this at the source (see its own doc comment) -
  /// unsubscribeFromSSE() there genuinely stops the connection.
  ///
  /// The StreamSubscription cancel below is a second, independent layer on
  /// top of that fix: it stops THIS app from acting on anything that
  /// arrives in the split second between closing and that closure fully
  /// taking effect, regardless of which SSE client is underneath.
  void initializeConnection() async {
    await _subscription?.cancel();
    PatchedSSEClient.unsubscribeFromSSE();
    String? token = await storage.read(key: 'token');
    String deviceToken = await resolveDeviceToken();
    String ssetoken = JwtTools().createJwt(
        {"token": token, "deviceToken": deviceToken, "type": "notifications"},
        secretKey);
    String url = '${Endpoints().apiUrl}${Endpoints().sseRoute}$ssetoken';

    ContentValidator().printer(url);

    _subscription = PatchedSSEClient.subscribeToSSE(
        method: SSERequestType.GET,
        url: url,
        header: {
          "Accept": "text/event-stream",
          "origin": Endpoints.origin,
          // Disable gzip on the SSE stream. dart:io's HttpClient requests
          // `Accept-Encoding: gzip` by default and auto-decompresses -
          // but the gzip decoder can only emit decoded bytes once it has a
          // full compressed block, so it BUFFERS individual small events
          // (a lone participant-left / produce-response) until enough
          // later traffic accumulates to complete the block. That exactly
          // matched the symptom: the join-time burst of events (lots of
          // bytes at once) always arrived, but isolated mid-call events
          // (webapp leaving, a second produce-response) stalled in the
          // decoder and never surfaced until the connection was torn down.
          // The browser's native EventSource doesn't hit this because it
          // streams each parsed event immediately. Forcing identity
          // encoding makes each flushed SSE event deliver as its own
          // uncompressed chunk, so the parser sees it right away.
          "Accept-Encoding": "identity",
          "Cache-Control": "no-cache",
        }).listen((event) {
      eventBus.fire(event);
      SseEvents().listen(event, true);
      // ContentValidator().printer({"event": event.event, "data": event.data});
    });
  }

  void closeConnection() {
    _subscription?.cancel();
    _subscription = null;
    PatchedSSEClient.unsubscribeFromSSE();
  }
}
