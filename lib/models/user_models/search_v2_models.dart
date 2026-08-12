// Search v2 result shapes - the redesigned Explore screen's data. Mirror
// webapp/src/reusables/vars/interfaces.ts (SearchPersonResult /
// SearchRealmResult / SearchPostResult / SearchOverview), which in turn
// mirror user_service's entity/search_views.py + newsfeed/services/
// post_search.py exactly.
//
// `profile` arrives already normalized server side (both "no photo"
// sentinels - user "none" and realm "N/A" - come back as null), so nothing
// here needs to re-check for them.

/// A person hit. `is_followed` and `is_follow_pending` together drive the
/// card's Follow / Requested / Following toggle - they are mutually
/// exclusive, and pending means a follow of a PRIVATE profile awaiting its
/// owner's approval;
/// the connection-state fields are carried through for parity with the v1
/// entity search so a contact flow can be deep-linked from here later.
class SearchPersonResult {
  final String entityId;
  final String displayName;
  final String handle;
  final String? profile;
  final bool isVerified;
  final int mutualCount;
  final bool isFollowed;
  final bool isFollowPending;
  final String? id;
  final bool hasConnection;
  final bool connectionAccomplished;
  final String? connectionId;
  final bool isActionByEntity;

  const SearchPersonResult({
    required this.entityId,
    required this.displayName,
    required this.handle,
    this.profile,
    required this.isVerified,
    required this.mutualCount,
    required this.isFollowed,
    this.isFollowPending = false,
    this.id,
    required this.hasConnection,
    required this.connectionAccomplished,
    this.connectionId,
    required this.isActionByEntity,
  });

  SearchPersonResult copyWith({bool? isFollowed, bool? isFollowPending}) =>
      SearchPersonResult(
        entityId: entityId,
        displayName: displayName,
        handle: handle,
        profile: profile,
        isVerified: isVerified,
        mutualCount: mutualCount,
        isFollowed: isFollowed ?? this.isFollowed,
        isFollowPending: isFollowPending ?? this.isFollowPending,
        id: id,
        hasConnection: hasConnection,
        connectionAccomplished: connectionAccomplished,
        connectionId: connectionId,
        isActionByEntity: isActionByEntity,
      );

  factory SearchPersonResult.fromJson(Map<String, dynamic> json) {
    return SearchPersonResult(
      entityId: (json["entity_id"] ?? "").toString(),
      displayName: (json["display_name"] ?? "").toString(),
      handle: (json["handle"] ?? "").toString(),
      profile: json["profile"]?.toString(),
      isVerified: json["is_verified"] == true,
      mutualCount: json["mutual_count"] is num
          ? (json["mutual_count"] as num).toInt()
          : 0,
      isFollowed: json["is_followed"] == true,
      isFollowPending: json["is_follow_pending"] == true,
      id: json["id"]?.toString(),
      hasConnection: json["has_connection"] == true,
      connectionAccomplished: json["connection_accomplished"] == true,
      connectionId: json["connection_id"]?.toString(),
      isActionByEntity: json["is_action_by_entity"] == true,
    );
  }
}

/// A realm hit. Only page / server / group can ever reach here - the server
/// filters channel/conference/voice out unconditionally. The action differs
/// per kind: page -> Follow toggle, server -> Open, group -> Join, or Open
/// chat once `is_member`.
class SearchRealmResult {
  final String entityId;
  final String displayName;
  final String handle;
  final String? profile;
  final bool isVerified;
  final String realmType;
  final int membersCount;
  final int followersCount;
  final bool isFollower;
  final bool isMember;

  /// Realm pk. A group's conversationID IS its realm id, so this is also
  /// what "Open chat" routes to.
  final String id;

  const SearchRealmResult({
    required this.entityId,
    required this.displayName,
    required this.handle,
    this.profile,
    required this.isVerified,
    required this.realmType,
    required this.membersCount,
    required this.followersCount,
    required this.isFollower,
    required this.isMember,
    required this.id,
  });

  SearchRealmResult copyWith({bool? isFollower, bool? isMember}) =>
      SearchRealmResult(
        entityId: entityId,
        displayName: displayName,
        handle: handle,
        profile: profile,
        isVerified: isVerified,
        realmType: realmType,
        membersCount: membersCount,
        followersCount: followersCount,
        isFollower: isFollower ?? this.isFollower,
        isMember: isMember ?? this.isMember,
        id: id,
      );

