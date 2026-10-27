import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/reusables/widgets/user_app_shortcuts.dart';
import 'package:chatterloop_app/views/servers/server_channels_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('private server and Apps previews ${brightness.name}',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({'token': 'fixture-token'});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = FontLoader('Inter');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        font.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
      }
      await font.load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
      var pending = false;
      final mainDio = ApiClient.instance.dio,
          userDio = ApiClient.userService.dio;
      final mainInterceptor = InterceptorsWrapper(
          onRequest: (request, handler) => handler.reject(DioException(
              requestOptions: request,
              response: Response(requestOptions: request, statusCode: 401))));
      final userInterceptor = InterceptorsWrapper(
          onRequest: (request, handler) => handler.resolve(
                  Response(requestOptions: request, statusCode: 200, data: {
                'data': {
                  'id': 'private-server',
                  'entity': 'server-entity',
                  'name': 'Private server',
                  'type': 'server',
                  'is_private': true,
                  'is_member': false,
                  'request_pending': pending
                }
              })));
      mainDio.interceptors.insert(0, mainInterceptor);
      userDio.interceptors.insert(0, userInterceptor);
      addTearDown(() {
        mainDio.interceptors.remove(mainInterceptor);
        userDio.interceptors.remove(userInterceptor);
      });
      const root = ValueKey('polish-preview');
      for (final state in [false, true]) {
        pending = state;
        await tester.pumpWidget(RepaintBoundary(
            key: root,
            child: MaterialApp(
                key: ValueKey(state),
                debugShowCheckedModeBanner: false,
                theme: buildCLTheme(brightness),
                home: const Scaffold(
                    body: ServerChannelsPane(
                        serverId: 'private-server',
                        serverName: 'Private server')))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
            find.byKey(root),
            matchesGoldenFile(
                'goldens/server_${state ? 'pending' : 'request'}_${brightness.name}.png'));
      }
      await tester.pumpWidget(RepaintBoundary(
          key: root,
          child: MaterialApp(
              key: const ValueKey('apps'),
              debugShowCheckedModeBanner: false,
              theme: buildCLTheme(brightness),
              home: Scaffold(
                  body: SafeArea(
                      child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: UserAppShortcuts(onSettings: () {})))))));
      await tester.pumpAndSettle();
      expect(find.text('Chatterloop Extension'), findsNothing);
      await expectLater(find.byKey(root),
          matchesGoldenFile('goldens/community_apps_${brightness.name}.png'));
    });
  }
}
