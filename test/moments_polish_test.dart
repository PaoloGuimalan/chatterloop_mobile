// Moments polish (designs 1a-1f): the moment viewer, your moment's viewers
// sheet, a thought opened from the rail - plus the empty Moments board, the
// full-screen media viewer covering the whole app, and gallery picks.
//
// The user_service client answers from memory. Its interceptors are cleared
// first: they read secure storage, the device token and the app version, none
// of which exist under test.

import 'dart:convert';
import 'dart:typed_data';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/reusables/widgets/media_viewer.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_composer.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_reactions.dart';
import 'package:chatterloop_app/models/post_models/ephemeral_models.dart';
import 'package:chatterloop_app/models/post_models/newsfeed_models.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/core/utils/gallery_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:chatterloop_app/views/moments/moment_viewer_screen.dart';
import 'package:chatterloop_app/views/moments/moments_strip.dart';
import 'package:chatterloop_app/views/moments/thoughts.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers user_service from [routes] (first path match wins) and records
/// every request.
class _Api implements HttpClientAdapter {
  final Map<String, Object> routes;

  /// Answers slowed down, by path - to hold a screen in its loading state.
  final Map<String, Duration> delays;
  final List<RequestOptions> seen = [];

  _Api(this.routes, {this.delays = const {}});

  int count(String method, String pathPart) =>
      seen.where((r) => r.method == method && r.path.contains(pathPart)).length;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    seen.add(options);
    for (final delay in delays.entries) {
      if (options.path.contains(delay.key)) await Future.delayed(delay.value);
    }
    final body = routes.entries
        .firstWhere((e) => options.path.contains(e.key),
            orElse: () => const MapEntry('', <String, dynamic>{}))
        .value;
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

_Api _serve(Map<String, Object> routes,
    {Map<String, Duration> delays = const {}}) {
  final api = _Api(routes, delays: delays);
  ApiClient.userService.dio
    ..interceptors.clear()
    ..httpClientAdapter = api;
  return api;
}

const _emojis = [
  Emoji(emojiId: "e1", title: "love", content: "❤️", theme: "", priority: 1),
  Emoji(emojiId: "e2", title: "haha", content: "😂", theme: "", priority: 2),
  Emoji(emojiId: "e3", title: "wow", content: "😮", theme: "", priority: 3),
  Emoji(emojiId: "e4", title: "sad", content: "😢", theme: "", priority: 4),
  Emoji(emojiId: "e5", title: "fire", content: "🔥", theme: "", priority: 5),
  Emoji(emojiId: "e6", title: "like", content: "👍", theme: "", priority: 6),
];

Map<String, dynamic> _entity(String id, String first, String last) => {
      "id": id,
      "type": "user",
      "details": {"first_name": first, "last_name": last, "username": first},
    };

Map<String, dynamic> _moment(String entityId, String first, String last,
        {String caption = "Golden hour on the pier"}) =>
    {
      "post_id": "m1",
      "caption": caption,
      "privacy_status": "public",
      "entity": _entity(entityId, first, last),
      "date_posted": DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 3))
          .toIso8601String(),
      "expires_at": DateTime.now()
          .toUtc()
          .add(const Duration(hours: 21))
          .toIso8601String(),
      "seen": false,
    };

void _signedInAs(String entityId) {
  appStore.dispatch(DispatchModel(
    setUserAuthT,
    UserAuth(
      true,
      UserAccount('account-1', 'paolo', 'Paolo', '', 'Portes', null, true, true,
          null, null, null, null,
          personalEntityId: entityId),
    ),
  ));
}

Future<void> _pump(WidgetTester tester, Widget home,
    {Brightness brightness = Brightness.light}) async {
  tester.view.physicalSize = const Size(360, 760);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(StoreProvider<AppState>(
    store: appStore,
    child: MaterialApp(theme: buildCLTheme(brightness), home: home),
  ));
}

