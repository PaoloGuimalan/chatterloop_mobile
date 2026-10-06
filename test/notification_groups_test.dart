// Grouped notifications: the parsing (grouped and ungrouped answers make the
// same rows) and CLGroupedNotificationRow - the sentence, where a tap goes,
// and expanding/collapsing. What may group is the server's call
// (server/reusables/models/notificationgroups.js, with its own tests).
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/reusables/widgets/notification_row.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_v2_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

int _seq = 0;

Map<String, dynamic> _sender(String id, String name) => {
      "entity_id": id,
      "type": "user",
      "display_name": name,
      "handle": id,
      "profile": null,
      "is_verified": false,
    };

Map<String, dynamic> _notification(String type, Map<String, dynamic> from,
        {String? route, bool read = false}) =>
    {
      "notificationID": "NTF_${++_seq}",
      "referenceID": "ref$_seq",
      "referenceStatus": true,
      "fromUserID": from["entity_id"],
      "fromUser": from,
      "content": {"headline": "h", "details": "did a thing."},
      "date": {"date": "2026-10-06T10:00:00Z", "time": null},
      "type": type,
      "isRead": read,
      "redirects": route == null
          ? []
          : [
              // The test host is not iOS, so this build reads "android".
              {"platform": "android", "type": "post", "route": route},
            ],
      "actions": [],
    };

final _maya = _sender("maya", "Maya Reyes");
final _leo = _sender("leo", "Leo Cruz");
final _ana = _sender("ana", "Ana Lim");

NotificationGroup _reactions() => NotificationGroup.fromJson({
      "key": "g-react",
      "count": 4,
      "unread": 4,
      "actorCount": 3,
      "action": "reacted to your post",
      "items": [
        _notification("post_reaction", _maya, route: "/post/p1?anchor=c1"),
        _notification("post_reaction", _leo, route: "/post/p1"),
        _notification("post_reaction", _ana, route: "/post/p1"),
        _notification("post_reaction", _maya, route: "/post/p1"),
      ],
    });

NotificationGroup _follows() => NotificationGroup.fromJson({
      "key": "g-follow",
      "count": 2,
      "unread": 0,
      "actorCount": 2,
      "action": "started following you",
      "items": [
        _notification("follow", _leo, route: "/user/leo", read: true),
        _notification("follow", _ana, route: "/user/ana", read: true),
      ],
    });

final _juan = _sender("juan", "Juan Lazy");

/// One person's connection rows, as the server's people family groups them:
/// an open contact request (its buttons are its own) and an accept.
NotificationGroup _juanConnections({bool answered = false}) =>
    NotificationGroup.fromJson({
      "key": "g-juan",
      "count": 2,
      "unread": 2,
      "actorCount": 1,
      "action": "sent you a contact request and accepted your request",
      "items": [
        {
          ..._notification("contact_request", _juan, route: "/user/juan"),
          "referenceStatus": answered,
        },
        _notification("info_contact_accept", _juan, route: "/user/juan"),
      ],
    });

String _connectionSentence(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((t) => t.text.toPlainText())
    .firstWhere((t) => t.contains("contact request"));

Widget _host(Widget child, {double width = 360}) => MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );

