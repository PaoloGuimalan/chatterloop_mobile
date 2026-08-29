// Explore's "Recent" list - the queries you have actually run.
//
// LOCAL ONLY, on purpose. There is no server endpoint for search history and
// this deliberately does not invent one: a search history is a sensitive log,
// syncing it across devices is a product decision rather than a UI detail, and
// Explore needs suggestions before either of those questions has an answer.
// Same call as MapFeedPrefs, which keeps the map toggles client-side for the
// same reason.
//
// Keyed by the ACTING entity's id, because a page acting for itself is a
// different searcher than the person behind it - switching to a page must not
// show that account's own recent searches back to whoever it is shared with.

import 'package:shared_preferences/shared_preferences.dart';

/// How many to keep. Short by design: this list sits above the popular topics
/// and is meant to catch "the thing I looked up ten minutes ago", not to be a
/// history screen. The design's idle state has room for a handful before the
/// tags below it start losing the fold.
const int kRecentSearchMax = 6;

class RecentSearches {
  static String _key(String entityId) => 'recent_searches_$entityId';

  /// Most recent first. Empty when nothing has been searched yet - the caller
  /// renders no section at all rather than an empty one.
  static Future<List<String>> read(String entityId) async {
    if (entityId.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key(entityId)) ?? const [];
  }

  /// Records [query] at the top, and returns the new list so the caller can
  /// render it without a second read.
  ///
  /// Re-searching something already in the list MOVES it rather than
  /// duplicating it - matched case-insensitively, since "Rina" and "rina" are
  /// the same search, while the newly typed spelling is the one kept.
  static Future<List<String>> record(String entityId, String query) async {
    final cleaned = query.trim();
    if (entityId.isEmpty || cleaned.isEmpty) return read(entityId);

    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key(entityId)) ?? const <String>[];
    final next = <String>[
      cleaned,
      ...current
          .where((entry) => entry.toLowerCase() != cleaned.toLowerCase()),
    ].take(kRecentSearchMax).toList();

    await prefs.setStringList(_key(entityId), next);
    return next;
  }

  /// Drops one entry - the × on a recent row.
  static Future<List<String>> remove(String entityId, String query) async {
    if (entityId.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getStringList(_key(entityId)) ?? const <String>[])
        .where((entry) => entry != query)
        .toList();
    await prefs.setStringList(_key(entityId), next);
    return next;
  }

  static Future<void> clear(String entityId) async {
    if (entityId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(entityId));
  }
}
