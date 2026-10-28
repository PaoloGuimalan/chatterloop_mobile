import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/requests/sse_connection.dart';
import 'package:chatterloop_app/views/notifications/notifications_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_test/flutter_test.dart';

String overview(String message) {
  final empty = {'items': <dynamic>[], 'total': 0, 'unread': 0, 'next': false};
  final payload = {
    'activity': {
      'items': [
        {
          'notificationID': message,
          'type': 'community_admin_activity',
          'content': {
            'headline': 'Community activity preview',
            'details': message
          },
          'date': {'date': '2026-10-28T00:00:00.000Z'},
          'isRead': false,
        }
      ],
      'total': 1,
      'unread': 1,
      'next': false,
    },
    'connections': empty,
    'system': empty,
  };
  return JwtCodec.sign(payload);
}

void main() {
  testWidgets('a delayed overview cannot replace the latest community preview',
      (tester) async {
    final dio = ApiClient.instance.dio;
    final saved = dio.interceptors.toList();
    dio.interceptors.clear();
    addTearDown(() {
      dio.interceptors.clear();
      dio.interceptors.addAll(saved);
    });
    final pending = <Completer<String>>[];
    final paths = <String>[];
    dio.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) async {
      paths.add(request.path);
      if (request.path.contains('grouped/overview')) {
        final response = Completer<String>();
        pending.add(response);
        handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: {'status': true, 'result': await response.future}));
      } else {
        handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: {'status': true, 'totalunread': 0}));
      }
    }));
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const NotificationsView()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(pending.length, 1, reason: paths.toString());
    eventBus
        .fire(SSEModel(event: 'community_admin_preview_changed', data: '{}'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(pending.length, 2);
    pending[1].complete(overview('Latest preview'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Latest preview', findRichText: true),
        findsOneWidget);
    pending[0].complete(overview('Older preview'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Latest preview', findRichText: true),
        findsOneWidget);
    expect(
        find.textContaining('Older preview', findRichText: true), findsNothing);
  });
}