String _sentence(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((t) => t.text.toPlainText())
    .firstWhere((t) => t.contains("reacted") || t.contains("following"));

void main() {
  group('parsing', () {
    test('a grouped answer keeps its groups', () {
      final data = NotificationSectionData.fromJson({
        "groups": [
          {
            "key": "g1",
            "count": 2,
            "unread": 1,
            "actorCount": 2,
            "action": "reacted to your post",
            "items": [
              _notification("post_reaction", _maya),
              _notification("post_reaction", _leo, read: true),
            ],
          },
        ],
        "total": 1,
        "unread": 1,
        "next": false,
      });
      expect(data.groups, hasLength(1));
      expect(data.groups.first.isGroup, isTrue);
      expect(data.groups.first.items, hasLength(2));
      expect(data.groups.first.action, "reacted to your post");
    });

    test('an ungrouped answer becomes groups of one', () {
      final data = NotificationSectionData.fromJson({
        "items": [
          _notification("post_reaction", _maya),
          _notification("poke", _leo, read: true),
        ],
        "total": 2,
        "unread": 1,
        "next": true,
      });
      expect(data.groups, hasLength(2));
      expect(data.groups.every((g) => !g.isGroup), isTrue);
      expect(data.groups.first.unread, 1);
      expect(data.groups.last.unread, 0);
      expect(data.hasNext, isTrue);
    });

    test('mapItems reaches the rows inside a group', () {
      final read = _reactions().mapItems((n) => n.copyWith(isRead: true),
          zeroUnread: true);
      expect(read.unread, 0);
      expect(read.items.every((n) => n.isRead), isTrue);
    });
  });

  group('CLGroupedNotificationRow', () {
    testWidgets('names the people and the action', (tester) async {
      await tester.pumpWidget(_host(CLGroupedNotificationRow(
        group: _reactions(),
        expanded: false,
        onToggle: (_) {},
        busy: (_) => false,
        onAccept: (_) {},
        onDecline: (_) {},
      )));
      expect(_sentence(tester),
          "Maya Reyes, Leo Cruz and 1 other reacted to your post");
      // Four notifications from three people.
      expect(find.textContaining("4 notifications"), findsOneWidget);
    });

    testWidgets('two people read "A and B"', (tester) async {
      await tester.pumpWidget(_host(CLGroupedNotificationRow(
        group: _follows(),
        expanded: false,
        onToggle: (_) {},
        busy: (_) => false,
        onAccept: (_) {},
        onDecline: (_) {},
      )));
      expect(_sentence(tester), "Leo Cruz and Ana Lim started following you");
    });

    testWidgets('a group about one post opens the post', (tester) async {
      NotificationV2? opened;
      String? toggled;
      final group = _reactions();
      await tester.pumpWidget(_host(CLGroupedNotificationRow(
        group: group,
        expanded: false,
        onToggle: (key) => toggled = key,
        busy: (_) => false,
        onAccept: (_) {},
        onDecline: (_) {},
        onOpen: (n) => opened = n,
      )));
      await tester.tap(find.textContaining("reacted to your post"));
      await tester.pump();
      expect(opened?.notificationID, group.items.first.notificationID,
          reason: "the newest one - it carries the anchor to scroll to");
      expect(toggled, isNull);
    });

    testWidgets('a group about different people expands instead',
        (tester) async {
      NotificationV2? opened;
      String? toggled;
      await tester.pumpWidget(_host(CLGroupedNotificationRow(
        group: _follows(),
        expanded: false,
        onToggle: (key) => toggled = key,
        busy: (_) => false,
        onAccept: (_) {},
        onDecline: (_) {},
        onOpen: (n) => opened = n,
      )));
      await tester.tap(find.textContaining("started following you"));
      await tester.pump();
      expect(opened, isNull);
      expect(toggled, "g-follow");
    });

    testWidgets('the count pill toggles, and the members come and go smoothly',
        (tester) async {
      var expanded = false;
      await tester.pumpWidget(StatefulBuilder(
        builder: (context, setState) => _host(CLGroupedNotificationRow(
          group: _reactions(),
          expanded: expanded,
          onToggle: (_) => setState(() => expanded = !expanded),
          busy: (_) => false,
          onAccept: (_) {},
          onDecline: (_) {},
          onOpen: (_) {},
        )),
      ));
      expect(find.byType(CLNotificationRow), findsNothing);

      await tester.tap(find.text("4"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(CLNotificationRow), findsNWidgets(4));
      final group = find.byType(CLGroupedNotificationRow);
      final mid = tester.getSize(group).height;
      await tester.pumpAndSettle();
      final open = tester.getSize(group).height;
      expect(mid, lessThan(open), reason: "grows, rather than appearing");

      await tester.tap(find.text("4"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(CLNotificationRow), findsNWidgets(4),
          reason: "closes WITH its rows");
      await tester.pumpAndSettle();
      expect(find.byType(CLNotificationRow), findsNothing);
    });

    testWidgets('one person\'s connections read as what they did',
        (tester) async {
      await tester.pumpWidget(_host(CLGroupedNotificationRow(
        group: _juanConnections(),
        expanded: false,
        onToggle: (_) {},
        busy: (_) => false,
        onAccept: (_) {},
        onDecline: (_) {},
      )));
      expect(_connectionSentence(tester),
          "Juan Lazy sent you a contact request and accepted your request");
      expect(find.textContaining("2 notifications"), findsOneWidget);
      expect(find.textContaining("1 to answer"), findsOneWidget);
      // The group's own row never carries buttons.
      expect(find.text("Confirm"), findsNothing);
    });

    testWidgets('a group with a request to answer opens, not navigates',
        (tester) async {
      NotificationV2? opened;
      String? toggled;
      await tester.pumpWidget(_host(CLGroupedNotificationRow(
        group: _juanConnections(),
        expanded: false,
        onToggle: (key) => toggled = key,
        busy: (_) => false,
        onAccept: (_) {},
        onDecline: (_) {},
        onOpen: (n) => opened = n,
      )));
      // Every member goes to Juan's profile - but the buttons are inside.
      await tester.tap(find.textContaining("accepted your request"));
      await tester.pump();
      expect(opened, isNull);
      expect(toggled, "g-juan");
    });

    testWidgets('each request is answered on its own row inside',
        (tester) async {
      final accepted = <String>[];
      final group = _juanConnections();
      await tester.pumpWidget(_host(CLGroupedNotificationRow(
        group: group,
        expanded: true,
        onToggle: (_) {},
        busy: (_) => false,
        onAccept: (n) => accepted.add(n.notificationID),
        onDecline: (_) {},
      )));
      await tester.pumpAndSettle();
      expect(find.text("Confirm"), findsOneWidget,
          reason: "only the open request has buttons");
      await tester.tap(find.text("Confirm"));
      expect(accepted, [group.items.first.notificationID]);
    });

    testWidgets('once answered, the group opens the shared profile',
        (tester) async {
      NotificationV2? opened;
      await tester.pumpWidget(_host(CLGroupedNotificationRow(
        group: _juanConnections(answered: true),
        expanded: false,
        onToggle: (_) {},
        busy: (_) => false,
        onAccept: (_) {},
        onDecline: (_) {},
        onOpen: (n) => opened = n,
      )));
      expect(find.textContaining("to answer"), findsNothing);
      await tester.tap(find.textContaining("accepted your request"));
      await tester.pump();
      expect(opened?.fromUserID, "juan");
    });

    testWidgets('long names fit a 360px phone', (tester) async {
      final long = _sender("x", "Maximiliano Bartholomew Fitzgerald-Santos");
      final group = NotificationGroup.fromJson({
        "key": "g",
        "count": 12,
        "unread": 12,
        "actorCount": 9,
        "action": "mentioned you in comments on a post",
        "items": [
          _notification("comment_mention", long),
          _notification("comment_mention", _maya),
        ],
      });
      await tester.pumpWidget(_host(
          CLGroupedNotificationRow(
            group: group,
            detail: true,
            expanded: true,
            onToggle: (_) {},
            busy: (_) => false,
            onAccept: (_) {},
            onDecline: (_) {},
          ),
          width: 340));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining("and 10 earlier"), findsOneWidget);
    });
  });
}
