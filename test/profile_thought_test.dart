// The live thought on a profile or page header (both use ProfileHeader): it
// comes down over the avatar's upper right, its lower edge just above the
// avatar's middle - not floating clear of the face above it - and a longer
// thought grows up over the cover rather than further down the face.
//
// The bubble reads GET /thoughts/?entity_ids= itself, so the user_service
// client is given an adapter that answers from memory. Its interceptors are
// cleared first: they read secure storage, the device token and the app
// version, none of which exist under test.

import 'dart:convert';
import 'dart:typed_data';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/views/moments/thoughts.dart';
import 'package:chatterloop_app/views/profile/widgets/profile_header.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  final String text;

  _Adapter(this.text);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = options.path.endsWith('/thoughts/')
        ? {
            "results": {
              "e-juan": {
                "post_id": "t1",
                "entity_id": "e-juan",
                "content": {"text": text},
                "privacy_status": "public",
              },
            },
          }
        : {"results": {}};
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// The header with Juan's thought, and the rects that matter. [editable] is
/// your own profile: the camera buttons are there.
Future<({Rect header, Rect avatar, Rect bubble, Rect body})> _pumpHeader(
    WidgetTester tester, String thought,
    {bool editable = false}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  ApiClient.userService.dio
    ..interceptors.clear()
    ..httpClientAdapter = _Adapter(thought);
  // A fresh header: pumping the same tree again would keep the loaded thought.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(StoreProvider<AppState>(
    store: appStore,
    child: MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProfileHeader(
            id: 'u-juan',
            entityId: 'e-juan',
            displayName: 'Juan Cruz',
            username: 'juan',
            onChangeAvatar: editable ? () {} : null,
            onChangeCover: editable ? () {} : null,
          ),
        ),
      ),
    ),
  ));
  for (var i = 0;
      i < 20 && find.byType(ThoughtBubble).evaluate().isEmpty;
      i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }

  final bubble = find.byType(ThoughtBubble);
  expect(bubble, findsOneWidget);
  return (
    // The header's own box: the cover plus the avatar's overhang.
    header: tester.getRect(find
        .ancestor(of: find.byType(CLAvatar), matching: find.byType(SizedBox))
        .last),
    avatar: tester.getRect(find.byType(CLAvatar)),
    // Tail included - its bottom is the tip of the last dot.
    bubble: tester.getRect(bubble),
    // The bubble itself, without the tail.
    body: tester.getRect(
        find.descendant(of: bubble, matching: find.byType(Container)).first),
  );
}

void main() {
  testWidgets('the thought comes down over the upper right of the avatar',
      (tester) async {
    final r = await _pumpHeader(tester, "ramen tonight?");

    // Right of the avatar's centre line, over the face rather than beside it.
    expect(r.bubble.left, greaterThan(r.avatar.center.dx));
    expect(r.bubble.left, lessThan(r.avatar.right));

    // The tail ends inside the avatar, just short of its middle ...
    expect(r.bubble.bottom, greaterThan(r.avatar.top + r.avatar.height * 0.3));
    expect(r.bubble.bottom, lessThan(r.avatar.center.dy));
    // ... so the bubble's lower edge is on the face, above the middle.
    expect(r.body.bottom, greaterThan(r.avatar.top));
    expect(r.body.bottom, lessThan(r.avatar.center.dy));

    // Inside the header's box, which is what keeps it tappable.
    expect(r.bubble.top, greaterThanOrEqualTo(r.header.top));
  });

  testWidgets('a longer thought grows up over the cover', (tester) async {
    final short = await _pumpHeader(tester, "ok");
    final long = await _pumpHeader(
        tester, "Chasing dreams and drinking iced coffee all day long");

    expect(long.bubble.bottom, moreOrLessEquals(short.bubble.bottom));
    expect(long.body.top, lessThan(short.body.top));
    expect(long.bubble.top, greaterThanOrEqualTo(long.header.top));
  });

  testWidgets('the change-cover button is clear of even a long thought',
      (tester) async {
    final r = await _pumpHeader(
        tester, "Chasing dreams and drinking iced coffee all day long",
        editable: true);
    final cover = tester.getRect(find.byTooltip("Change cover photo"));

    expect(cover.overlaps(r.bubble), isFalse);
    // Left of the avatar - the thought only ever sits right of its centre.
    expect(cover.right, lessThan(r.avatar.left));
    // Low on the cover, not up in the top strip where the screen's floating
    // back button is (the app bar, which this test does not pump).
    expect(cover.top, greaterThan(r.header.top + 80));
    expect(cover.bottom, lessThan(r.avatar.center.dy));
  });
}
