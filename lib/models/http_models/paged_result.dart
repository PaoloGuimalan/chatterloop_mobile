import 'package:flutter/foundation.dart';

// One page of a DRF-paginated list ({count, next, previous, results}) - the
// envelope every v2 "See all" endpoint uses (search people/realms/posts,
// network connections/followers/following). `next` is flattened to a bool
// because pagination is driven by an incrementing page number here, not by
// following the server's URL.

class PagedResult<T> {
  /// Total matching rows, not the page size - drives the count pill on the
  /// detail screens' headers.
  final int count;
  final bool hasNext;
  final List<T> results;

  const PagedResult({
    required this.count,
    required this.hasNext,
    required this.results,
  });

  static PagedResult<T> empty<T>() =>
      PagedResult<T>(count: 0, hasNext: false, results: const []);

  /// `data` is the raw response body. A row that fails to parse is SKIPPED,
  /// and the rest of the page still arrives.
  ///
  /// This used to be a plain `.map(parse)`, which meant the opposite of what
  /// this comment claimed: a throw inside `parse` escaped `fromDrf` entirely,
  /// hit the calling request's try/catch, and returned an empty page. One
  /// malformed row therefore blanked a whole feed - silently, and on every
  /// load, since the same row comes back each time. That is not a theoretical
  /// risk: web is parsing the same payloads in JS, where a missing or
  /// unexpected field is `undefined` and rendering carries on, so a shape only
  /// this client rejects produces "works on web, empty on mobile" with nothing
  /// in between to explain it.
  factory PagedResult.fromDrf(
    dynamic data,
    T Function(Map<String, dynamic>) parse,
  ) {
    if (data is! Map) return PagedResult.empty<T>();
    final raw = data["results"];
    return PagedResult<T>(
      count: data["count"] is num ? (data["count"] as num).toInt() : 0,
      hasNext: data["next"] != null,
      results: raw is List ? _parseRows(raw, parse) : const [],
    );
  }

  static List<T> _parseRows<T>(
      List<dynamic> raw, T Function(Map<String, dynamic>) parse) {
    final results = <T>[];
    for (final item in raw.whereType<Map>()) {
      try {
        results.add(parse(Map<String, dynamic>.from(item)));
      } catch (e) {
        // Loud in debug - a skipped row is data the user asked for and did not
        // get, so it should be findable rather than merely survivable.
        if (kDebugMode) {
          print('[PagedResult] skipped an unparseable row: $e');
          print(item);
        }
      }
    }
    return results;
  }
}
