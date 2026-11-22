import 'package:dio/dio.dart';

Future<void> verifyRealmConversation(Dio client, String id) async {
  await client.get('/m/conversationinfo/${Uri.encodeComponent(id)}/group');
}

/// A lifecycle frame is a hint: current API state decides whether to leave.
/// Network errors and delayed frames after restoration do not end a call.
Future<void> checkRealmCallLifecycle(
    {required Future<void> Function() verify,
    required bool Function() isCurrent,
    required Future<void> Function() leave}) async {
  try {
    await verify();
  } catch (error) {
    if (error is DioException &&
        [403, 404, 410].contains(error.response?.statusCode) &&
        isCurrent()) {
      await leave();
    }
  }
}
