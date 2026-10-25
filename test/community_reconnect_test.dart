import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:chatterloop_app/core/requests/patched_sse_client.dart';

void main() {
  testWidgets('explicit disconnect cancels a pending reconnect timer',
      (tester) async {
    var attempts = 0;
    final client = PatchedSSEClient(
        clientFactory: () => MockClient.streaming((request, _) async {
              attempts++;
              return http.StreamedResponse(const Stream.empty(), 200);
            }));
    final subscription = client.subscribe(
        method: SSERequestType.GET,
        url: 'https://fixture.invalid/events',
        header: {}).listen((_) {});
    await tester.pump();
    expect(attempts, 1);
    client.unsubscribe();
    subscription.cancel();
    await tester.pump();
    // The test binding also rejects pending timers after disposal.
  });
  for (final failed in [false, true]) {
    testWidgets(
        'reconnect revalidates access after ${failed ? 'error' : 'closed stream'}',
        (tester) async {
      var attempts = 0;
      var reconnected = 0;
      final keepAlive = StreamController<List<int>>();
      final client = PatchedSSEClient(
          clientFactory: () => MockClient.streaming((request, _) async {
                attempts++;
                final stream = attempts > 1
                    ? keepAlive.stream
                    : failed
                        ? Stream<List<int>>.error(StateError('offline'))
                        : const Stream<List<int>>.empty();
                return http.StreamedResponse(stream, 200);
              }));
      final subscription = client
          .subscribe(
              method: SSERequestType.GET,
              url: 'https://fixture.invalid/events',
              header: {},
              onReconnect: () => reconnected++)
          .listen((_) {});
      await tester.pump();
      expect(attempts, 1);
      expect(reconnected, 0);
      await tester.pump(const Duration(seconds: 5));
      expect(attempts, 2);
      expect(reconnected, 1);
      client.unsubscribe();
      subscription.cancel();
      keepAlive.close();
      await tester.pump();
    });
  }
}
