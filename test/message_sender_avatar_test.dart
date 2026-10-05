// Sender avatars beside group and channel messages.
//
// A run of consecutive messages from one sender draws as one block: avatar
// and name on its first message, the rest indented under them (see
// utils/message_runs, which the webapp mirrors in hooks/messageRuns.ts). Your
// own messages and DMs carry neither.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/reusables/widgets/message_content_widget.dart';
import 'package:chatterloop_app/core/utils/message_runs.dart';
import 'package:chatterloop_app/core/utils/system_entity.dart';
import 'package:chatterloop_app/models/messages_models/message_content_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_test/flutter_test.dart';

MessageContent _message(
  String sender, {
  String content = "hello",
  String date = "2026-10-05T10:00:00.000Z",
  String type = "text",
}) =>
    MessageContent.fromJson({
      "messageID": "m-$sender-$date",
      "conversationID": "c1",
      "sender": sender,
      "content": content,
      "messageType": type,
      "messageDate": date,
    });

const _maya = UsersContactPreview(
  "maya",
  "ent-maya",
  UserFullname("Maya", "", "Reyes"),
  "none",
  null,
  true,
  false,
  entityType: "user",
);

Finder _profileTarget(String label) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == label);

void main() {
  group('startsSenderRun', () {
    final maya = _message("ent-maya", date: "2026-10-05T10:00:00.000Z");

    test('the oldest loaded message opens a run', () {
      expect(startsSenderRun(maya, null), isTrue);
    });

    test('the same sender continues the run', () {
      final next = _message("ent-maya", date: "2026-10-05T10:01:00.000Z");
      expect(startsSenderRun(next, maya), isFalse);
    });

    test('a different sender opens a run', () {
      final jon = _message("ent-jon", date: "2026-10-05T10:01:00.000Z");
      expect(startsSenderRun(jon, maya), isTrue);
    });

    test('a system line between two messages breaks the run', () {
      final joined = _message("ent-maya",
          type: "notif", date: "2026-10-05T10:01:00.000Z");
      final next = _message("ent-maya", date: "2026-10-05T10:02:00.000Z");
      expect(startsSenderRun(next, joined), isTrue);
    });

    test('a pause longer than the gap opens a run, the gap itself does not',
        () {
      final atGap = _message("ent-maya", date: "2026-10-05T10:10:00.000Z");
      final pastGap = _message("ent-maya", date: "2026-10-05T10:10:01.000Z");
      expect(startsSenderRun(atGap, maya), isFalse);
      expect(startsSenderRun(pastGap, maya), isTrue);
    });

    test('an unreadable date falls back to grouping by sender', () {
      final odd = _message("ent-maya", date: "yesterday");
      expect(startsSenderRun(odd, maya), isFalse);
    });

    test('a pending send above never continues a run', () {
      expect(startsSenderRun(maya, Object()), isTrue);
    });
  });

  group('sender avatar', () {
    Future<void> pump(
      WidgetTester tester,
      MessageContent message, {
      bool startsRun = true,
      bool single = false,
      bool channel = false,
      String name = "Maya",
      UsersContactPreview? member = _maya,
    }) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(StoreProvider<AppState>(
        store: appStore,
        child: MaterialApp(
          theme: buildCLTheme(Brightness.light),
          home: Builder(
            builder: (context) => CLAccent(
              color: channel ? cl(context).gold : cl(context).brand,
              child: Scaffold(
                body: SingleChildScrollView(
                  // The conversation list's own side padding.
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: MessageContentWidget(
                    messageContent: message,
                    startsRun: startsRun,
                    currentUserID: "me",
                    onPressed: (_, __) {},
                    resolveSenderName: (_) => name,
                    resolveSenderMember: (_) => member,
                    isSingleConversation: single,
                    conversationID: "c1",
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
    }


    testWidgets('the first message of a run carries the avatar and name',
        (tester) async {
      await pump(tester, _message("ent-maya"));
      expect(find.byType(CLAvatar), findsOneWidget);
      expect(find.text("Maya"), findsOneWidget);
      expect(_profileTarget("Open Maya's profile"), findsOneWidget);
    });

    testWidgets('server channels get them too', (tester) async {
      await pump(tester, _message("ent-maya"), channel: true);
      expect(find.byType(CLAvatar), findsOneWidget);
      expect(find.text("Maya"), findsOneWidget);
    });

    testWidgets('the rest of the run is indented under the first',
        (tester) async {
      await pump(tester, _message("ent-maya"));
      final firstLeft = tester.getTopLeft(find.text("hello")).dx;

      await pump(tester, _message("ent-maya"), startsRun: false);
      expect(find.byType(CLAvatar), findsNothing);
      expect(find.text("Maya"), findsNothing);
      expect(tester.getTopLeft(find.text("hello")).dx, firstLeft);
    });

    testWidgets('the avatar sits level with the name', (tester) async {
      await pump(tester, _message("ent-maya"));
      expect(tester.getTopLeft(find.byType(CLAvatar)).dy,
          moreOrLessEquals(tester.getTopLeft(find.text("Maya")).dy, epsilon: 2));
    });

    testWidgets('DMs carry neither', (tester) async {
      await pump(tester, _message("ent-maya"), single: true);
      expect(find.byType(CLAvatar), findsNothing);
      expect(find.text("Maya"), findsNothing);
    });

    testWidgets('your own messages carry neither', (tester) async {
      await pump(tester, _message("me"));
      expect(find.byType(CLAvatar), findsNothing);
    });

    testWidgets('a system line takes no avatar column', (tester) async {
      await pump(tester, _message("ent-maya", type: "notif"));
      expect(find.byType(CLAvatar), findsNothing);
    });

    testWidgets('System gets the bot avatar and no tap target', (tester) async {
      await pump(tester, _message(systemBotEntityId),
          name: systemBotDisplayName, member: null);
      final avatar = tester.widget<CLAvatar>(find.byType(CLAvatar));
      expect(avatar.kind, 'bot');
      expect(_profileTarget("Open System's profile"), findsNothing);
    });

    testWidgets('a long name and a full-width bubble fit a 360px phone',
        (tester) async {
      await pump(
        tester,
        _message("ent-maya", content: "word " * 80),
        name: "Maximiliana Alexandra Montgomery-Fitzwilliam of the Valley",
      );
      expect(tester.takeException(), isNull);
    });
  });
}
