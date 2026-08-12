// Emoji + Comment shapes from the Django newsfeed app.
//
// Shared by the post screen and, later, the newsfeed - nothing in here knows
// which surface it's rendered on.

import 'package:chatterloop_app/models/messages_models/link_preview_model.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';

/// One entry of the reaction palette (GET /api/newsfeed/emojis).
///
/// `animatedPreview` is a Lottie JSON url, which is what the webapp's picker
/// plays. This app renders [content] - the glyph itself - instead; see
/// reaction_picker.dart for why.
class Emoji {
  final String emojiId;
  final String title;

  /// The actual character(s), e.g. "👍". This is what a reaction tally's
  /// `emoji` field is matched against for display.
  final String content;

  /// Hex string like "#7d7d7d" - the emoji's accent colour on web.
  final String theme;
  final int priority;
  final String? animatedPreview;

  const Emoji({
    required this.emojiId,
    required this.title,
    required this.content,
    required this.theme,
    required this.priority,
    this.animatedPreview,
  });

  factory Emoji.fromJson(Map<String, dynamic> json) {
    return Emoji(
      emojiId: (json["emoji_id"] ?? "").toString(),
      title: (json["emoji_title"] ?? "").toString(),
      content: (json["emoji_content"] ?? "").toString(),
      theme: (json["emoji_theme"] ?? "").toString(),
      priority: json["priority"] is num ? (json["priority"] as num).toInt() : 0,
      animatedPreview: json["animated_preview"]?.toString(),
    );
  }
}

/// One uploaded attachment on its way INTO a new post.
///
/// The outgoing counterpart of [PostReference], and deliberately a separate
/// type: this is what /posts/upload hands back (a CDN url plus a name and a
/// media type), not what the feed hands out - the read side also carries a
/// referenceID, a post id and an order the client never sends.
class PostMediaReference {
  /// CDN url from the upload step - `fileDetails.data` in its response.
  final String url;
  final String fileName;

  /// "image" or "video", as the upload response reports it.
  final String mediaType;
  final String caption;

  const PostMediaReference({
    required this.url,
    required this.fileName,
    required this.mediaType,
    this.caption = "",
  });

  /// [index] is the 1-based position web assigns (`id: i + 1`); the server
  /// sorts references by it.
  Map<String, dynamic> toJson(int index) => {
        'id': index,
        'name': fileName,
        'reference': url,
        'caption': caption,
        'referenceMediaType': mediaType,
      };
}

/// A comment or a reply (GET/POST /api/newsfeed/comments).
///
/// Threads are flattened to TWO levels server-side: a top-level comment and
/// its replies. Replying to a reply re-parents to the top-level ancestor and
/// mentions that author instead of nesting deeper, so a reply never has
/// children of its own and this model needs no recursion.
class PostComment {
  final String commentId;

  /// null for a top-level comment; the ancestor's id for a reply.
  final String? parentId;
  final String text;
  final String? attachment;
  final DateTime? createdAt;
  final PostPreviewAuthor author;

  /// Reaction tallies, same shape as a post's.
  final List<PostReactionCount> reactions;

  /// The emoji id the VIEWER reacted with, or null. Absent for guests.
  final String? entityReaction;

  /// How many replies hang off this comment. Always 0 on a reply.
  final int replyCount;
  final LinkPreviewData? linkPreview;

  const PostComment({
    required this.commentId,
    this.parentId,
    required this.text,
    this.attachment,
    this.createdAt,
    required this.author,
    required this.reactions,
    this.entityReaction,
    required this.replyCount,
    this.linkPreview,
  });

  int get reactionTotal =>
      reactions.fold(0, (sum, reaction) => sum + reaction.count);

  PostComment copyWith({
    List<PostReactionCount>? reactions,
    String? entityReaction,
    bool clearEntityReaction = false,
    int? replyCount,
  }) =>
      PostComment(
        commentId: commentId,
        parentId: parentId,
        text: text,
        attachment: attachment,
        createdAt: createdAt,
        author: author,
        reactions: reactions ?? this.reactions,
        entityReaction: clearEntityReaction
            ? null
            : (entityReaction ?? this.entityReaction),
        replyCount: replyCount ?? this.replyCount,
        linkPreview: linkPreview,
      );

  factory PostComment.fromJson(Map<String, dynamic> json) {
    final reactions = json["preview"];
    final linkPreview = json["link_preview"];
    // parent_comment is the FK id; the serializer emits it flat.
    final parent = json["parent_comment"]?.toString();
    return PostComment(
      commentId: (json["comment_id"] ?? "").toString(),
      parentId: (parent == null || parent.isEmpty) ? null : parent,
      text: (json["text"] ?? "").toString(),
      attachment: json["attachment"]?.toString(),
      createdAt: DateTime.tryParse((json["created_at"] ?? "").toString()),
      author: PostPreviewAuthor.fromEntityJson(json["entity"]),
      reactions: reactions is List
          ? reactions
              .whereType<Map>()
              .map((item) =>
                  PostReactionCount.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
      entityReaction: json["entity_reaction"]?.toString(),
      replyCount:
          json["reply_count"] is num ? (json["reply_count"] as num).toInt() : 0,
      linkPreview: linkPreview is Map
          ? LinkPreviewData.fromJson(Map<String, dynamic>.from(linkPreview))
          : null,
    );
  }
}
