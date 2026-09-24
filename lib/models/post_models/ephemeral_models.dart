/// Moments (24h photo / video / shared-post stories) and Thoughts (24h text
/// notes, 60 characters, optional mood) - the two ephemeral post kinds.
///
/// Both are rows in newsfeed_post (on_feed "moment" / "thought") served by
/// user_service's newsfeed/moment_views.py; created through Node's
/// /posts/moments/create and /posts/thoughts/create. Mirrors webapp's
/// interfaces.ts (IMomentTray, IThought, ...) and moments/ephemeral.ts.
library;

import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/material.dart';

const thoughtMaxLength = 60;
const momentCaptionMaxLength = 120;

/// The two audiences an ephemeral post can have. "Close" exists in the
/// designs but is hidden until close-friends lists do.
const ephemeralAudiences = <({String key, String label, IconData icon})>[
  (key: "public", label: "Public", icon: Icons.public_rounded),
  (key: "connections", label: "Contacts", icon: Icons.group_rounded),
];

/// One-tap emoji for the thought composer - same row as web.
const thoughtEmojis = ["☕", "🔥", "😴", "🎧", "✈️", "🍜", "🎉", "💭"];

class ThoughtMood {
  final String key;
  final String label;
  final IconData icon;
  final Color color;

  const ThoughtMood(this.key, this.label, this.icon, this.color);
}

/// The server's THOUGHT_MOODS, in the composer's order.
const thoughtMoods = <ThoughtMood>[
  ThoughtMood("chilling", "Chilling", Icons.coffee_rounded, Color(0xFF3B82F6)),
  ThoughtMood("busy", "Busy", Icons.work_rounded, Color(0xFFF59E0B)),
  ThoughtMood(
      "focused", "Focused", Icons.headphones_rounded, Color(0xFF8B5CF6)),
  ThoughtMood("traveling", "Traveling", Icons.flight_takeoff_rounded,
      Color(0xFF0EA5E9)),
  ThoughtMood("celebrating", "Celebrating", Icons.celebration_rounded,
      Color(0xFFEC4899)),
  ThoughtMood("resting", "Resting", Icons.bedtime_rounded, Color(0xFF6366F1)),
  ThoughtMood("hungry", "Hungry", Icons.restaurant_rounded, Color(0xFFF97316)),
];

ThoughtMood? thoughtMoodOf(String? key) {
  for (final mood in thoughtMoods) {
    if (mood.key == key) return mood;
  }
  return null;
}

/// Characters as a person counts them (emoji = 1), which is what the
/// server's 60-character limit counts too.
int ephemeralCharCount(String text) => text.runes.length;

/// "22h left" / "35m left" / "Expired".
String ephemeralTimeLeft(DateTime? expiresAt, {DateTime? now}) {
  if (expiresAt == null) return "";
  final left = expiresAt.difference(now ?? DateTime.now());
  if (left.isNegative) return "Expired";
  if (left.inHours >= 1) return "${left.inHours}h left";
  return "${left.inMinutes.clamp(1, 59)}m left";
}

/// How much of a 24h lifetime is left, 0..1 - a tile's remaining bar.
double ephemeralRemainingFraction(DateTime? expiresAt, {DateTime? now}) {
  if (expiresAt == null) return 0;
  final left = expiresAt.difference(now ?? DateTime.now()).inSeconds;
  return (left / const Duration(hours: 24).inSeconds).clamp(0.0, 1.0);
}

/// "Just now" / "12m" / "3h".
String ephemeralTimeAgo(DateTime? at, {DateTime? now}) {
  if (at == null) return "";
  final ago = (now ?? DateTime.now()).difference(at);
  if (ago.inMinutes < 1) return "Just now";
  if (ago.inHours < 1) return "${ago.inMinutes}m";
  if (ago.inDays < 1) return "${ago.inHours}h";
  return "${ago.inDays}d";
}

DateTime? _date(dynamic raw) =>
    raw == null ? null : DateTime.tryParse(raw.toString())?.toLocal();

int _int(dynamic raw) => raw is num ? raw.toInt() : 0;

