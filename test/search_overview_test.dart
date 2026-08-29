// The Explore overview's section parsing.
//
// Pinned because the Topics section is the one whose wire key CHANGED - it
// shipped as "tags" and was renamed to "topics" - and a client reading only one
// of them renders "No topics found" against a server sending the other. That
// failure is indistinguishable from an empty result set by eye, including in
// the network response, so it needs a test rather than a look.

import 'package:chatterloop_app/models/user_models/search_v2_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _payload(String topicsKey) => {
      topicsKey: {
        "has_more": true,
        "results": [
          {
            "id": 7,
            "name": "sunset series",
            "slug": "sunsetseries",
            "category": "Photography",
            "score": 12.5,
            "posts": 3,
            "faces": [
              {
                "entity_id": "e1",
                "name": "Rina Santos",
                "profile": null,
                "initials": "RS",
              }
            ],
          }
        ],
      },
      "people": {"has_more": false, "results": []},
      "realms": {"has_more": false, "results": []},
      "posts": {"has_more": false, "results": []},
    };

void main() {
  group('the topics section arrives under either key', () {
    for (final key in ['topics', 'tags']) {
      test('"$key"', () {
        final overview = SearchOverview.fromJson(_payload(key));

        expect(overview.topics.results, hasLength(1),
            reason: 'a server sending "$key" must not read as no results');
        expect(overview.topics.results.first.slug, 'sunsetseries');
        expect(overview.topics.results.first.category, 'Photography');
        expect(overview.topics.results.first.faces, hasLength(1));
        expect(overview.topics.hasMore, isTrue);
      });
    }
  });

  test('a section the server omits entirely is empty, not an error', () {
    final overview = SearchOverview.fromJson({
      "people": {"has_more": false, "results": []},
      "realms": {"has_more": false, "results": []},
      "posts": {"has_more": false, "results": []},
    });

    expect(overview.topics.results, isEmpty);
    expect(overview.topics.hasMore, isFalse);
  });

  test('a follow flip does not drop the topics already parsed', () {
    // copyWith rebuilds the whole object; forgetting one section there is how
    // results vanish the moment somebody taps Follow.
    final overview = SearchOverview.fromJson(_payload('topics'));
    final after = overview.copyWith(
      people: const SearchOverviewSection(hasMore: false, results: []),
    );

    expect(after.topics.results, hasLength(1));
  });
}
