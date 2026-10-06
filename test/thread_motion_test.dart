// The conversation thread's motion and its unread divider:
// - utils/unread_divider.dart (kept in step with the webapp's unreadDivider.ts)
// - ThreadEntry: new rows slide in; a row keeps its element across the
//   pending -> sent swap and only eases its height
// - ComposerStrip: the reply / AI-assist strips close WITH their content
// - UnreadDividerLine: neutral greys, never the accent
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/reusables/widgets/thread_motion.dart';
import 'package:chatterloop_app/core/utils/unread_divider.dart';
import 'package:chatterloop_app/models/messages_models/message_content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = "ent-me";
const _maya = "ent-maya";

MessageContent _message(String id, String sender,
        {List<String>? seeners, String type = "text", bool deleted = false}) =>
    MessageContent.fromJson({
      "messageID": id,
      "conversationID": "c1",
      "sender": sender,
      "content": "message $id",
      "messageType": type,
      "messageDate": "2026-10-06T10:00:00.000Z",
      "seeners": seeners ?? [sender],
      "isDeleted": deleted,
    });

MessageContent _read(String id, [String sender = _maya]) =>
    _message(id, sender, seeners: [sender, _me]);
MessageContent _unread(String id) => _message(id, _maya, seeners: [_maya]);

/// The visit as the conversation records it: newest-first.
UnreadVisit _visitOf(List<MessageContent> oldestFirst) {
  final visit = UnreadVisit();
  recordFirstSight(oldestFirst.reversed, visit, {_me});
  return visit;
}

