// GET /api/newsfeed/saves - the bookmark list.
//
// Deliberately its own model rather than [PostPreview]: the rows come from
// PostSaveSerializer, whose nested `post` is a PostBasicSerializer - the Post
// row and its author entity, and nothing else. No attachments, no reaction or
// comment counts, no references. Parsing it as a PostPreview would produce
// posts that claim zero of everything, which a feed row would then render as
// fact.
//
// So a saved row shows what it actually has (author, caption, kind) and links
// out to /post/<id> for the real thing, which is also what webapp's
// SavedPostItem does with its View button.

/// The author of a saved post - a person or a page.
///
/// EntitySerializer nests the concrete row under `details`, and which fields
/// exist there depends on the kind: a user has first/last name and username,
/// a realm has name and slug. [displayName] and [handle] flatten that.
class SavedPostAuthor {
  final String entityId;
  final String type;
  final String displayName;
  final String handle;
  final String? profile;

  const SavedPostAuthor({
    required this.entityId,
    required this.type,
    required this.displayName,
    required this.handle,
    this.profile,
  });

  bool get isRealm => type != "user";

  factory SavedPostAuthor.fromJson(Map<String, dynamic> json) {
    final details = json["details"] is Map
        ? Map<String, dynamic>.from(json["details"])
        : const <String, dynamic>{};

    final first = (details["first_name"] ?? "").toString().trim();
    final middle = (details["middle_name"] ?? "").toString().trim();
    final last = (details["last_name"] ?? "").toString().trim();
    // "N/A" is the sentinel the backend stores for an absent middle name, and
    // it must never reach a rendered name.
    final personName = [
      first,
      if (middle.isNotEmpty && middle != "N/A") middle,
      last,
    ].where((part) => part.isNotEmpty).join(" ");

    final profile = details["profile"]?.toString();

    return SavedPostAuthor(
      entityId: (json["id"] ?? "").toString(),
      type: (json["type"] ?? "user").toString(),
      displayName: (details["name"] ?? "").toString().trim().isNotEmpty
          ? details["name"].toString()
          : personName,
      handle: (details["slug"] ?? details["username"] ?? "").toString(),
      // Both "none" and "N/A" are used as "no picture" across these payloads.
      profile:
          (profile == null || profile.isEmpty || profile == "N/A" ||
                  profile == "none")
              ? null
              : profile,
    );
  }
}

class SavedPost {
  /// The PostSave row's id, not the post's - this is what the list dedupes on,
  /// since the same post can only be saved once but the ids differ in kind.
  final String id;
  final String postId;
  final String caption;

  /// "text_only", "with_media", … - rendered as a human label on the row.
  final String contentType;
  final DateTime? savedAt;
  final SavedPostAuthor author;

  const SavedPost({
    required this.id,
    required this.postId,
    required this.caption,
    required this.contentType,
    required this.author,
    this.savedAt,
  });

  factory SavedPost.fromJson(Map<String, dynamic> json) {
    final post = json["post"] is Map
        ? Map<String, dynamic>.from(json["post"])
        : const <String, dynamic>{};
    return SavedPost(
      id: (json["id"] ?? "").toString(),
      postId: (post["post_id"] ?? "").toString(),
      caption: (post["caption"] ?? "").toString(),
      contentType: (post["content_type"] ?? "").toString(),
      savedAt: DateTime.tryParse((json["saved_at"] ?? "").toString()),
      author: SavedPostAuthor.fromJson(
        post["entity"] is Map
            ? Map<String, dynamic>.from(post["entity"])
            : const <String, dynamic>{},
      ),
    );
  }

  /// "Paolo's Post" when there is no caption to show - the same fallback the
  /// webapp row uses, so an image-only post is still identifiable.
  String get title {
    if (caption.trim().isNotEmpty) return caption.trim();
    final who = author.displayName.trim();
    return who.isEmpty ? "Post" : "$who's Post";
  }

  /// "with_media" -> "With Media".
  String get contentTypeLabel => contentType
      .replaceAll("_", " ")
      .split(" ")
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(" ");
}
