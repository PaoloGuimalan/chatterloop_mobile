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

  /// `data` is the raw response body. Anything unparseable degrades to an
  /// empty page rather than throwing - a malformed row must not take out the
  /// whole list.
  factory PagedResult.fromDrf(
    dynamic data,
    T Function(Map<String, dynamic>) parse,
  ) {
    if (data is! Map) return PagedResult.empty<T>();
    final raw = data["results"];
    return PagedResult<T>(
      count: data["count"] is num ? (data["count"] as num).toInt() : 0,
      hasNext: data["next"] != null,
      results: raw is List
          ? raw
              .whereType<Map>()
              .map((item) => parse(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
    );
  }
}
