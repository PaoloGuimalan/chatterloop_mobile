// The moderation record behind a "your content was removed" notification.
//
// Mirrors user_service entity/moderation_views.py and the webapp's
// ModerationDetailData, so both clients read one shape.

import 'package:chatterloop_app/models/post_models/post_preview_model.dart';

class ModerationCategory {
  final String code;
  final double score;

  const ModerationCategory({required this.code, required this.score});

  factory ModerationCategory.fromJson(Map<String, dynamic> json) =>
      ModerationCategory(
        code: (json['code'] ?? '').toString(),
        score: (json['score'] as num?)?.toDouble() ?? 0.0,
      );

  /// "hate_speech" -> "Hate speech". The codes mirror Report.REASON_CHOICES.
  String get readable {
    final spaced = code.replaceAll('_', ' ');
    if (spaced.isEmpty) return spaced;
    return spaced[0].toUpperCase() + spaced.substring(1);
  }
}

class ModerationContent {
  /// "post" or "comment".
  final String type;
  final String id;
  final String? body;
  final bool isRemoved;

  /// Full references, not just urls - the screen renders them through the
  /// app's own PostAttachments, which needs the media type to tell an image
  /// from a video.
  final List<PostReference> references;

  /// WHICH attachment the record is about, when it is about one.
  ///
  /// Media moderation targets a single reference, not the post: a post with
  /// four photos and one violating frame produces a record whose target is
  /// that photo. Without this the review shows four images and leaves the
  /// reader guessing which one it is about.
  final String? flaggedReferenceId;

  final String? authorName;
  final String? authorHandle;
  final String? authorPicture;
  final String? postedAt;

  const ModerationContent({
    required this.type,
    required this.id,
    required this.body,
    required this.isRemoved,
    required this.references,
    required this.flaggedReferenceId,
    required this.authorName,
    required this.authorHandle,
    required this.authorPicture,
    required this.postedAt,
  });

  factory ModerationContent.fromJson(Map<String, dynamic> json) {
    final references = json['references'];
    final details = (json['entity'] is Map)
        ? (json['entity']['details'] as Map?) ?? const {}
        : const {};

    final first = (details['first_name'] ?? '').toString().trim();
    final last = (details['last_name'] ?? '').toString().trim();
    final full = [first, last].where((p) => p.isNotEmpty).join(' ');
    final picture = (details['profile'] ?? '').toString();

    return ModerationContent(
      type: (json['type'] ?? 'post').toString(),
      // A serialized post keys its id as post_id; a comment payload uses id.
      id: (json['post_id'] ?? json['id'] ?? '').toString(),
      // A post carries a caption and a comment carries text; one field here,
      // because the screen renders them identically.
      body: (json['caption'] ?? json['text']) as String?,
      isRemoved: json['is_removed'] == true,
      references: references is List
          ? references
              .whereType<Map>()
              .map((r) => PostReference.fromJson(Map<String, dynamic>.from(r)))
              .toList()
          : const [],
      flaggedReferenceId: json['flagged_reference_id'] as String?,
      authorName: full.isEmpty
          ? (details['name'] ?? details['username'])?.toString()
          : full,
      authorHandle: (details['username'] ?? details['slug'])?.toString(),
      // Both sentinels the platform uses mean "no picture".
      authorPicture: (picture.isEmpty || picture == 'none' || picture == 'N/A')
          ? null
          : picture,
      postedAt: (json['date_posted'] ?? json['created_at'])?.toString(),
    );
  }
}

class ModerationVerdict {
  final String? verdict;
  final List<ModerationCategory> categories;

  /// Categories nothing checked. Surfaced because a category nobody looked at
  /// is not a category that came back clean.
  final List<String> unevaluated;
  final bool removed;

  /// What the model actually judged - for an image or a video this is the only
  /// human-readable account of why it scored the way it did.
  final String? reviewedText;

  const ModerationVerdict({
    required this.verdict,
    required this.categories,
    required this.unevaluated,
    required this.removed,
    required this.reviewedText,
  });

  factory ModerationVerdict.fromJson(Map<String, dynamic> json) {
    final categories = json['categories'];
    final unevaluated = json['unevaluated'];
    return ModerationVerdict(
      verdict: json['verdict'] as String?,
      categories: categories is List
          ? categories
              .whereType<Map>()
              .map((c) =>
                  ModerationCategory.fromJson(Map<String, dynamic>.from(c)))
              .toList()
          : const [],
      unevaluated: unevaluated is List
          ? unevaluated.map((u) => u.toString()).toList()
          : const [],
      removed: json['removed'] == true,
      reviewedText: json['reviewed_text'] as String?,
    );
  }
}

class ModerationDetail {
  final String moderationId;
  final bool viewerIsOwner;
  final ModerationContent content;
  final ModerationVerdict moderation;

  const ModerationDetail({
    required this.moderationId,
    required this.viewerIsOwner,
    required this.content,
    required this.moderation,
  });

  factory ModerationDetail.fromJson(Map<String, dynamic> json) =>
      ModerationDetail(
        moderationId: (json['moderation_id'] ?? '').toString(),
        viewerIsOwner: json['viewer_is_owner'] == true,
        content: ModerationContent.fromJson(
            Map<String, dynamic>.from(json['content'] ?? {})),
        moderation: ModerationVerdict.fromJson(
            Map<String, dynamic>.from(json['moderation'] ?? {})),
      );
}
