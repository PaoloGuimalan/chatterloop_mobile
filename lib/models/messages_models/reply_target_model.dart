/// What a message replies to - the server's `replyedtarget`, one shape for a
/// reply to a message, a post, a moment or a thought (server:
/// reusables/hooks/replyTargets.js).
///
/// A message reply keeps its quote in `replyedmessage` as it always has; this
/// is what draws the other three. `status` says whether there is still
/// something to show: `expired` for a moment/thought past its 24h, and
/// `unavailable` for anything deleted or hidden from this viewer.
library;

class ReplyTargetAuthor {
  final String entityId;
  final String type;
  final String displayName;
  final String handle;
  final String? profile;

  const ReplyTargetAuthor({
    required this.entityId,
    required this.type,
    required this.displayName,
    required this.handle,
    this.profile,
  });

  factory ReplyTargetAuthor.fromJson(Map<String, dynamic> json) {
    final profile = json["profile"]?.toString();
    return ReplyTargetAuthor(
      entityId: (json["entity_id"] ?? "").toString(),
      type: (json["type"] ?? "").toString(),
      displayName: (json["display_name"] ?? "").toString(),
      handle: (json["handle"] ?? "").toString(),
      profile: (profile == null || profile.isEmpty || profile == "none")
          ? null
          : profile,
    );
  }
}

class ReplyTarget {
  static const typeMessage = "message";
  static const typePost = "post";
  static const typeMoment = "moment";
  static const typeThought = "thought";

  final String type;
  final String id;

  /// "active" | "expired" | "unavailable".
  final String status;
  final ReplyTargetAuthor? author;

  /// A thought's text, or a message's.
  final String? text;

  /// A post's or moment's caption, already clipped to a line or two.
  final String? caption;
  final String? thumbnail;
  final String? mediaType;
  final String? fileType;

  /// Set when the post is itself a share: its single reference is the
  /// ORIGINAL post's id, which is where tapping the card should go.
  final String? sharedPostId;

  /// A moment's or thought's end of life. Null for posts and messages.
  final DateTime? expiresAt;

  /// A MESSAGE target whose message had no text of its own (a post sent into
  /// the chat, a moment or thought reply): the card it carried, which the
  /// quote draws instead of a "Sent a post" line.
  final ReplyTarget? attached;

  const ReplyTarget({
    required this.type,
    required this.id,
    required this.status,
    this.author,
    this.text,
    this.caption,
    this.thumbnail,
    this.mediaType,
    this.fileType,
    this.sharedPostId,
    this.expiresAt,
    this.attached,
  });

  bool get isMessage => type == typeMessage;

  bool get isUnavailable => status == "unavailable";

  /// Expired by the server's word OR by the clock since. A card that was live
  /// when the conversation loaded stops showing its moment once the 24h pass,
  /// without waiting for a reload.
  bool isExpiredAt(DateTime now) =>
      status == "expired" || (expiresAt != null && !expiresAt!.isAfter(now));

  bool isLiveAt(DateTime now) => !isUnavailable && !isExpiredAt(now);

  bool get isVideo => mediaType?.startsWith("video") == true;

  static ReplyTarget? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final type = (json["type"] ?? "").toString();
    final id = (json["id"] ?? "").toString();
    if (type.isEmpty || id.isEmpty) return null;

    final content = json["content"] is Map
        ? Map<String, dynamic>.from(json["content"])
        : const <String, dynamic>{};
    String? str(String key) {
      final value = content[key];
      return value == null || value.toString().isEmpty
          ? null
          : value.toString();
    }

    return ReplyTarget(
      type: type,
      id: id,
      status: (json["status"] ?? "unavailable").toString(),
      author: json["author"] is Map
          ? ReplyTargetAuthor.fromJson(
              Map<String, dynamic>.from(json["author"]))
          : null,
      text: str("text"),
      caption: str("caption"),
      thumbnail: str("thumbnail") ?? str("url"),
      mediaType: str("media_type"),
      fileType: str("file_type"),
      sharedPostId: str("shared_post_id"),
      expiresAt: DateTime.tryParse(str("expires_at") ?? "")?.toLocal(),
      attached: tryParse(content["attached"]),
    );
  }
}

/// A message's `replyingTo` as the id of the MESSAGE it replies to, or "".
///
/// The server sends it as that string (it stores {type, id} but keeps the
/// wire as it has always been, so installed builds are unaffected). The map
/// branch is defensive: should the stored object ever arrive, a message reply
/// still reads as its id rather than as the map's toString().
String replyingToMessageId(dynamic raw) {
  if (raw == null) return "";
  if (raw is Map) {
    return raw["type"]?.toString() == ReplyTarget.typeMessage
        ? (raw["id"] ?? "").toString()
        : "";
  }
  return raw.toString();
}
