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

  test('read requests preserve the displayed revision through model updates',
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
    NotificationV2 item(String type, dynamic revision) =>
        NotificationV2.fromJson({
          'notificationID': type,
          'type': type,
          'isRead': false,
          'activity_revision': revision,
        }).copyWith(referenceStatus: true);

    await NotificationsApi().readNotificationsRequest(notifications: [
      item('community_admin_activity', 3),
      item('community_admin_activity', -1),
      item('community_admin_activity', '4'),
      item('follow', 5),
    ]);
    expect(requests.single.data, {
      'community_summaries': [
        {'notificationID': 'community_admin_activity', 'activity_revision': 3},
      ]
    });
    expect(requests.single.path, '/u/readnotifications');
  });
}
