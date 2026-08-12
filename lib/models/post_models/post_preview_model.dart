// GET /api/newsfeed/preview/<post_id>/ - the full Django PostSerializer
// shape, parsed down to what the read-only post preview screen renders.
//
// Deliberately NOT UserPost (post_models/user_post_model.dart): that model
// parses the NODE feed's payload (postID/content/post_owner), a completely
// different shape from the Django serializer's (post_id/references/entity).
// Both exist because both endpoints exist.

import 'package:chatterloop_app/models/messages_models/link_preview_model.dart';

/// Appends [incoming] to [into], dropping any post already in the list.
/// Returns how many actually landed.
///
/// Every paginated feed has to go through this, because duplicates arrive
/// from two unrelated directions and neither is a client bug:
///
///   - The profile feed's queryset ORs `entity` against `tagging__entity`,
///     which is a join across a many-to-many. A post tagging three people
///     comes back as three rows.
///   - The default feed is RANKED, and ranking is recomputed per request. A
///     post can be #10 when you fetch page 1 and #11 by the time you fetch
///     page 2, so it legitimately appears in both.
///
/// Keeping the FIRST copy matters: later pages of a shifting feed are the
/// stale ones, and replacing an already-rendered row would also throw away
/// whatever local state it holds (an optimistic reaction, say).
int appendDistinctPosts(
    List<PostPreview> into, Iterable<PostPreview> incoming) {
  final seen = into.map((post) => post.postId).toSet();
  var added = 0;
  for (final post in incoming) {
    if (post.postId.isEmpty || !seen.add(post.postId)) continue;
    into.add(post);
    added++;
  }
  return added;
}

/// One attached media file. `reference` is an absolute URL, ready to hand to
/// Image.network / VideoPlayerController.
class PostReference {
  final String referenceId;
  final String reference;
  final String mediaType;

  const PostReference({
    required this.referenceId,
    required this.reference,
    required this.mediaType,
  });

  bool get isImage => mediaType.contains("image");
  bool get isVideo => mediaType.contains("video");

  factory PostReference.fromJson(Map<String, dynamic> json) {
    return PostReference(
      referenceId: (json["reference_id"] ?? "").toString(),
      reference: (json["reference"] ?? "").toString(),
      mediaType: (json["reference_media_type"] ?? "").toString(),
    );
  }
}

/// A reaction tally ({emoji, count}) from the serializer's `preview` field.
class PostReactionCount {
  final String emoji;
  final int count;

  const PostReactionCount({required this.emoji, required this.count});

  factory PostReactionCount.fromJson(Map<String, dynamic> json) {
    return PostReactionCount(
      emoji: (json["emoji"] ?? "").toString(),
      count: json["count"] is num ? (json["count"] as num).toInt() : 0,
    );
  }
}

/// The post's author, normalized off EntitySerializer.details.
///
/// EmbeddedRealmSerializer aliases a realm's fields onto the account keys
/// (name -> first_name, slug/realm_id -> username, is_verified -> is_badged)
/// specifically so one reader handles both kinds - hence no per-type branch
/// here beyond the routing target.
class PostPreviewAuthor {
  final String entityId;
  final String type;
  final String displayName;
  final String handle;
  final String? profile;
  final bool isVerified;

  const PostPreviewAuthor({
    required this.entityId,
    required this.type,
    required this.displayName,
    required this.handle,
    this.profile,
    required this.isVerified,
  });

  bool get isRealm => type == "realm";

  factory PostPreviewAuthor.fromEntityJson(dynamic entity) {
    final map =
        entity is Map ? Map<String, dynamic>.from(entity) : <String, dynamic>{};
    final details = map["details"] is Map
        ? Map<String, dynamic>.from(map["details"])
        : const <String, dynamic>{};
    final first = (details["first_name"] ?? "").toString();
    var middle = (details["middle_name"] ?? "").toString();
    if (middle == "N/A") middle = "";
    final last = (details["last_name"] ?? "").toString();
    final name = [first, middle, last]
        .where((part) => part.trim().isNotEmpty)
        .join(" ")
        .trim();
    final handle = (details["username"] ?? "").toString();
    final profile = details["profile"]?.toString();
    return PostPreviewAuthor(
      entityId: (map["id"] ?? "").toString(),
      type: (map["type"] ?? "user").toString(),
      displayName: name.isNotEmpty ? name : handle,
      handle: handle,
      // Unlike the v2 search/network endpoints, the newsfeed serializers do
      // NOT normalize the "no photo" sentinels away - so both are checked
      // here instead.
      profile: (profile == null ||
              profile.isEmpty ||
              profile == "none" ||
              profile == "N/A")
          ? null
          : profile,
      isVerified: details["is_badged"] == true,
    );
  }
}

class PostPreview {
  final String postId;
  final String caption;
  final DateTime? datePosted;
  final List<PostReference> references;
  final List<PostReactionCount> reactions;
  final PostPreviewAuthor author;
  final int likesCount;
  final int commentsCount;

  /// A shared post's own media lives on the referenced post, not here - web
  /// hides the carousel entirely in that case, so this does too. The shared
  /// post's id travels as a reference with mediaType "shared_post"; see
  /// [sharedPostId].
  final bool isShared;
  final LinkPreviewData? linkPreview;

