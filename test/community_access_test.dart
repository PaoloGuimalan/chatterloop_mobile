import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/search_cards.dart';
import 'package:chatterloop_app/models/user_models/search_v2_models.dart';

void main() {
  testWidgets('cached community search content clears when access is revoked',
      (tester) async {
    final fixtures = jsonDecode(
        File('test/fixtures/community_stage1.json').readAsStringSync());
    final post = Map<String, dynamic>.from(fixtures['anonymous_owner']);
    post['caption'] = 'Private cached caption';
    var allowed = true;
    final dio = ApiClient.userService.dio;
    final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      if (allowed) {
        handler.resolve(
            Response(requestOptions: request, statusCode: 200, data: post));
      } else {
        handler.reject(DioException(
            requestOptions: request,
            response: Response(requestOptions: request, statusCode: 404)));
      }
    });
    dio.interceptors.insert(0, interceptor);
    addTearDown(() => dio.interceptors.remove(interceptor));
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(
            body: SearchContentCard(
                post: SearchPostResult.fromJson(post), onOpen: (_) {}))));
    await tester.pumpAndSettle();
    expect(find.text('Private cached caption'), findsOneWidget);
    allowed = false;
    communityChanges.value++;
    await tester.pumpAndSettle();
    expect(find.text('Private cached caption'), findsNothing);
  });
}
