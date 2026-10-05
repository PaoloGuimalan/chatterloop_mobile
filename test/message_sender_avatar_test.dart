// Sender avatars, seen faces and typing faces in group and channel threads.
//
// A run of consecutive messages from one sender draws as one block: the name
// over its first message and the avatar beside its last, every message
// indented to line up (see utils/message_runs, which the webapp mirrors in
// hooks/messageRuns.ts). Your own messages and DMs carry neither. Each
// member's "seen" face sits under the newest message they have read and
// slides down as they read further; the typing bubble carries who is typing.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/reusables/loaders/typing_loader.dart';
import 'package:chatterloop_app/core/reusables/widgets/message_content_widget.dart';
import 'package:chatterloop_app/core/reusables/widgets/seen_faces.dart';
import 'package:chatterloop_app/core/utils/message_runs.dart';
import 'package:chatterloop_app/core/utils/system_entity.dart';
import 'package:chatterloop_app/core/utils/typing_label.dart';
import 'package:chatterloop_app/models/messages_models/message_content_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_test/flutter_test.dart';

MessageContent _message(
  String sender, {
  String content = "hello",
  String date = "2026-10-05T10:00:00.000Z",
  String type = "text",
  List<String>? seeners,
  List<Map<String, dynamic>>? reactions,
}) =>
    MessageContent.fromJson({
      "messageID": "m-$sender-$date",
      "conversationID": "c1",
      "sender": sender,
      "content": content,
      "messageType": type,
      "messageDate": date,
      "seeners": seeners ?? [sender],
      if (reactions != null) "reactions": reactions,
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

  group('endsSenderRun', () {
    final maya = _message("ent-maya", date: "2026-10-05T10:00:00.000Z");

    test('the newest loaded message closes its run', () {
      expect(endsSenderRun(maya, null), isTrue);
    });

    test('a newer message from the same sender keeps the run going', () {
      final next = _message("ent-maya", date: "2026-10-05T10:01:00.000Z");
      expect(endsSenderRun(maya, next), isFalse);
    });

    test('someone else, a pause, or a pending send below closes it', () {
      expect(
          endsSenderRun(
              maya, _message("ent-jon", date: "2026-10-05T10:01:00.000Z")),
          isTrue);
      expect(
          endsSenderRun(
              maya, _message("ent-maya", date: "2026-10-05T10:11:00.000Z")),
          isTrue);
      expect(endsSenderRun(maya, Object()), isTrue);
    });
  });

  group('seenFaceAnchors', () {
    test('every seener but you sits under the newest message they have seen',
        () {
      final thread = [
        _message("ent-maya",
            date: "2026-10-05T10:00:00.000Z",
            seeners: ["ent-maya", "me", "ent-jon", "ent-ana"]),
        _message("me",
            date: "2026-10-05T10:01:00.000Z",
            seeners: ["me", "ent-jon", "ent-maya"]),
        _message("ent-maya",
            date: "2026-10-05T10:02:00.000Z", seeners: ["ent-maya", "me"]),
      ];
      final anchors = seenFaceAnchors(thread, ["me"]);
      // Maya sent the newest message and has seen it - she shows there too.
      expect(anchors[thread[2].messageID], ["ent-maya"]);
      // Jon read up to my message; Ana only the first one.
      expect(anchors[thread[1].messageID], ["ent-jon"]);
      expect(anchors[thread[0].messageID], ["ent-ana"]);
      expect(anchors.values.expand((ids) => ids), isNot(contains("me")));
    });

    test("a sender missing from an old message's seeners still counts", () {
      final thread = [_message("ent-jon", seeners: [])];
      expect(seenFaceAnchors(thread, ["me"])[thread[0].messageID],
          ["ent-jon"]);
    });

    test('system lines are never an anchor', () {
      final thread = [
        _message("ent-maya", seeners: ["ent-maya", "ent-jon"]),
        _message("me",
            type: "notif",
            date: "2026-10-05T10:01:00.000Z",
            seeners: ["ent-jon"]),
      ];
      final anchors = seenFaceAnchors(thread, ["me"]);
      expect(anchors[thread[1].messageID], isNull);
      expect(anchors[thread[0].messageID], ["ent-maya", "ent-jon"]);
    });

    test('none of your own ids gets a face', () {
      final thread = [
        _message("ent-maya", seeners: ["ent-maya", "page-me", "human-me"]),
      ];
      expect(
          seenFaceAnchors(thread, ["page-me", "human-me"])[thread[0].messageID],
          ["ent-maya"]);
    });

    test('seens recorded by account id fold onto the member, once', () {
      final thread = [
        _message("ent-jon",
            date: "2026-10-05T10:00:00.000Z",
            seeners: ["ent-jon", "acct-kai", "acct-me"]),
        _message("ent-maya",
            date: "2026-10-05T10:01:00.000Z",
            seeners: ["ent-maya", "ent-kai"]),
      ];
      const accounts = {"acct-kai": "ent-kai", "acct-me": "me"};
      final anchors = seenFaceAnchors(thread, ["me", "acct-me"],
          canonical: (id) => accounts[id] ?? id);
      expect(anchors[thread[1].messageID], ["ent-maya", "ent-kai"]);
      expect(anchors[thread[0].messageID], ["ent-jon"]);
    });
  });

  group('typing label', () {
    IsTypingMetaData typer(String name, {String type = "user"}) =>
        IsTypingMetaData("acc", "c1",
            entityID: "e-$name", displayName: name, entityType: type);

    test('a DM row says only "is typing"', () {
      expect(typingLabel([typer("Maya Reyes")], isGroupLike: false),
          "is typing…");
    });

    test('a group row names one typer by first name', () {
      expect(typingLabel([typer("Maya Reyes")], isGroupLike: true),
          "Maya is typing…");
    });

    test('a page or bot keeps its whole name', () {
      expect(
          typingLabel([typer("Neon Systems", type: "realm")],
              isGroupLike: true),
          "Neon Systems is typing…");
    });

    test('several typers are "multiple people"', () {
      expect(
          typingLabel([typer("Maya Reyes"), typer("Jon Park")],
              isGroupLike: true),
          "multiple people are typing…");
    });

    test('an older server\'s nameless ping stays "someone"', () {
      expect(
          typingLabel([IsTypingMetaData("acc", "c1")], isGroupLike: true),
          "someone is typing…");
    });
  });

  group('IsTypingMetaData', () {
    test('reads the new identity fields and keys by entity', () {
      final typer = IsTypingMetaData.fromJson({
        "userID": "acc-1",
        "conversationID": "c1",
        "entityID": "ent-1",
        "displayName": "Maya Reyes",
        "profile": "https://example.test/maya.png",
        "entityType": "user",
      });
      expect(typer.key, "ent-1|c1");
      expect(typer.displayName, "Maya Reyes");
      expect(typer.profile, "https://example.test/maya.png");
    });

    test('an older server\'s ping keys by account and leaves the rest null',
        () {
      final typer =
          IsTypingMetaData.fromJson({"userID": "acc-1", "conversationID": "c1"});
      expect(typer.key, "acc-1|c1");
      expect(typer.entityID, isNull);
      expect(typer.profile, isNull);
    });
  });

  group('sender avatar', () {
    Future<void> pump(
      WidgetTester tester,
      MessageContent message, {
      bool startsRun = true,
      bool endsRun = true,
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
                    endsRun: endsRun,
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

    testWidgets('the first message of a run carries the name, not the avatar',
        (tester) async {
      await pump(tester, _message("ent-maya"), endsRun: false);
      expect(find.text("Maya"), findsOneWidget);
      expect(find.byType(CLAvatar), findsNothing);
    });

    testWidgets('the last message of a run carries the avatar',
        (tester) async {
      await pump(tester, _message("ent-maya"), startsRun: false);
      expect(find.byType(CLAvatar), findsOneWidget);
      expect(find.text("Maya"), findsNothing);
      expect(_profileTarget("Open Maya's profile"), findsOneWidget);
    });

    testWidgets('a one-message run carries both', (tester) async {
      await pump(tester, _message("ent-maya"));
      expect(find.byType(CLAvatar), findsOneWidget);
      expect(find.text("Maya"), findsOneWidget);
    });

    testWidgets('server channels get them too', (tester) async {
      await pump(tester, _message("ent-maya"), channel: true);
      expect(find.byType(CLAvatar), findsOneWidget);
      expect(find.text("Maya"), findsOneWidget);
    });

    testWidgets('every message in the run lines up', (tester) async {
      await pump(tester, _message("ent-maya"));
      final lastLeft = tester.getTopLeft(find.text("hello")).dx;

      await pump(tester, _message("ent-maya"),
          startsRun: false, endsRun: false);
      expect(find.byType(CLAvatar), findsNothing);
      expect(tester.getTopLeft(find.text("hello")).dx, lastLeft);
    });

    testWidgets('the avatar sits level with the bottom of the bubble',
        (tester) async {
      await pump(tester, _message("ent-maya"), startsRun: false);
      final bubble = find
          .ancestor(of: find.text("hello"), matching: find.byType(Container))
          .first;
      expect(tester.getBottomLeft(find.byType(CLAvatar)).dy,
          moreOrLessEquals(tester.getBottomLeft(bubble).dy, epsilon: 2));
    });

    testWidgets('a reactions pill does not push the avatar below the bubble',
        (tester) async {
      await pump(
          tester,
          _message("ent-maya", reactions: [
            {"entityID": "ent-jon", "userID": "acc-jon", "emoji": "👍"}
          ]),
          startsRun: false);
      final bubble = find
          .ancestor(of: find.text("hello"), matching: find.byType(Container))
          .first;
      expect(tester.getBottomLeft(find.byType(CLAvatar)).dy,
          moreOrLessEquals(tester.getBottomLeft(bubble).dy, epsilon: 2));
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

  group('seen faces', () {
    const jon = SeenFace(entityId: "ent-jon", name: "Jon Park");

    /// Two messages stacked one above the other; [jonUnder] says which one
    /// carries Jon's face.
    Widget thread(SeenFaceTracker tracker, String jonUnder) => MaterialApp(
          theme: buildCLTheme(Brightness.light),
          home: Scaffold(
            body: Column(
              children: [
                const SizedBox(height: 100),
                SeenFacesRow(
                    messageId: "older",
                    faces: jonUnder == "older" ? const [jon] : const [],
                    tracker: tracker),
                const SizedBox(height: 120),
                SeenFacesRow(
                    messageId: "newer",
                    faces: jonUnder == "newer" ? const [jon] : const [],
                    tracker: tracker),
              ],
            ),
          ),
        );

    testWidgets('a face slides down to the newer message it was read up to',
        (tester) async {
      final tracker = SeenFaceTracker();
      await tester.pumpWidget(thread(tracker, "older"));
      await tester.pumpAndSettle();
      final olderTop = tester.getTopLeft(find.byType(CLAvatar)).dy;

      await tester.pumpWidget(thread(tracker, "newer"));
      await tester.pump(); // first frame: measured, still hidden
      await tester.pump(); // slide starts from where it was
      final startTop = tester.getTopLeft(find.byType(CLAvatar)).dy;
      await tester.pump(const Duration(milliseconds: 150));
      final midTop = tester.getTopLeft(find.byType(CLAvatar)).dy;
      await tester.pumpAndSettle();
      final endTop = tester.getTopLeft(find.byType(CLAvatar)).dy;

      expect(startTop, moreOrLessEquals(olderTop, epsilon: 2));
      expect(midTop, greaterThan(startTop));
      expect(midTop, lessThan(endTop));
      expect(endTop, greaterThan(olderTop + 100));
    });

    testWidgets('a face seen for the first time pops in where it belongs',
        (tester) async {
      final tracker = SeenFaceTracker();
      await tester.pumpWidget(thread(tracker, "newer"));
      await tester.pump(const Duration(milliseconds: 50));
      final opacity = tester.widget<Opacity>(find
          .ancestor(of: find.byType(CLAvatar), matching: find.byType(Opacity))
          .first);
      expect(opacity.opacity, lessThan(1));
      await tester.pumpAndSettle();
      expect(find.byType(CLAvatar), findsOneWidget);
    });

    testWidgets('more than five faces collapse into +N', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(
          body: SeenFacesRow(
            messageId: "m",
            tracker: SeenFaceTracker(),
            faces: [
              for (var i = 0; i < 7; i++)
                SeenFace(entityId: "e$i", name: "Member $i")
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(CLAvatar), findsNWidgets(5));
      expect(find.text("+2"), findsOneWidget);
    });
  });

  group('typing faces', () {
    TypingFace face(String id) =>
        TypingFace(key: id, name: "Person $id", colorKey: id);

    /// A group message and the typing bubble under it, laid out the way the
    /// conversation screen does: the list's 10px inset on both.
    Future<void> pump(WidgetTester tester, List<TypingFace> faces) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(StoreProvider<AppState>(
        store: appStore,
        child: MaterialApp(
          theme: buildCLTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: MessageContentWidget(
                      messageContent: _message("ent-maya"),
                      currentUserID: "me",
                      onPressed: (_, __) {},
                      resolveSenderName: (_) => "Maya",
                      resolveSenderMember: (_) => _maya,
                      isSingleConversation: false,
                      conversationID: "c1",
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: TypingIndicator(
                        isTyping: true, p: cl(context), faces: faces),
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
    }

    Finder typingAvatars() => find.descendant(
        of: find.byType(TypingIndicator), matching: find.byType(CLAvatar));

    testWidgets('one typer shows one face at the run avatar size',
        (tester) async {
      await pump(tester, [face("a")]);
      expect(tester.widget<CLAvatar>(typingAvatars()).size, 32);
    });

    testWidgets('two and three typers cluster inside one avatar square',
        (tester) async {
      await pump(tester, [face("a"), face("b")]);
      expect(typingAvatars(), findsNWidgets(2));
      await pump(tester, [face("a"), face("b"), face("c")]);
      expect(typingAvatars(), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('past three, the last slot says how many more',
        (tester) async {
      await pump(tester, [face("a"), face("b"), face("c"), face("d")]);
      expect(typingAvatars(), findsNWidgets(2));
      expect(find.text("+2"), findsOneWidget);
    });

    testWidgets('the typing bubble lines up with the message bubbles',
        (tester) async {
      for (var count = 1; count <= 5; count++) {
        await pump(tester, [for (var i = 0; i < count; i++) face("f$i")]);
        final messageBubble = find
            .ancestor(of: find.text("hello"), matching: find.byType(Container))
            .first;
        final typingBubble = find.descendant(
            of: find.byType(TypingIndicator),
            matching: find.byType(AnimatedContainer));
        expect(tester.getTopLeft(typingBubble).dx,
            moreOrLessEquals(tester.getTopLeft(messageBubble).dx, epsilon: 1),
            reason: "$count typing");
      }
    });

    testWidgets('a DM keeps the bare bubble', (tester) async {
      await pump(tester, const []);
      expect(typingAvatars(), findsNothing);
    });
  });
}