  /// The emoji id the VIEWER reacted with, or null if they haven't. Drives
  /// which reaction the action bar shows as active, and whether tapping one
  /// POSTs (first reaction), PUTs (swap) or DELETEs (same one again).
  final String? entityReaction;

  /// Whether the viewer has saved this post.
  final bool isSaved;

  /// Archived posts are hidden from feeds but still reachable by their author.
  /// Only the author can archive, and Save is hidden while archived.
  final bool isArchived;

  /// What KIND of post this is - "text", "media", "shared_post", and the two
  /// that are really account updates: "profile" and "cover_photo". The server
  /// writes the avatar/cover AND files a post, which is how a changed picture
  /// shows up in the feed at all.
  final String contentType;

  bool get isProfilePicturePost => contentType == 'profile';
  bool get isCoverPhotoPost => contentType == 'cover_photo';

  /// Who the post was published to - "public", "connections", "private" or
  /// "custom" (Post.PRIVACY_STATUS_CHOICES). Shown as an icon in the header so
  /// the author can see at a glance where something went; the SERVER is what
  /// actually enforces it.
  final String privacyStatus;

  /// Entities tagged on the post - "is with A, B and C" in the header. Users
  /// AND realms/pages, which is why they reuse the author shape: `tagging[]`
  /// rows carry a full EntitySerializer, same as the post's own entity.
  final List<PostPreviewAuthor> tagged;

  const PostPreview({
    required this.postId,
    required this.caption,
    this.datePosted,
    required this.references,
    required this.reactions,
    required this.author,
    required this.likesCount,
    required this.commentsCount,
    required this.isShared,
    this.linkPreview,
    this.entityReaction,
    this.isSaved = false,
    this.isArchived = false,
    this.privacyStatus = 'public',
    this.contentType = 'text',
    this.tagged = const [],
  });

  /// The post this one shares, when [isShared]. Stored as a reference row
  /// whose media type is "shared_post" and whose `reference` is the original
  /// post's id - the same shape the composer sends when creating a share.
  String? get sharedPostId {
    for (final reference in references) {
      if (reference.mediaType == "shared_post") return reference.reference;
    }
    return null;
  }

  /// Total reactions across every emoji - what the summary row counts.
  int get reactionTotal =>
      reactions.fold(0, (sum, reaction) => sum + reaction.count);

  PostPreview copyWith({
    List<PostReactionCount>? reactions,
    String? entityReaction,
    bool clearEntityReaction = false,
    int? commentsCount,
    bool? isSaved,
    bool? isArchived,
    String? privacyStatus,
    String? contentType,
  }) =>
      PostPreview(
        postId: postId,
        caption: caption,
        datePosted: datePosted,
        references: references,
        reactions: reactions ?? this.reactions,
        author: author,
        likesCount: likesCount,
        commentsCount: commentsCount ?? this.commentsCount,
        isShared: isShared,
        linkPreview: linkPreview,
        entityReaction: clearEntityReaction
            ? null
            : (entityReaction ?? this.entityReaction),
        isSaved: isSaved ?? this.isSaved,
        isArchived: isArchived ?? this.isArchived,
        privacyStatus: privacyStatus ?? this.privacyStatus,
        contentType: contentType ?? this.contentType,
        tagged: tagged,
      );

  factory PostPreview.fromJson(Map<String, dynamic> json) {
    final references = json["references"];
    final reactions = json["preview"];
    final score = json["score"] is Map
        ? Map<String, dynamic>.from(json["score"])
        : const <String, dynamic>{};
    final linkPreview = json["link_preview"];
    return PostPreview(
      postId: (json["post_id"] ?? "").toString(),
      caption: (json["caption"] ?? "").toString(),
      datePosted: DateTime.tryParse((json["date_posted"] ?? "").toString()),
      references: references is List
          ? references
              .whereType<Map>()
              .map((item) =>
                  PostReference.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
      reactions: reactions is List
          ? reactions
              .whereType<Map>()
              .map((item) =>
                  PostReactionCount.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
      author: PostPreviewAuthor.fromEntityJson(json["entity"]),
      likesCount: score["likes_count"] is num
          ? (score["likes_count"] as num).toInt()
          : 0,
      commentsCount: score["comments_count"] is num
          ? (score["comments_count"] as num).toInt()
          : 0,
      isShared: json["is_shared"] == true,
      entityReaction: json["entity_reaction"]?.toString(),
      isSaved: json["is_saved"] == true,
      isArchived: json["is_archived"] == true,
      // Defaulted rather than nullable: the column has a default of "public"
      // server-side, so an absent value means public rather than unknown.
      privacyStatus: (json["privacy_status"] ?? 'public').toString(),
      contentType: (json["content_type"] ?? 'text').toString(),
      tagged: json["tagging"] is List
          ? (json["tagging"] as List)
              .whereType<Map>()
              .map((item) => PostPreviewAuthor.fromEntityJson(
                  Map<String, dynamic>.from(item)["entity"]))
              // A tag whose entity didn't resolve has no name to render.
              .where((entity) => entity.displayName.isNotEmpty)
              .toList()
          : const [],
      linkPreview: linkPreview is Map
          ? LinkPreviewData.fromJson(Map<String, dynamic>.from(linkPreview))
          : null,
    );
  }
}
