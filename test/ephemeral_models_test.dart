import 'package:chatterloop_app/models/post_models/ephemeral_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _entity(String id) => {
      "id": id,
      "type": "user",
      "details": {"first_name": "Ana", "last_name": "Cruz", "username": "ana"},
    };

void main() {
  test("thought parses content, mood, my_reaction and author", () {
    final t = Thought.fromJson({
      "post_id": "p1",
      "entity_id": "e1",
      "content": {"text": "coffee first ☕", "mood": "chilling"},
      "privacy_status": "connections",
      "date_posted": "2026-09-24T10:00:00Z",
      "expires_at": "2026-09-25T10:00:00Z",
      "my_reaction": "emo1",
      "author": _entity("e1"),
    });
    expect(t.text, "coffee first ☕");
    expect(thoughtMoodOf(t.mood)?.label, "Chilling");
    expect(t.myReaction, "emo1");
    expect(t.author?.displayName, "Ana Cruz");
    expect(t.views, isNull);
  });

  test("rail: mine is optional", () {
    final rail = ThoughtsRail.fromJson({"mine": null, "results": []});
    expect(rail.mine, isNull);
    expect(rail.results, isEmpty);
  });

  test("moment: allow_replies defaults on, shared post id from reference", () {
    final m = Moment.fromJson({
      "post_id": "m1",
      "caption": "",
      "file_type": "shared_post",
      "references": [
        {
          "reference_id": "r1",
          "reference": "post-9",
          "referenceMediaType": "shared_post"
        }
      ],
      "entity": _entity("e1"),
      "expires_at": "2026-09-25T10:00:00Z",
      "seen": true,
    });
    expect(m.allowReplies, isTrue);
    expect(m.isShared, isTrue);
    expect(m.sharedPostId, "post-9");
    expect(m.seen, isTrue);
    expect(
        Moment.fromJson({
          "post_id": "m2",
          "details": {"allow_replies": false}
        }).allowReplies,
        isFalse);
  });

  test("tray: self entry and new count", () {
    final tray = MomentTray.fromJson({
      "results": [
        {"entity": _entity("me"), "is_self": true, "start_post_id": "a"},
        {"entity": _entity("x"), "has_unseen": true, "unseen_count": 2},
      ],
      "new_count": 1,
    });
    expect(tray.mine?.startPostId, "a");
    expect(tray.newCount, 1);
    expect(tray.results.last.hasUnseen, isTrue);
  });

  test("time labels and char count", () {
    final now = DateTime(2026, 9, 24, 12);
    expect(
        ephemeralTimeLeft(now.add(const Duration(hours: 22, minutes: 5)),
            now: now),
        "22h left");
    expect(
        ephemeralTimeLeft(now.subtract(const Duration(minutes: 1)), now: now),
        "Expired");
    expect(
        ephemeralTimeAgo(now.subtract(const Duration(minutes: 12)), now: now),
        "12m");
    expect(ephemeralCharCount("hi 🔥"), 4);
  });

  test("rail suggestions parse; viewer last activity", () {
    final rail = ThoughtsRail.fromJson({
      "mine": null,
      "results": [],
      "suggestions": [_entity("s1"), _entity("s2")],
    });
    expect(rail.suggestions.map((a) => a.entityId), ["s1", "s2"]);
    expect(ThoughtsRail.fromJson({"results": []}).suggestions, isEmpty);

    final viewer = EphemeralViewer.fromJson({
      "entity": _entity("v"),
      "viewed_at": "2026-09-24T02:00:00Z",
      "last_activity_at": "2026-09-24T09:55:00+00:00",
      "reaction": null,
      "replied": true,
    });
    expect(viewer.lastActivityAt!.toUtc().hour, 9);
    expect(viewer.lastActivityAt!.isAfter(viewer.viewedAt!), isTrue);
  });
}
