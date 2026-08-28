// Popular Topics - the interest ranking behind Explore's first section.
//
// Mirrors user_service interests/views.py PopularTopicsView and the webapp's
// PopularTopic/TopicFace interfaces. Counts and faces come back already
// filtered to what THIS viewer may see (the endpoint applies the feed's own
// post-visibility rule), so nothing here should be cached across accounts.

class PopularTopicFace {
  final String entityId;
  final String name;

  /// Profile picture URL, or null when the participant has none. Null and a
  /// dead URL are the same thing to CLAvatar, which falls back to initials on
  /// both.
  final String? profile;
  final String initials;

  const PopularTopicFace({
    required this.entityId,
    required this.name,
    required this.profile,
    required this.initials,
  });

  factory PopularTopicFace.fromJson(Map<String, dynamic> json) {
    return PopularTopicFace(
      entityId: (json['entity_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      profile: json['profile'] as String?,
      initials: (json['initials'] ?? '').toString(),
    );
  }
}

class PopularTopic {
  final int id;

  /// The readable interest name ("north edsa") - what a text search should
  /// use, because prose mentions it with the spaces in.
  final String name;

  /// The normalized key ("northedsa") - what a hashtag normalises to and what
  /// the topic endpoint resolves on. Shown with a leading "#".
  final String slug;

  /// The taxonomy parent, or "General" for an interest nothing has adopted.
  final String category;
  final double score;

  /// Visible post count. Carried for completeness but not displayed - it is a
  /// number the reader cannot act on, and it crowded the row on web too.
  final int posts;
  final List<PopularTopicFace> faces;

  const PopularTopic({
    required this.id,
    required this.name,
    required this.slug,
    required this.category,
    required this.score,
    required this.posts,
    required this.faces,
  });

  factory PopularTopic.fromJson(Map<String, dynamic> json) {
    final faces = json['faces'];
    return PopularTopic(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
      category: (json['category'] ?? 'General').toString(),
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      posts: (json['posts'] as num?)?.toInt() ?? 0,
      faces: faces is List
          ? faces
              .whereType<Map>()
              .map((face) =>
                  PopularTopicFace.fromJson(Map<String, dynamic>.from(face)))
              .toList()
          : const [],
    );
  }
}
