// ignore_for_file: use_build_context_synchronously
import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/utils/content_validator.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/core/utils/jwt_tools.dart';
import 'package:chatterloop_app/core/utils/sse_events.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// import 'package:http/http.dart' as http;

final EventBus eventBus = EventBus();

class SseConnection {
  final storage = FlutterSecureStorage();

  void initializeConnection() async {
    SSEClient.unsubscribeFromSSE();
    String? token = await storage.read(key: 'token');
    String ssetoken = JwtTools()
        .createJwt({"token": token, "type": "notifications"}, secretKey);
    String url = '${Endpoints().apiUrl}${Endpoints().sseRoute}$ssetoken';

    ContentValidator().printer(url);

    SSEClient.subscribeToSSE(
        method: SSERequestType.GET,
        url: url,
        header: {"Accept": "text/event-stream"}).listen((event) {
      eventBus.fire(event);
      SseEvents().listen(event, null, true);
      // ContentValidator().printer({"event": event.event, "data": event.data});
    });
  }

  void closeConnection() {
    SSEClient.unsubscribeFromSSE();
  }
}