  factory SearchRealmResult.fromJson(Map<String, dynamic> json) {
    return SearchRealmResult(
      entityId: (json["entity_id"] ?? "").toString(),
      displayName: (json["display_name"] ?? "").toString(),
      handle: (json["handle"] ?? "").toString(),
      profile: json["profile"]?.toString(),
      isVerified: json["is_verified"] == true,
      realmType: (json["realm_type"] ?? "").toString(),
      membersCount: json["members_count"] is num
          ? (json["members_count"] as num).toInt()
          : 0,
      followersCount: json["followers_count"] is num
          ? (json["followers_count"] as num).toInt()
          : 0,
      isFollower: json["is_follower"] == true,
      isMember: json["is_member"] == true,
      id: (json["id"] ?? "").toString(),
    );
  }
}

/// The author line on a content card - a post can be authored by a person
/// OR a page, so this is the same normalized shape either way.
class SearchPostAuthor {
  final String entityId;
  final String type;
  final String displayName;
  final String handle;
  final String? profile;
  final bool isVerified;

  const SearchPostAuthor({
    required this.entityId,
    required this.type,
    required this.displayName,
    required this.handle,
    this.profile,
    required this.isVerified,
  });

  bool get isRealm => type == "realm";

  factory SearchPostAuthor.fromJson(Map<String, dynamic> json) {
    return SearchPostAuthor(
      entityId: (json["entity_id"] ?? "").toString(),
      type: (json["type"] ?? "user").toString(),
      displayName: (json["display_name"] ?? "").toString(),
      handle: (json["handle"] ?? "").toString(),
      profile: json["profile"]?.toString(),
      isVerified: json["is_verified"] == true,
    );
  }
}

/// A post hit - deliberately lightweight (author/time/caption + the two
/// counters). The real post is opened separately through
/// `/api/newsfeed/preview/<post_id>/`, same as on web.
class SearchPostResult {
  final String postId;
  final String caption;
  final String contentType;
  final String fileType;
  final DateTime? datePosted;
  final int likesCount;
  final int commentsCount;
  final SearchPostAuthor author;

  const SearchPostResult({
    required this.postId,
    required this.caption,
    required this.contentType,
    required this.fileType,
    this.datePosted,
    required this.likesCount,
    required this.commentsCount,
    required this.author,
  });

  factory SearchPostResult.fromJson(Map<String, dynamic> json) {
    final author = json["author"];
    return SearchPostResult(
      postId: (json["post_id"] ?? "").toString(),
      caption: (json["caption"] ?? "").toString(),
      contentType: (json["content_type"] ?? "").toString(),
      fileType: (json["file_type"] ?? "").toString(),
      // ISO8601 from the serializer.
      datePosted: DateTime.tryParse((json["date_posted"] ?? "").toString()),
      likesCount:
          json["likes_count"] is num ? (json["likes_count"] as num).toInt() : 0,
      commentsCount: json["comments_count"] is num
          ? (json["comments_count"] as num).toInt()
          : 0,
      author: SearchPostAuthor.fromJson(
          author is Map ? Map<String, dynamic>.from(author) : const {}),
    );
  }
}

/// One section of the overview response. `hasMore` is resolved server side by
/// fetching previewN+1 rows, so there is deliberately no total here (no COUNT
/// query) - the "See all" detail screen gets the real count from its own
/// paginated endpoint.
class SearchOverviewSection<T> {
  final bool hasMore;
  final List<T> results;

  const SearchOverviewSection({required this.hasMore, required this.results});

  static SearchOverviewSection<T> parse<T>(
    dynamic data,
    T Function(Map<String, dynamic>) parseItem,
  ) {
    if (data is! Map) {
      return SearchOverviewSection<T>(hasMore: false, results: const []);
    }
    final raw = data["results"];
    return SearchOverviewSection<T>(
      hasMore: data["has_more"] == true,
      results: raw is List
          ? raw
              .whereType<Map>()
              .map((item) => parseItem(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
    );
  }
}

class SearchOverview {
  final SearchOverviewSection<SearchPersonResult> people;
  final SearchOverviewSection<SearchRealmResult> realms;
  final SearchOverviewSection<SearchPostResult> posts;

  const SearchOverview({
    required this.people,
    required this.realms,
    required this.posts,
  });

  SearchOverview copyWith({
    SearchOverviewSection<SearchPersonResult>? people,
    SearchOverviewSection<SearchRealmResult>? realms,
  }) =>
      SearchOverview(
        people: people ?? this.people,
        realms: realms ?? this.realms,
        posts: posts,
      );

  factory SearchOverview.fromJson(Map<String, dynamic> json) {
    return SearchOverview(
      people: SearchOverviewSection.parse(
          json["people"], SearchPersonResult.fromJson),
      realms: SearchOverviewSection.parse(
          json["realms"], SearchRealmResult.fromJson),
      posts:
          SearchOverviewSection.parse(json["posts"], SearchPostResult.fromJson),
    );
  }
}
