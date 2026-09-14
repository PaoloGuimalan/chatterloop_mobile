// The avatar's presence marker: which of the three states shows, at which
// sizes, and that the pill still fits the avatars that now qualify for it.
//
// Pumped under the TEST FONT, which renders every glyph as a full em square -
// so a pill that fits here fits real Inter with room to spare, and also
// survives a large accessibility text scale. See redesign_layout_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';

const _me = 'me-entity';

AppState _state(Map<String, PresenceInfo> presence) => AppState(
      // `entityId` is a getter over activeEntity/personalEntityId/id, so the
      // signed-in entity is set through personalEntityId here.
      userAuth: const UserAuth(
        true,
        UserAccount('acc', 'ada', 'Ada', '', 'L', null, true, true, null, null,
            null, null,
            personalEntityId: _me),
      ),
      presence: presence,
    );

Future<void> _pump(
  WidgetTester tester, {
  required String entityId,
  required double size,
  required Map<String, PresenceInfo> presence,
}) async {
  final store = Store<AppState>((s, a) => s, initialState: _state(presence));
  await tester.pumpWidget(StoreProvider<AppState>(
    store: store,
    child: MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: Scaffold(
        body: Center(
            child: CLAvatar(entityId: entityId, name: 'Ada', size: size)),
      ),
    ),
  ));
  await tester.pump();
}

Finder get _dot => find.byWidgetPredicate((w) =>
    w is Container &&
    w.decoration is BoxDecoration &&
    (w.decoration as BoxDecoration).shape == BoxShape.circle &&
    (w.decoration as BoxDecoration).color == CLColors.online);

void main() {
  final justNow = DateTime.now();

  group('which state shows', () {
    testWidgets('online draws the dot and no pill', (tester) async {
      await _pump(tester,
          entityId: 'a',
          size: 40,
          presence: {'a': PresenceInfo(online: true, lastSeen: justNow)});
      expect(_dot, findsOneWidget);
      expect(find.textContaining('m'), findsNothing);
    });

    testWidgets('offline under an hour draws the pill, not the dot',
        (tester) async {
      await _pump(tester, entityId: 'a', size: 40, presence: {
        'a': PresenceInfo(
            online: false,
            lastSeen: DateTime.now().subtract(const Duration(minutes: 42)))
      });
      expect(find.text('42m'), findsOneWidget);
      expect(_dot, findsNothing);
    });

    testWidgets('at sixty minutes the marker goes away entirely',
        (tester) async {
      await _pump(tester, entityId: 'a', size: 40, presence: {
        'a': PresenceInfo(
            online: false,
            lastSeen: DateTime.now().subtract(const Duration(minutes: 61)))
      });
      expect(find.textContaining('m'), findsNothing);
      expect(_dot, findsNothing);
    });

    testWidgets('a moment ago floors at 1m, never 0m', (tester) async {
      await _pump(tester, entityId: 'a', size: 40, presence: {
        'a': PresenceInfo(
            online: false,
            lastSeen: DateTime.now().subtract(const Duration(seconds: 8)))
      });
      expect(find.text('1m'), findsOneWidget);
    });

    testWidgets('an entity nobody reports on shows nothing', (tester) async {
      await _pump(tester, entityId: 'stranger', size: 40, presence: const {});
      expect(_dot, findsNothing);
      expect(find.textContaining('m'), findsNothing);
    });

    testWidgets('you are always active, though never in the presence map',
        (tester) async {
      await _pump(tester, entityId: _me, size: 40, presence: const {});
      expect(_dot, findsOneWidget);
    });
  });

  group('size floor', () {
    testWidgets('a 28px picker avatar gets the pill, and it fits',
        (tester) async {
      await _pump(tester, entityId: 'a', size: 28, presence: {
        'a': PresenceInfo(
            online: false,
            lastSeen: DateTime.now().subtract(const Duration(minutes: 59)))
      });
      // 59m is the widest label the pill ever has to hold.
      expect(find.text('59m'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a 22px stacked face shows the dot but no pill',
        (tester) async {
      await _pump(tester, entityId: 'a', size: 22, presence: {
        'a': PresenceInfo(
            online: false,
            lastSeen: DateTime.now().subtract(const Duration(minutes: 5)))
      });
      expect(find.textContaining('m'), findsNothing);

      await _pump(tester,
          entityId: 'a',
          size: 22,
          presence: {'a': PresenceInfo(online: true, lastSeen: justNow)});
      expect(_dot, findsOneWidget);
    });
  });

  testWidgets('without a StoreProvider the avatar still renders',
      (tester) async {
    // A design primitive must not throw for want of app state - widget tests
    // pump rows bare, and so do thumbnails outside the app shell.
    await tester.pumpWidget(MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: const Scaffold(
        body: Center(child: CLAvatar(entityId: 'a', name: 'Ada', size: 40)),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(CLAvatar), findsOneWidget);
  });
}
