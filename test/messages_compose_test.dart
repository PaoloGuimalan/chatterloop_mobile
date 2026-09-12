// Starting a conversation from the Messages list.
//
// Two entry points sit above the list: Write message (a DM, resolved through
// /m/crtc) and Create group (web's CreateGroupChatModal).
//
// The group form is its OWN screen rather than a third mode of
// CreateRealmScreen, even though server-side a group chat is the same
// community_realm row a server is. The two belong to different surfaces - gold
// Servers, blue Messages - and that is the thing most likely to regress if
// somebody later decides the forms look similar enough to merge, so it is
// pinned below.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/views/messages/messages_view.dart';
import 'package:chatterloop_app/views/messages/create_group_chat_view.dart';
import 'package:chatterloop_app/views/servers/create_realm_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_test/flutter_test.dart';

/// Seeds the acting account, which is where the default name comes from.
void _signedInAs(String firstName) {
  appStore.dispatch(DispatchModel(
    setUserAuthT,
    UserAuth(
      true,
      UserAccount('account-1', 'paolo', firstName, '', 'Portes', null, true,
          true, null, null, null, null,
          personalEntityId: 'e-me'),
    ),
  ));
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(360, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(StoreProvider<AppState>(
    store: appStore,
    child: MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: child,
    ),
  ));
  // Twice. These screens fire a request on mount, and dio schedules a
  // zero-duration timer to do it - one pump leaves that timer pending at
  // teardown, which the test binding treats as a leak. The request itself just
  // fails (no plugins here) and the screen handles that; only the timer needs
  // draining.
  await tester.pump();
  await tester.pump(Duration.zero);
}

void main() {
  setUp(() => _signedInAs('Paolo'));
  // Signed out again, so a later test never inherits an acting account.
  tearDown(() => _signedInAs(''));

  group('the messages list', () {
    testWidgets('offers both ways to start a conversation', (tester) async {
      await _pump(tester, const MessagesView());

      expect(find.text('Write message'), findsOneWidget);
      expect(find.text('Create group'), findsOneWidget);
    });

    testWidgets('neither is the secondary one - they share the width',
        (tester) async {
      await _pump(tester, const MessagesView());

      final write = tester.getRect(find.ancestor(
          of: find.text('Write message'), matching: find.byType(CLBtn)));
      final group = tester.getRect(find.ancestor(
          of: find.text('Create group'), matching: find.byType(CLBtn)));

      expect(write.width, group.width);
      // Side by side, not stacked.
      expect(write.top, group.top);
      // Tall enough to read as the screen's primary actions rather than as
      // filter chips above the list - CLBtnSize.md.
      expect(write.height, 38);
      expect(group.height, 38);

      for (final label in ['Write message', 'Create group']) {
        final button = tester.widget<CLBtn>(
            find.ancestor(of: find.text(label), matching: find.byType(CLBtn)));
        // Filled enough to read as a button in LIGHT mode, where plain `soft`
        // is a near-white #E7F0FE - but not the solid variant, which
        // out-shouts the list it sits above.
        expect(button.variant, CLBtnVariant.softStrong);
        // Tall, but quieter in type than the conversation names below - a
        // button louder than the list it introduces is the wrong way round.
        expect(button.labelSize, lessThan(CLType.title));
      }
    });
  });

  group('the create form', () {
    testWidgets('a group chat names itself after you, like web does',
        (tester) async {
      await _pump(tester, const CreateGroupChatScreen());

      // Twice: the screen title and the Create button, both from _noun.
      expect(find.text('Create group chat'), findsNWidgets(2));
      expect(find.text('Name of Group Chat'), findsOneWidget);
      expect(find.text("Paolo's Group Chat"), findsOneWidget);
    });

    testWidgets('a server still says server', (tester) async {
      // The same screen serves all three modes, so the group branch must not
      // have taken the others' copy with it.
      await _pump(tester, const CreateRealmScreen.server());

      expect(find.text('Create server'), findsNWidgets(2));
      expect(find.text('Name of Server'), findsOneWidget);
      expect(find.text("Paolo's Server"), findsOneWidget);
    });

    testWidgets('a channel still says channel', (tester) async {
      await _pump(tester, const CreateRealmScreen.channel(serverId: 's1'));

      expect(find.text('Create channel'), findsNWidgets(2));
      expect(find.text('Name of Channel'), findsOneWidget);
      expect(find.text("Paolo's Channel"), findsOneWidget);
    });

    testWidgets('a nameless account still gets a usable default',
        (tester) async {
      _signedInAs('');
      await _pump(tester, const CreateGroupChatScreen());

      expect(find.text('New Group Chat'), findsOneWidget);
    });

    testWidgets('a group chat answers in blue, a server in gold',
        (tester) async {
      // The whole reason these are two screens. A group chat is reached from
      // Messages and makes a conversation; the gold belongs to Servers.
      await _pump(tester, const CreateGroupChatScreen());
      expect(
        tester
            .widget<CLBtn>(find.ancestor(
                of: find.text('Create group chat'),
                matching: find.byType(CLBtn)))
            .variant,
        CLBtnVariant.primary,
      );
    });

    testWidgets('a server still answers in gold', (tester) async {
      await _pump(tester, const CreateRealmScreen.server());
      expect(
        tester
            .widget<CLBtn>(find.ancestor(
                of: find.text('Create server'), matching: find.byType(CLBtn)))
            .variant,
        CLBtnVariant.gold,
      );
    });

    testWidgets('a server picks members from everyone, public or private',
        (tester) async {
      // Unlike a public channel, which takes its membership from the server
      // and so has nobody to choose.
      expect(
        createRealmMemberSource(isChannel: false, isPrivate: true),
        CreateRealmMemberSource.globalEntities,
      );
      expect(
        createRealmMemberSource(isChannel: true, isPrivate: false),
        CreateRealmMemberSource.none,
      );
    });
  });

  group('softStrong', () {
    /// The rendered fill of a button in the given theme.
    Future<Color?> fill(WidgetTester tester, Brightness brightness,
        CLBtnVariant variant) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(brightness),
        home: Scaffold(
          body: CLBtn(label: 'X', variant: variant, onPressed: () {}),
        ),
      ));
      await tester.pump();
      final box = tester.widget<Container>(find.descendant(
          of: find.byType(CLBtn), matching: find.byType(Container)));
      return (box.decoration as BoxDecoration).color;
    }

    testWidgets('is exactly soft in dark mode', (tester) async {
      // The whole point of the variant: dark already read correctly, so moving
      // a button onto softStrong must not be able to change it.
      expect(
        await fill(tester, Brightness.dark, CLBtnVariant.softStrong),
        await fill(tester, Brightness.dark, CLBtnVariant.soft),
      );
    });

    testWidgets('sits between soft and solid in light mode', (tester) async {
      final soft = await fill(tester, Brightness.light, CLBtnVariant.soft);
      final strong =
          await fill(tester, Brightness.light, CLBtnVariant.softStrong);
      final solid = await fill(tester, Brightness.light, CLBtnVariant.primary);

      // Measured on luminance, so it cannot pass by being merely different:
      // darker than the pale tint, lighter than the solid fill.
      expect(strong!.computeLuminance(), lessThan(soft!.computeLuminance()));
      expect(strong.computeLuminance(), greaterThan(solid!.computeLuminance()));
    });
  });
}