/// A few frames for the requests to land - well short of a moment's 6s.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() => ReactionPalette.seed(_emojis));
  tearDown(() => _signedInAs(''));

  group("someone else's moment", () {
    testWidgets('reactions wait behind one button; one reaction, then locked',
        (tester) async {
      _signedInAs('e-me');
      final api = _serve({
        '/moments/entity/': {
          "results": [_moment('e-maya', 'Maya', 'Santos')]
        },
        '/moments/tray/': {"results": []},
        '/reaction': {},
      });
      await _pump(tester, const MomentViewerScreen(entityId: 'e-maya'));
      await _settle(tester);

      expect(find.text('Maya Santos'), findsOneWidget);
      expect(find.text('Golden hour on the pier'), findsOneWidget);
      expect(find.text('Replies go to your chat with Maya.'), findsOneWidget);
      // Tucked away until asked for.
      expect(find.text('🔥'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Reactions'));
      await tester.pump();
      expect(find.text('🔥'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('React 🔥'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('You reacted 🔥 · Maya will see it'), findsOneWidget);

      // Locked: another one does nothing.
      await tester.tap(find.bySemanticsLabel('React ❤️'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('You reacted 🔥 · Maya will see it'), findsOneWidget);
      expect(api.count('POST', '/reaction'), 1);

      // It tucks itself away once you have seen it land.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.bySemanticsLabel('React ❤️'), findsNothing);
    });

    testWidgets('send sits inside the reply field', (tester) async {
      _signedInAs('e-me');
      _serve({
        '/moments/entity/': {
          "results": [_moment('e-maya', 'Maya', 'Santos')]
        },
        '/moments/tray/': {"results": []},
      });
      await _pump(tester, const MomentViewerScreen(entityId: 'e-maya'));
      await _settle(tester);

      final field = tester.getRect(find.byType(TextField));
      final send = tester.getRect(find.bySemanticsLabel('Send reply'));
      final pill = tester.getRect(find
          .ancestor(of: find.byType(TextField), matching: find.byType(Row))
          .first);
      expect(send.left, greaterThan(field.right - 1));
      expect(send.right, lessThanOrEqualTo(pill.right + 0.5));
      expect(find.text('Reply to Maya…'), findsOneWidget);
    });
  });

  group('your moment', () {
    final viewers = {
      "totals": {"views": 24, "reactions": 5, "replies": 2},
      "results": [
        {
          "entity": _entity('e-jonas', 'Jonas', 'Reyes'),
          "viewed_at": DateTime.now().toUtc().toIso8601String(),
          "reaction": {"emoji": "❤️"},
          "replied": true,
        },
      ],
      "next": null,
    };

    testWidgets('the viewers pill: faces, count, reactions and replies',
        (tester) async {
      _signedInAs('e-me');
      _serve({
        '/moments/entity/': {
          "results": [_moment('e-me', 'Paolo', 'Portes', caption: "Sunday")]
        },
        '/moments/tray/': {"results": []},
        '/viewers/': viewers,
      });
      await _pump(tester, const MomentViewerScreen(entityId: 'e-me'));
      await _settle(tester);

      expect(find.text('Your moment'), findsOneWidget);
      expect(find.text('Public'), findsOneWidget);
      expect(find.text('24 viewers'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
    });

    testWidgets('the pill holds placeholders while its viewers load',
        (tester) async {
      _signedInAs('e-me');
      _serve({
        '/moments/entity/': {
          "results": [_moment('e-me', 'Paolo', 'Portes', caption: "Sunday")]
        },
        '/moments/tray/': {"results": []},
        '/viewers/': viewers,
      }, delays: {
        '/viewers/': const Duration(milliseconds: 800)
      });
      await _pump(tester, const MomentViewerScreen(entityId: 'e-me'));
      await _settle(tester);

      // Loading - and it says so, rather than claiming nobody has looked.
      expect(find.bySemanticsLabel(RegExp('Loading viewers')), findsOneWidget);
      expect(find.text('No viewers yet'), findsNothing);
      expect(find.text('24 viewers'), findsNothing);

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('24 viewers'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Loading viewers')), findsNothing);
    });

    testWidgets('the sheet opens at its full height and stays there',
        (tester) async {
      _signedInAs('e-me');
      final api = _serve({
        '/moments/entity/': {
          "results": [_moment('e-me', 'Paolo', 'Portes', caption: "Sunday")]
        },
        '/moments/tray/': {"results": []},
        '/viewers/': viewers,
      });
      await _pump(tester, const MomentViewerScreen(entityId: 'e-me'));
      await _settle(tester);

      await tester.tap(find.bySemanticsLabel(RegExp('^Viewers')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final sheet = tester.getRect(find.byType(BottomSheet));
      expect(sheet.height, closeTo(760 * 0.8, 1));

      // The totals are the filters.
      expect(find.text('Views'), findsOneWidget);
      expect(find.text('Reactions'), findsOneWidget);
      expect(find.text('Replies'), findsOneWidget);
      expect(find.text('Who can see this'), findsOneWidget);
      expect(find.text('Allow replies and reactions'), findsOneWidget);
      expect(find.text('Archive'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      await tester.tap(find.text('Reactions'));
      await tester.pump();
      await _settle(tester);
      expect(
          api.seen.any((r) =>
              r.path.contains('/viewers/') &&
              r.queryParameters['filter'] == 'reacted'),
          isTrue);
      expect(tester.getRect(find.byType(BottomSheet)).height, sheet.height,
          reason: 'switching filters never resizes it');
      expect(find.text('Reacted · Replied · Just now'), findsOneWidget);
    });
  });

  group('a thought, opened', () {
    Thought thought() => Thought.fromJson({
          "post_id": "t1",
          "entity_id": "e-maya",
          "content": {"text": "Beach this weekend?", "mood": "chilling"},
          "privacy_status": "public",
          "date_posted": DateTime.now().toUtc().toIso8601String(),
          "expires_at": DateTime.now()
              .toUtc()
              .add(const Duration(hours: 21))
              .toIso8601String(),
          "author": _entity('e-maya', 'Maya', 'Santos'),
        });

    Future<_Api> open(WidgetTester tester, Brightness brightness) async {
      final api = _serve({'/reaction': {}});
      await _pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    showThoughtDetailSheet(context, thought: thought()),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        brightness: brightness,
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return api;
    }

    for (final brightness in Brightness.values) {
      testWidgets('the bubble sits over its author ($brightness)',
          (tester) async {
        await open(tester, brightness);

        final bubble = tester.getRect(find.text('Beach this weekend?'));
        final name = tester.getRect(find.text('Maya Santos'));
        expect(bubble.bottom, lessThan(name.top));
        expect(bubble.center.dx, closeTo(name.center.dx, 1));
        expect(find.text('Chilling'), findsOneWidget);
      });
    }

    testWidgets('one reaction, then the rest are locked', (tester) async {
      final api = await open(tester, Brightness.light);

      await tester.tap(find.bySemanticsLabel('React 😂'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('You reacted 😂 · Maya will see it'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('React 👍'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('You reacted 😂 · Maya will see it'), findsOneWidget);
      expect(api.count('POST', '/reaction'), 1);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('the Moments board', () {
    testWidgets('nothing to watch: a card fills the row beside Add Moment',
        (tester) async {
      _serve({
        '/moments/tray/': {"results": []}
      });
      await _pump(
          tester,
          const Scaffold(
              body:
                  Padding(padding: EdgeInsets.all(14), child: MomentsStrip())));
      await _settle(tester);

      expect(find.text('Add Moment'), findsOneWidget);
      expect(find.text('No moments to view'), findsOneWidget);
      final card = tester.getRect(find
          .ancestor(
              of: find.text('No moments to view'),
              matching: find.byType(Container))
          .first);
      // To the right edge, not a line of text floating in the gap.
      expect(card.right, closeTo(360 - 14 - 2, 1));
      expect(card.height, closeTo(150, 1));
    });

    testWidgets('Add Moment is white on the light feed', (tester) async {
      _serve({
        '/moments/tray/': {"results": []}
      });
      await _pump(tester, const Scaffold(body: MomentsStrip()));
      await _settle(tester);

      final tile = tester.widget<Container>(find
          .ancestor(
              of: find.text('Add Moment'), matching: find.byType(Container))
          .first);
      final color = (tile.decoration as BoxDecoration).color;
      expect(color, CLColors.surfaceLight);
    });
  });

  testWidgets('full-screen media covers the whole app, not just its tab',
      (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: Scaffold(
        body: Column(children: [
          // A tab: its own navigator, as a shell branch has.
          Expanded(
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => openMediaViewer(
                        context,
                        [
                          MediaViewerItem(
                              source: 'https://example.invalid/a.jpg',
                              isVideo: false),
                        ],
                        0,
                        canDownload: false),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 60, child: Text('TAB BAR')),
        ]),
      ),
    ));
    expect(find.text('TAB BAR'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(MediaViewerScreen), findsOneWidget);
    expect(find.text('TAB BAR'), findsNothing,
        reason: 'covered by the viewer, not left showing beside it');
  });

  test('picking media opens the photo picker, not the file browser', () {
    final before = ImagePickerPlatform.instance;
    addTearDown(() => ImagePickerPlatform.instance = before);
    final android = ImagePickerAndroid();
    ImagePickerPlatform.instance = android;
    expect(android.useAndroidPhotoPicker, isFalse,
        reason: "the plugin's own default - the file browser");

    useGalleryPicker();

    expect(android.useAndroidPhotoPicker, isTrue);
  });

  test('a gallery pick is a video by its type, whatever it is named', () {
    expect(
        PendingMedia(
                path: '/x/1000123',
                name: '1000123',
                size: 1,
                mimeType: 'video/mp4')
            .isVideo,
        isTrue);
    expect(
        PendingMedia(
                path: '/x/a.jpg',
                name: 'a.jpg',
                size: 1,
                mimeType: 'image/jpeg')
            .isVideo,
        isFalse);
    expect(
        PendingMedia(path: '/x/b.MOV', name: 'b.MOV', size: 1).isVideo, isTrue);
  });
}
