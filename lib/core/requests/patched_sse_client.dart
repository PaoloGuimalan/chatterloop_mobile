// Vendored copy of flutter_client_sse-2.0.3's SSEClient (pub cache:
// flutter_client_sse-2.0.3/lib/flutter_client_sse.dart), patched to fix a
// real bug rather than just work around it from the outside.
//
// The original unsubscribeFromSSE() only closes the underlying
// http.Client, which raises an error on the pending request - and the
// package's OWN retry logic (_retryConnection) treats any error as "the
// connection dropped, retry in 5s", using the exact url/token closure
// captured at the original subscribeToSSE call. There is no flag in the
// original package to tell it "no, this close was intentional, don't
// reconnect" - so every explicit disconnect (logout, or reconnecting under
// a different identity after an entity switch) silently reconnects itself
// 5s later as the PREVIOUS identity. Since this app's server ties presence/
// online-status to having a live SSE session, that stale reconnect isn't
// just a wasted request - it keeps the old identity showing online to
// other users indefinitely (it keeps retrying forever, not once), until
// that old token happens to expire.
//
// Fix: track *which* StreamController each caller asked to be disconnected
// (a Set of controller references, not a single global flag - a single
// flag would race the moment SseConnection.initializeConnection() closes
// the old connection and immediately opens a new one, since the old
// connection's close-triggered error can arrive asynchronously *after*
// the new connection has already reset a shared flag back to "retry OK").
// A per-controller Set has no such race: closing connection A's
// controller can never affect connection B's, since they're different
// objects regardless of timing. Every other line of logic here (parsing,
// retry delay, request construction) is unchanged from upstream.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart' show SSEModel;
import 'package:http/http.dart' as http;

class PatchedSSEClient {
  static http.Client _client = http.Client();

  /// Whichever StreamController the most recent subscribeToSSE call
  /// returned - what unsubscribeFromSSE() (called with no arguments,
  /// matching the original API) marks as "don't retry" in [_disconnected].
  static StreamController<SSEModel>? _activeController;

  static final Set<StreamController<SSEModel>> _disconnected =
      <StreamController<SSEModel>>{};

  static void _retryConnection(
      {required SSERequestType method,
      required String url,
      required Map<String, String> header,
      required StreamController<SSEModel> streamController,
      Map<String, dynamic>? body}) {
    if (_disconnected.contains(streamController)) return;
    Future.delayed(const Duration(seconds: 5), () {
      if (_disconnected.contains(streamController)) return;
      subscribeToSSE(
        method: method,
        url: url,
        header: header,
        body: body,
        oldStreamController: streamController,
      );
    });
  }

  static Stream<SSEModel> subscribeToSSE(
      {required SSERequestType method,
      required String url,
      required Map<String, String> header,
      StreamController<SSEModel>? oldStreamController,
      Map<String, dynamic>? body}) {
    StreamController<SSEModel> streamController =
        oldStreamController ?? StreamController<SSEModel>();
    _activeController = streamController;
    var lineRegex = RegExp(r'^([^:]*)(?::)?(?: )?(.*)?$');
    var currentSSEModel = SSEModel(data: '', id: '', event: '');
    while (true) {
      try {
        _client = http.Client();
        var request = http.Request(
          method == SSERequestType.GET ? "GET" : "POST",
          Uri.parse(url),
        );

        header.forEach((key, value) {
          request.headers[key] = value;
        });

        if (body != null) {
          request.body = jsonEncode(body);
        }

        Future<http.StreamedResponse> response = _client.send(request);

        response.asStream().listen((data) {
          data.stream
              .transform(const Utf8Decoder())
              .transform(const LineSplitter())
              .listen(
            (dataLine) {
              if (dataLine.isEmpty) {
                streamController.add(currentSSEModel);
                currentSSEModel = SSEModel(data: '', id: '', event: '');
                return;
              }

              Match match = lineRegex.firstMatch(dataLine)!;
              var field = match.group(1);
              if (field!.isEmpty) {
                return;
              }
              var value = '';
              if (field == 'data') {
                value = dataLine.substring(5);
              } else {
                value = match.group(2) ?? '';
              }
              switch (field) {
                case 'event':
                  currentSSEModel.event = value;
                  break;
                case 'data':
                  currentSSEModel.data =
                      '${currentSSEModel.data ?? ''}$value\n';
                  break;
                case 'id':
                  currentSSEModel.id = value;
                  break;
                case 'retry':
                  break;
                default:
                  _retryConnection(
                    method: method,
                    url: url,
                    header: header,
                    streamController: streamController,
                  );
              }
            },
            onError: (e, s) {
              _retryConnection(
                method: method,
                url: url,
                header: header,
                body: body,
                streamController: streamController,
              );
            },
          );
        }, onError: (e, s) {
          _retryConnection(
            method: method,
            url: url,
            header: header,
            body: body,
            streamController: streamController,
          );
        });
      } catch (e) {
        _retryConnection(
          method: method,
          url: url,
          header: header,
          body: body,
          streamController: streamController,
        );
      }
      return streamController.stream;
    }
  }

  /// Marks the current connection as intentionally ended, then closes it -
  /// unlike the original, the resulting error will NOT trigger a retry
  /// (see _retryConnection's guard above), so this actually stops the
  /// connection for good instead of it quietly coming back 5s later under
  /// the identity that was just abandoned.
  static void unsubscribeFromSSE() {
    if (_activeController != null) {
      _disconnected.add(_activeController!);
    }
    _client.close();
  }
}
