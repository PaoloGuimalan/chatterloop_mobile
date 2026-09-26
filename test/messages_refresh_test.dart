// Pull-to-refresh on Messages: the whole screen is one scroll view, so the pull
// can start anywhere (even on the actions at the top), its spinner comes down
// from the top of the screen, and it reloads the Thoughts rail along with the
// conversations - the rail otherwise only reloads when your own thought
// changes.
//
// Both clients get an adapter that answers from memory. Their interceptors are
// cleared first: they read secure storage, the device token and the app
// version, none of which exist under test.

import 'dart:convert';
import 'dart:typed_data';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/views/messages/messages_view.dart';
import 'package:chatterloop_app/views/moments/thoughts.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  final Map<String, dynamic> Function() answer;
  int calls = 0;

  _Adapter(this.answer);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    return ResponseBody.fromString(jsonEncode(answer()), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _rail(String text) => {
      "mine": null,
      "results": [
        {
          "post_id": "t1",
          "entity_id": "e-juan",
          "content": {"text": text},
          "privacy_status": "public",
          "author": {
            "id": "e-juan",
            "type": "user",
            "display_name": "Juan Cruz",
            "name": "Juan Cruz",
          },
        },
      ],
      "suggestions": [],
    };

void main() {
  testWidgets('a pull from the top reloads the list and the thoughts',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var juansThought = "ramen tonight?";
    final list = _Adapter(() => {
          "result": {"items": [], "total": 0, "next": false},
        });
    final rail = _Adapter(() => _rail(juansThought));
    ApiClient.instance.dio
      ..interceptors.clear()
      ..httpClientAdapter = list;
    ApiClient.userService.dio
      ..interceptors.clear()
      ..httpClientAdapter = rail;

    await tester.pumpWidget(StoreProvider<AppState>(
      store: appStore,
      child: MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const MessagesView(),
      ),
    ));
    for (var i = 0;
        i < 20 &&
            (find.text("No conversations yet").evaluate().isEmpty ||
                find.text("ramen tonight?").evaluate().isEmpty);
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text("ramen tonight?"), findsOneWidget);
    final listCalls = list.calls;
    final railCalls = rail.calls;

    // Juan changes his thought; only a refresh can show it.
    juansThought = "movie later?";

    // Starting on the actions, above the rail - not on the list.
    await tester.fling(find.text("Write message"), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The spinner comes down from the top of the screen: it starts above the
    // rail, where it used to start under it with the list.
    final spinner = tester.getRect(find.byType(RefreshProgressIndicator));
    final railTop = tester.getRect(find.byType(ThoughtsRailView)).top;
    expect(spinner.top, lessThan(railTop));

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(list.calls, listCalls + 1);
    expect(rail.calls, railCalls + 1);
    expect(find.text("movie later?"), findsOneWidget);
    expect(find.text("ramen tonight?"), findsNothing);
    expect(find.byType(RefreshProgressIndicator), findsNothing);
  });
}
