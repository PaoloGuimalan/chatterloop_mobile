import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('community delivery retry uses the same upload without reading the file',
      () async {
    final dio = ApiClient.instance.dio;
    final previous = dio.interceptors.toList();
    final requests = <Map<String, dynamic>>[];
    dio.interceptors.clear();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(Map<String, dynamic>.from(options.data));
      handler.resolve(Response(
        requestOptions: options,
        statusCode: requests.length == 1 ? 503 : 200,
        data: {
          'status': requests.length > 1,
          'message': 'Delivery incomplete. Retry this upload.',
        },
      ));
    }));
    addTearDown(() {
      dio.interceptors.clear();
      dio.interceptors.addAll(previous);
    });

    final api = ProfileApi();
    Future<bool> retry() => api.updateRealmMediaRequest(
          realmId: 'garden',
          realmType: 'community',
          mediaType: 'cover_photo',
          filePath: '/nonexistent/file.png',
          uploadId: 'upload-one',
        );
    expect(await retry(), isFalse);
    expect(await retry(), isTrue);
    expect(requests.map((request) => request['uploadID']),
        ['upload-one', 'upload-one']);
    expect(
        requests.every((request) => request['realm_id'] == 'garden'), isTrue);
  });
}