void main() {
  group('unread divider', () {
    test('sits above the oldest unread message, counting what is below', () {
      final thread = [_read("1"), _read("2", _me), _unread("3"), _unread("4")];
      final visit = _visitOf(thread);
      expect(unreadDividerOf(thread.reversed, visit, false),
          const UnreadDivider("3", 2));
    });

    test('nothing unread, no divider', () {
      final thread = [_read("1"), _read("2")];
      expect(unreadDividerOf(thread.reversed, _visitOf(thread), false), isNull);
    });

    test('your own message counts as read', () {
      final thread = [_unread("1"), _message("2", _me), _unread("3")];
      expect(unreadDividerOf(thread.reversed, _visitOf(thread), false),
          const UnreadDivider("3", 1));
    });

    test('system lines and deleted messages are transparent', () {
      final thread = [
        _read("1"),
        _unread("2"),
        _message("3", _maya, type: "notif"),
        _message("4", _maya, deleted: true),
        _unread("5"),
      ];
      expect(unreadDividerOf(thread.reversed, _visitOf(thread), false),
          const UnreadDivider("2", 2));
    });

    test('stays put once the messages are marked seen', () {
      final thread = [_read("1"), _unread("2"), _unread("3")];
      final visit = _visitOf(thread);
      // The refetch after the seen receipts: same messages, now read.
      final refetched = [_read("1"), _read("2"), _read("3")];
      recordFirstSight(refetched.reversed, visit, {_me});
      expect(unreadDividerOf(refetched.reversed, visit, false),
          const UnreadDivider("2", 2));
    });

    test('a message arriving while you look does not move it', () {
      final thread = [_read("1"), _unread("2")];
      final visit = _visitOf(thread);
      final later = [...thread, _unread("3")];
      recordFirstSight(later.reversed, visit, {_me});
      expect(unreadDividerOf(later.reversed, visit, false),
          const UnreadDivider("2", 1));
    });

    test('an empty conversation does not mark its first live message', () {
      final visit = _visitOf([]);
      final later = [_unread("1")];
      recordFirstSight(later.reversed, visit, {_me});
      expect(unreadDividerOf(later.reversed, visit, false), isNull);
    });

    test('waits for the older page when every loaded message is unread', () {
      final page = [_unread("3"), _unread("4")];
      final visit = _visitOf(page);
      expect(unreadDividerOf(page.reversed, visit, true), isNull);

      // The older page comes in above: judged, and the boundary is there.
      final more = [_read("1"), _unread("2"), ...page];
      recordFirstSight(more.reversed, visit, {_me});
      expect(unreadDividerOf(more.reversed, visit, false),
          const UnreadDivider("2", 3));
    });

    test('a fully loaded, fully unread thread splits at the top', () {
      final thread = [_unread("1"), _unread("2")];
      expect(unreadDividerOf(thread.reversed, _visitOf(thread), false),
          const UnreadDivider("1", 2));
    });

    test('label', () {
      expect(unreadDividerLabel(1), "1 unread message");
      expect(unreadDividerLabel(4), "4 unread messages");
    });
  });

  group('ThreadEntry', () {
    Widget host(List<({String key, double height, bool animateIn})> rows) =>
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              reverse: true,
              itemCount: rows.length,
              findChildIndexCallback: (key) {
                final i = rows.indexWhere(
                    (r) => ValueKey<String>(r.key) == key);
                return i < 0 ? null : i;
              },
              itemBuilder: (context, index) {
                final row = rows[index];
                return ThreadEntry(
                  key: ValueKey<String>(row.key),
                  animateIn: row.animateIn,
                  child: SizedBox(
                      height: row.height, child: Text("row ${row.key}")),
                );
              },
            ),
          ),
        );

    double heightOf(WidgetTester tester, String key) =>
        tester.getSize(find.byKey(ValueKey<String>(key))).height;

    testWidgets('a new row grows in from nothing; old rows do not',
        (tester) async {
      await tester.pumpWidget(host([
        (key: "a", height: 60, animateIn: false),
      ]));
      expect(heightOf(tester, "a"), 60);

      await tester.pumpWidget(host([
        (key: "b", height: 60, animateIn: true),
        (key: "a", height: 60, animateIn: false),
      ]));
      await tester.pump(const Duration(milliseconds: 60));
      final early = heightOf(tester, "b");
      expect(early, greaterThan(0));
      expect(early, lessThan(60));
      // The row it pushed up is untouched.
      expect(heightOf(tester, "a"), 60);

      await tester.pumpAndSettle();
      expect(heightOf(tester, "b"), 60);
    });

    testWidgets('pending -> sent keeps the row and only eases its height',
        (tester) async {
      await tester.pumpWidget(host([
        (key: "p:1", height: 70, animateIn: false),
        (key: "m:0", height: 40, animateIn: false),
      ]));
      final before = tester.element(find.byKey(const ValueKey<String>("p:1")));

      // The sent copy takes the pending's key and lands one place up; the
      // settled pending is left drawing nothing below it.
      await tester.pumpWidget(host([
        (key: "settled:1", height: 0, animateIn: false),
        (key: "p:1", height: 50, animateIn: false),
        (key: "m:0", height: 40, animateIn: false),
      ]));
      final after = tester.element(find.byKey(const ValueKey<String>("p:1")));
      expect(identical(before, after), isTrue,
          reason: "the same row, not a new one arriving");

      await tester.pump(const Duration(milliseconds: 60));
      final mid = heightOf(tester, "p:1");
      expect(mid, lessThan(70));
      expect(mid, greaterThan(50));
      await tester.pumpAndSettle();
      expect(heightOf(tester, "p:1"), 50);
    });

    testWidgets('reduced motion: no entrance', (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: ThreadEntry(
              key: const ValueKey<String>("x"),
              animateIn: true,
              child: const SizedBox(height: 60),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(heightOf(tester, "x"), 60);
    });
  });

  group('ComposerStrip', () {
    Widget host(bool open, String text) => MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ComposerStrip(
                open: open,
                height: 80,
                child: open
                    ? TextButton(onPressed: () {}, child: Text(text))
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        );

    testWidgets('opens smoothly to its height', (tester) async {
      await tester.pumpWidget(host(false, ""));
      expect(find.byType(TextButton), findsNothing);

      await tester.pumpWidget(host(true, "Replying to Maya"));
      await tester.pump(const Duration(milliseconds: 80));
      final mid = tester.getSize(find.byType(ComposerStrip)).height;
      expect(mid, greaterThan(0));
      expect(mid, lessThan(80));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(ComposerStrip)).height, 80);
    });

    testWidgets('closes WITH its content, and cannot be tapped meanwhile',
        (tester) async {
      await tester.pumpWidget(host(true, "Replying to Maya"));
      await tester.pumpAndSettle();

      // isReplying clears at once: the new child is empty.
      await tester.pumpWidget(host(false, ""));
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text("Replying to Maya"), findsOneWidget);
      final mid = tester.getSize(find.byType(ComposerStrip)).height;
      expect(mid, greaterThan(0));
      expect(mid, lessThan(80));
      final ignoring = tester.widget<IgnorePointer>(find.descendant(
          of: find.byType(ComposerStrip),
          matching: find.byType(IgnorePointer)).first);
      expect(ignoring.ignoring, isTrue);

      await tester.pumpAndSettle();
      expect(find.text("Replying to Maya"), findsNothing);
      expect(tester.getSize(find.byType(ComposerStrip)).height, 0);
    });
  });

  group('UnreadDividerLine', () {
    Future<Color?> labelColor(WidgetTester tester, Brightness b) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(b),
        home: const Scaffold(
            body: UnreadDividerLine(label: "2 unread messages")),
      ));
      // MaterialApp animates a theme change.
      await tester.pumpAndSettle();
      return tester.widget<Text>(find.text("2 unread messages")).style?.color;
    }

    testWidgets('grey on light, the text colour on dark - never the accent',
        (tester) async {
      final light = await labelColor(tester, Brightness.light);
      expect(light, CLPalette.light.text2);
      expect(light, isNot(CLPalette.light.brand));

      final dark = await labelColor(tester, Brightness.dark);
      expect(dark, CLPalette.dark.text);
      expect(dark, isNot(CLPalette.dark.brand));
    });
  });
}
