import 'package:chatterloop_app/core/calls/realm_call_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

void main() {
  test('realm call availability uses ID-based conversation membership endpoint',
      () async {
    final dio = Dio();
    String? path;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (req, handler) {
      path = req.path;
      handler.resolve(Response(requestOptions: req, data: {'status': true}));
    }));
    await verifyRealmConversation(dio, 'voice-id');
    expect(path, '/m/conversationinfo/voice-id/group');
  });
  test(
      'only unavailable current realm calls leave; stale events and outages preserve calls',
      () async {
    var leaves = 0;
    final denied = DioException(
        requestOptions: RequestOptions(),
        response: Response(requestOptions: RequestOptions(), statusCode: 404));
    Future<void> check() async => throw denied;
    await checkRealmCallLifecycle(
        verify: check,
        isCurrent: () => true,
        leave: () async {
          leaves++;
        });
    expect(leaves, 1);
    await checkRealmCallLifecycle(
        verify: check,
        isCurrent: () => false,
        leave: () async {
          leaves++;
        });
    expect(leaves, 1);
    await checkRealmCallLifecycle(
        verify: () async {},
        isCurrent: () => true,
        leave: () async {
          leaves++;
        });
    expect(leaves, 1);
    await checkRealmCallLifecycle(
        verify: () async => throw Exception('offline'),
        isCurrent: () => true,
        leave: () async {
          leaves++;
        });
    expect(leaves, 1);
  });
}
