// Presence on the conversation info screen.
//
// Pinned because it went missing once already: every avatar on this screen got
// its `entityId` in one sweep except the member rows, which sat after a script
// failure point - so the counterpart at the top showed a marker and the list
// below it showed none, for no reason a reader could see.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_redux/flutter_redux.dart';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/messages_models/conversation_info_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';
import 'package:chatterloop_app/views/messages/conversation_info_view.dart';

const _me = 'me-entity';
const _them = 'them-entity';
const _other = 'other-entity';

UsersContactPreview _person(String entityId, String first) =>
    UsersContactPreview(
      first.toLowerCase(),
      entityId,
      UserFullname(first, 'N/A', 'Lovelace'),
      'none',
      null,
      true,
      false,
    );

ConversationInfoModel _info(List<UsersContactPreview> people, String type) =>
    ConversationInfoModel(
      'conv-1',
      _me,
      const ActionDate('', ''),
      true,
      const [],
      type,
      people,
      const [],
    );

Future<void> _pump(
  WidgetTester tester, {
  required String type,
  required List<UsersContactPreview> people,
  required Map<String, PresenceInfo> presence,
}) async {
  tester.view.physicalSize = const Size(360, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // The global appStore, not a throwaway one: `_counterpart` resolves "who is
  // the other person" through `appStore.state` directly rather than through
  // the context's store, so a private store here would leave it matching
  // against an empty auth and picking YOU as the counterpart.
  appStore.dispatch(DispatchModel(
      setUserAuthT,
      const UserAuth(
        true,
        UserAccount(
            'acc', 'me', 'Me', '', '', null, true, true, null, null, null, null,
            personalEntityId: _me),
      )));
  appStore.dispatch(DispatchModel(setActiveUsersListT, presence));

  await tester.pumpWidget(StoreProvider<AppState>(
    store: appStore,
    child: MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: ConversationInfoScreen(
        info: _info(people, type),
        title: 'Ada Lovelace',
        conversationType: type,
      ),
    ),
  ));
  await tester.pump();
}

/// The "Nm" pill, matched by shape rather than by substring - plain words on
/// this screen ("members", "Me") contain an "m" too.
Finder get _pill => find.byWidgetPredicate(
    (w) => w is Text && w.data != null && RegExp(r'^\d+m$').hasMatch(w.data!));

Finder get _dot => find.byWidgetPredicate((w) =>
    w is Container &&
    w.decoration is BoxDecoration &&
    (w.decoration as BoxDecoration).shape == BoxShape.circle &&
    (w.decoration as BoxDecoration).color == CLColors.online);

void main() {
  testWidgets('a member who is online gets a dot', (tester) async {
    await _pump(
      tester,
      type: 'group',
      people: [_person(_me, 'Me'), _person(_other, 'Ada')],
      presence: {_other: PresenceInfo(online: true, lastSeen: DateTime.now())},
    );
    // Two: Ada's, and your own row - you are always active.
    expect(_dot, findsNWidgets(2));
  });

  testWidgets('a member seen within the hour gets the pill', (tester) async {
    await _pump(
      tester,
      type: 'group',
      people: [_person(_me, 'Me'), _person(_other, 'Ada')],
      presence: {
        _other: PresenceInfo(
            online: false,
            lastSeen: DateTime.now().subtract(const Duration(minutes: 12)))
      },
    );
    expect(_pill, findsOneWidget);
    expect(find.text('12m'), findsOneWidget);
  });

  testWidgets('a member outside your presence scope stays unmarked',
      (tester) async {
    // Group co-members are excluded server-side unless they are also a contact
    // or DM counterpart, so an unknown member simply has no row in the map.
    await _pump(
      tester,
      type: 'group',
      people: [_person(_me, 'Me'), _person(_other, 'Ada')],
      presence: const {},
    );
    // Only your own row, which never depends on the map.
    expect(_dot, findsOneWidget);
    expect(_pill, findsNothing);
  });

  group('the DM header', () {
    testWidgets('reads Active Now, and the avatar carries the dot',
        (tester) async {
      await _pump(
        tester,
        type: 'single',
        people: [_person(_me, 'Me'), _person(_them, 'Ada')],
        presence: {_them: PresenceInfo(online: true, lastSeen: DateTime.now())},
      );
      expect(find.text('Active Now'), findsOneWidget);
      expect(_dot, findsOneWidget);
    });

    testWidgets('reads a relative time once they are offline', (tester) async {
      await _pump(
        tester,
        type: 'single',
        people: [_person(_me, 'Me'), _person(_them, 'Ada')],
        presence: {
          _them: PresenceInfo(
              online: false,
              lastSeen: DateTime.now().subtract(const Duration(minutes: 20)))
        },
      );
      expect(find.textContaining('minutes ago'), findsOneWidget);
      expect(find.text('Active Now'), findsNothing);
      expect(find.text('Recently Active'), findsNothing);
      // A DM shows presence in this slot instead of the kind label.
      expect(find.text('Direct message'), findsNothing);
    });

    testWidgets('a group keeps its kind label rather than presence',
        (tester) async {
      await _pump(
        tester,
        type: 'group',
        people: [_person(_me, 'Me'), _person(_other, 'Ada')],
        presence: const {},
      );
      expect(find.text('Group Chat'), findsOneWidget);
    });
  });
}