Map<String, dynamic> _map(dynamic raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

List<Map<String, dynamic>> _maps(dynamic raw) => raw is List
    ? raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : const [];

/// The newest moment of a tray entry, enough for its tile.
class MomentPreview {
  final String postId;
  final String caption;
  final bool isShared;
  final String? thumbnail;
  final String mediaType;
  final DateTime? expiresAt;

  const MomentPreview({
    required this.postId,
    required this.caption,
    required this.isShared,
    required this.thumbnail,
    required this.mediaType,
    this.expiresAt,
  });

  bool get isVideo => mediaType.contains("video");

  factory MomentPreview.fromJson(Map<String, dynamic> json) {
    final thumb = json["thumbnail"]?.toString();
    return MomentPreview(
      postId: (json["post_id"] ?? "").toString(),
      caption: (json["caption"] ?? "").toString(),
      isShared: json["is_shared"] == true,
      thumbnail: (thumb == null || thumb.isEmpty) ? null : thumb,
      mediaType: (json["media_type"] ?? "").toString(),
      expiresAt: _date(json["expires_at"]),
    );
  }
}

/// One entity on the Moments board.
class MomentTrayEntry {
  final PostPreviewAuthor author;
  final bool isSelf;
  final int momentCount;
  final int unseenCount;
  final bool hasUnseen;
  final String startPostId;
  final DateTime? latestAt;
  final MomentPreview? latest;

  const MomentTrayEntry({
    required this.author,
    required this.isSelf,
    required this.momentCount,
    required this.unseenCount,
    required this.hasUnseen,
    required this.startPostId,
    required this.latestAt,
    required this.latest,
  });

  factory MomentTrayEntry.fromJson(Map<String, dynamic> json) =>
      MomentTrayEntry(
        author: PostPreviewAuthor.fromEntityJson(json["entity"]),
        isSelf: json["is_self"] == true,
        momentCount: _int(json["moment_count"]),
        unseenCount: _int(json["unseen_count"]),
        hasUnseen: json["has_unseen"] == true,
        startPostId: (json["start_post_id"] ?? "").toString(),
        latestAt: _date(json["latest_at"]),
        latest: json["latest"] is Map
            ? MomentPreview.fromJson(_map(json["latest"]))
            : null,
      );
}

class MomentTray {
  final List<MomentTrayEntry> results;
  final int newCount;
  final int total;

  const MomentTray(
      {required this.results, required this.newCount, this.total = 0});

  static const empty = MomentTray(results: [], newCount: 0);

  MomentTrayEntry? get mine {
    for (final entry in results) {
      if (entry.isSelf) return entry;
    }
    return null;
  }

  factory MomentTray.fromJson(Map<String, dynamic> json) => MomentTray(
        results: _maps(json["results"]).map(MomentTrayEntry.fromJson).toList(),
        newCount: _int(json["new_count"]),
        total: _int(json["total"]),
      );
}

/// An avatar's moment ring: absent = no live moment.
class MomentRing {
  final bool hasUnseen;
  final String startPostId;

  const MomentRing({required this.hasUnseen, required this.startPostId});

  factory MomentRing.fromJson(Map<String, dynamic> json) => MomentRing(
        hasUnseen: json["has_unseen"] == true,
        startPostId: (json["start_post_id"] ?? "").toString(),
      );
}

/// One moment as the viewer plays it.
class Moment {
  final PostPreview post;
  final DateTime? expiresAt;
  final bool allowReplies;
  final bool seen;

  /// A shared-post moment's single reference is the shared POST's id, with
  /// media type "shared_post".
  final bool isShared;

  /// A shared-post moment's preview image/video, resolved server-side (the
  /// shared post's first media, or the original's when it is a re-share).
  final String? sharedThumbnail;
  final String? sharedMediaType;

  const Moment({
    required this.post,
    required this.expiresAt,
    required this.allowReplies,
    required this.seen,
    required this.isShared,
    this.sharedThumbnail,
    this.sharedMediaType,
  });

  /// What a small tile shows: the photo, or the shared post's photo. Videos
  /// have no still here, so they get null and an icon.
  String? get thumbnail {
    if (isShared) {
      return sharedMediaType?.contains("video") == true
          ? null
          : sharedThumbnail;
    }
    final m = media;
    return m != null && m.isImage ? m.reference : null;
  }

  bool get isVideo => isShared
      ? sharedMediaType?.contains("video") == true
      : media?.isVideo == true;

  /// Archived by hand while its 24h were not over: it can still go back on
  /// the board, until the moment it would have expired anyway.
  ///
  /// "Archived" is the flag, or - for moments archived the earlier way - a
  /// timer that was ended before its natural end (posted + 24h). Unarchiving
  /// restores that natural end, so both kinds come back.
  bool get canUnarchive {
    final end = naturalEnd;
    if (end == null || !end.isAfter(DateTime.now())) return false;
    final endedEarly = expiresAt != null &&
        expiresAt!.isBefore(end.subtract(const Duration(minutes: 1)));
    return post.isArchived || endedEarly;
  }

  /// When this moment's 24h are up - what it runs until once unarchived.
  DateTime? get naturalEnd =>
      post.datePosted?.toLocal().add(const Duration(hours: 24));

  /// The video to take a first frame from, for a tile - null unless a video.
  String? get videoSrc =>
      !isVideo ? null : (isShared ? sharedThumbnail : media?.reference);

  PostReference? get media =>
      post.references.isEmpty ? null : post.references.first;

  String? get sharedPostId => isShared ? media?.reference : null;

  factory Moment.fromJson(Map<String, dynamic> json) {
    final details = _map(json["details"]);
    final shared = _map(json["shared_preview"]);
    final sharedThumb = shared["thumbnail"]?.toString();
    return Moment(
      post: PostPreview.fromJson(json),
      expiresAt: _date(json["expires_at"]),
      // Absent = allowed: moments predating the toggle took replies.
      allowReplies: details["allow_replies"] != false,
      seen: json["seen"] == true,
      isShared: json["file_type"] == "shared_post",
      sharedThumbnail:
          (sharedThumb == null || sharedThumb.isEmpty) ? null : sharedThumb,
      sharedMediaType: shared["media_type"]?.toString(),
    );
  }
}

class Thought {
  final String postId;
  final String entityId;
  final String text;
  final String? mood;
  final String privacyStatus;
  final DateTime? datePosted;
  final DateTime? expiresAt;

  /// The viewer's reaction (emoji id) on someone else's thought.
  final String? myReaction;

  /// Only on your own thought.
  final int? views;
  final PostPreviewAuthor? author;

  const Thought({
    required this.postId,
    required this.entityId,
    required this.text,
    required this.mood,
    required this.privacyStatus,
    required this.datePosted,
    required this.expiresAt,
    this.myReaction,
    this.views,
    this.author,
  });

  factory Thought.fromJson(Map<String, dynamic> json) {
    final content = _map(json["content"]);
    final mood = content["mood"]?.toString();
    final reaction = json["my_reaction"]?.toString();
    return Thought(
      postId: (json["post_id"] ?? "").toString(),
      entityId: (json["entity_id"] ?? "").toString(),
      text: (content["text"] ?? "").toString(),
      mood: (mood == null || mood.isEmpty) ? null : mood,
      privacyStatus: (json["privacy_status"] ?? "public").toString(),
      datePosted: _date(json["date_posted"]),
      expiresAt: _date(json["expires_at"]),
      myReaction: (reaction == null || reaction.isEmpty) ? null : reaction,
      views: json["views"] is num ? (json["views"] as num).toInt() : null,
      author: json["author"] is Map
          ? PostPreviewAuthor.fromEntityJson(json["author"])
          : null,
    );
  }
}

class ThoughtsRail {
  final Thought? mine;
  final List<Thought> results;

  /// Only when [results] is empty: connections, most-interacted first - so
  /// the rail is never an empty strip. Online ones are put first client-side.
  final List<PostPreviewAuthor> suggestions;

  const ThoughtsRail(
      {required this.mine, required this.results, this.suggestions = const []});

  static const empty = ThoughtsRail(mine: null, results: []);

  factory ThoughtsRail.fromJson(Map<String, dynamic> json) => ThoughtsRail(
        mine: json["mine"] is Map ? Thought.fromJson(_map(json["mine"])) : null,
        results: _maps(json["results"]).map(Thought.fromJson).toList(),
        suggestions: (json["suggestions"] is List
                ? (json["suggestions"] as List).whereType<Map>()
                : const <Map>[])
            .map(PostPreviewAuthor.fromEntityJson)
            .where((a) => a.entityId.isNotEmpty)
            .toList(),
      );
}

/// Who saw your moment / thought, and what they did.
class EphemeralViewer {
  final PostPreviewAuthor entity;
  final DateTime? viewedAt;

  /// Latest of their view, reaction and reply - what the row's time shows.
  final DateTime? lastActivityAt;
  final String? reactionEmoji;
  final bool replied;

  const EphemeralViewer({
    required this.entity,
    required this.viewedAt,
    this.lastActivityAt,
    required this.reactionEmoji,
    required this.replied,
  });

  factory EphemeralViewer.fromJson(Map<String, dynamic> json) =>
      EphemeralViewer(
        entity: PostPreviewAuthor.fromEntityJson(json["entity"]),
        viewedAt: _date(json["viewed_at"]),
        lastActivityAt: _date(json["last_activity_at"]),
        reactionEmoji: json["reaction"] is Map
            ? _map(json["reaction"])["emoji"]?.toString()
            : null,
        replied: json["replied"] == true,
      );
}

class EphemeralViewers {
  final List<EphemeralViewer> results;
  final bool hasMore;
  final int views;
  final int reactions;
  final int replies;

  const EphemeralViewers({
    required this.results,
    required this.hasMore,
    required this.views,
    required this.reactions,
    required this.replies,
  });

  static const empty = EphemeralViewers(
      results: [], hasMore: false, views: 0, reactions: 0, replies: 0);

  factory EphemeralViewers.fromJson(Map<String, dynamic> json) {
    final totals = _map(json["totals"]);
    return EphemeralViewers(
      results: _maps(json["results"]).map(EphemeralViewer.fromJson).toList(),
      hasMore: json["next"] != null,
      views: _int(totals["views"]),
      reactions: _int(totals["reactions"]),
      replies: _int(totals["replies"]),
    );
  }
}
