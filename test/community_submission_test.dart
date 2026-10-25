import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:dio/dio.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_composer.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';

typedef Upload = ({
  String url,
  String mediaType,
  String fileName,
  String? fileId
});

class WaitingUpload extends ProfileApi {
  final result = Completer<Upload?>();
  bool started = false;
  @override
  Future<Upload?> uploadMediaRequest(String path, String mediaType,
      {required String action,
      Map<String, dynamic>? context,
      String? authToken,
      void Function(double fraction)? onProgress}) {
    started = true;
    return result.future;
  }
}

class FixturePicker extends ImagePickerPlatform {
  final String path;
  FixturePicker(this.path);
  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) async =>
      [XFile(path)];
}

void main() {
  testWidgets('dismissed composer never publishes after its upload completes',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'token': 'fixture-token'});
    final file = File('assets/images/default.png');
    final previousPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = FixturePicker(file.path);
    addTearDown(() => ImagePickerPlatform.instance = previousPicker);
    final upload = WaitingUpload();
    var published = 0;
    final node = ApiClient.instance.dio;
    final user = ApiClient.userService.dio;
    final nodeInterceptor = InterceptorsWrapper(onRequest: (request, handler) {
      published++;
      handler.resolve(Response(
          requestOptions: request, statusCode: 200, data: {'status': true}));
    });
    final userInterceptor = InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'status': true,
        'result': {
          'realm_id': 'club',
          'entity_id': 'club-entity',
          'name': 'Club',
          'is_member': true
        }
      }));
    });
    node.interceptors.insert(0, nodeInterceptor);
    user.interceptors.insert(0, userInterceptor);
    addTearDown(() {
      node.interceptors.remove(nodeInterceptor);
      user.interceptors.remove(userInterceptor);
    });
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showCreatePostSheet(context,
                        withMedia: true,
                        profileApi: upload,
                        community: const Community(
                            realmId: 'club',
                            entityId: 'club-entity',
                            name: 'Club',
                            isMember: true)),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.runAsync(() async {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(upload.started, true);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    upload.result.complete((
      url: '/uploaded.png',
      mediaType: 'image/png',
      fileName: 'photo.png',
      fileId: 'file'
    ));
    await tester.pumpAndSettle();
    expect(published, 0);
  });
}
