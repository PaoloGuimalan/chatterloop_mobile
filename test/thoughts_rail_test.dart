// The Thoughts rail's geometry: a thought comes down over its avatar, and the
// rail keeps no empty band above the avatars of people without one.
//
// The rail reads GET /thoughts/rail/ itself, so the user_service client is
// given an adapter that answers with a fixed rail. Its interceptors are
// cleared first: they read secure storage, the device token and the app
// version, none of which exist under test.

import 'dart:convert';
import 'dart:typed_data';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/views/moments/thoughts.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redux/redux.dart';

class _RailAdapter implements HttpClientAdapter {
  final Map<String, dynamic> body;

  _RailAdapter(this.body);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(jsonEncode(body), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _entity(String id, String name) =>
    {"id": id, "type": "user", "display_name": name, "name": name};

Map<String, dynamic> _thought(
        String id, String entity, String name, String text) =>
    {
      "post_id": id,
      "entity_id": entity,
      "content": {"text": text},
      "privacy_status": "public",
      "author": _entity(entity, name),
    };

Future<void> _pumpRail(WidgetTester tester, Map<String, dynamic> rail) async {
  final dio = ApiClient.userService.dio;
  dio.interceptors.clear();
  dio.httpClientAdapter = _RailAdapter(rail);
  // A fresh rail: pumping the same tree again would keep the loaded state.
  await tester.pumpWidget(const SizedBox());

  final store = Store<AppState>((s, a) => s, initialState: AppState());
  await tester.pumpWidget(StoreProvider<AppState>(
    store: store,
    child: MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: const Scaffold(
        body: Align(alignment: Alignment.topLeft, child: ThoughtsRailView()),
      ),
    ),
  ));
  // The load runs on the test's fake clock: advance it until the rail lands.
  for (var i = 0; i < 20 && find.byType(CLAvatar).evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Map<String, dynamic> _rail(String juansThought) => {
      "mine": null,
      "results": [_thought("t1", "e-juan", "Juan Cruz", juansThought)],
      "suggestions": [_entity("e-marco", "Marco Reyes")],
    };

void main() {
  testWidgets('a thought is pinned over the top of its avatar', (tester) async {
    await _pumpRail(tester, _rail("ramen tonight?"));

    final rail = tester.getRect(find.byType(SingleChildScrollView).first);
    final bubbles = find.byType(ThoughtBubble);
    // Yours ("Share a thought") and Juan's. Marco has none.
    expect(bubbles, findsNWidgets(2));
    final avatars = find.byType(CLAvatar);
    expect(avatars, findsNWidgets(3));

    for (var i = 0; i < 2; i++) {
      final bubble = tester.getRect(bubbles.at(i));
      final avatar = tester.getRect(avatars.at(i));
      expect(bubble.top, moreOrLessEquals(rail.top),
          reason: 'thought $i starts at the top of the rail');
      expect(bubble.bottom, greaterThan(avatar.top),
          reason: 'thought $i comes down over its avatar');
    }

    // Every avatar on one line, the same fixed room above each - with or
    // without a thought over it.
    for (var i = 0; i < 3; i++) {
      expect(
          tester.getRect(avatars.at(i)).top - rail.top, moreOrLessEquals(28));
    }
  });

  testWidgets('a long thought grows down, not the rail up', (tester) async {
    await _pumpRail(tester, _rail("ok"));
    final shortRail = tester.getRect(find.byType(SingleChildScrollView).first);
    final shortBubble = tester.getRect(find.byType(ThoughtBubble).at(1));

    await _pumpRail(
        tester, _rail("Chasing dreams and drinking iced coffee all day long"));
    final longRail = tester.getRect(find.byType(SingleChildScrollView).first);
    final longBubble = tester.getRect(find.byType(ThoughtBubble).at(1));
    final avatar = tester.getRect(find.byType(CLAvatar).at(1));

    expect(longRail.height, moreOrLessEquals(shortRail.height));
    expect(longBubble.top, moreOrLessEquals(shortBubble.top));
    expect(longBubble.bottom, greaterThan(shortBubble.bottom));
    // Still within the avatar: three lines at most.
    expect(longBubble.bottom, lessThan(avatar.bottom));
  });
}
