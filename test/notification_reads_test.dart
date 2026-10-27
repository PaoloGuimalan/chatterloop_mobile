import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/notifications_api.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_v2_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('read response retains the badge count for newer unread activity',
      () async {
    final dio = ApiClient.instance.dio;
    final saved = dio.interceptors.toList();
    dio.interceptors.clear();
    addTearDown(() {
      dio.interceptors.clear();
      dio.interceptors.addAll(saved);
    });
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(
        requestOptions: request,
        statusCode: 200,
        data: {'status': true, 'totalunread': 1, 'message': 'Read'},
      ));
    }));

    expect(await NotificationsApi().readNotificationsRequest(), 1);
  });

  test('read requests use immutable preview IDs without additional schema fields',
      () async {
    final dio = ApiClient.instance.dio;
    final saved = dio.interceptors.toList();
    dio.interceptors.clear();
    addTearDown(() {
      dio.interceptors.clear();
      dio.interceptors.addAll(saved);
    });
    final requests = <RequestOptions>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: {'status': true, 'totalunread': 0}));
    }));
    NotificationV2 item(String id, String type) => NotificationV2.fromJson({
          'notificationID': id,
          'type': type,
          'isRead': false,
        }).copyWith(referenceStatus: true);

    await NotificationsApi().readNotificationsRequest(notifications: [
      item('preview-one', 'community_admin_activity'),
      item('preview-two', 'community_admin_activity'),
      item('', 'community_admin_activity'),
      item('ordinary', 'follow'),
    ]);
    expect(requests.single.data, {
      'community_summaries': [
        {'notificationID': 'preview-one'},
        {'notificationID': 'preview-two'},
      ]
    });
    expect(requests.single.path, '/u/readnotifications');
  });
}
