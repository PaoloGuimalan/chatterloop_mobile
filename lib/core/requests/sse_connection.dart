import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/utils/content_validator.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/core/utils/jwt_tools.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// import 'package:http/http.dart' as http;

class SseConnection {
  final storage = FlutterSecureStorage();

  void initializeConnection() async {
    String? token = await storage.read(key: 'token');
    String ssetoken = JwtTools()
        .createJwt({"token": token, "type": "notifications"}, secretKey);
    String url = '${Endpoints().apiUrl}${Endpoints().sseRoute}$ssetoken';

    ContentValidator().printer(url);

    SSEClient.subscribeToSSE(
        method: SSERequestType.GET,
        url: url,
        header: {"Accept": "text/event-stream"}).listen((event) {
      ContentValidator().printer({"event": event.event, "data": event.data});
    });
  }

  void closeConnection() {
    SSEClient.unsubscribeFromSSE();
  }
}