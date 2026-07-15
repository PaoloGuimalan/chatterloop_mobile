class ReactionItem {
  final String userID;
  final String activeSkinTone;
  final dynamic emoji;
  final String imageUrl;
  final bool isCustom;
  final List<String> names;
  final String unified;
  final String unifiedWithoutSkinTone;

  /// The real, currently-written shape (server's routes/messages/index.js
  /// POST /m/addreaction just $push'es {userID, entityID, emoji} verbatim)
  /// only ever populates userID/emoji/entityID - the rest above are dead
  /// fields left over from an earlier emoji-mart-shaped prototype, kept
  /// only because fromJson still tolerates them if a legacy doc has them.
  final String entityID;

  ReactionItem(this.userID, this.activeSkinTone, this.emoji, this.imageUrl,
      this.isCustom, this.names, this.unified, this.unifiedWithoutSkinTone,
      [this.entityID = ""]);

  factory ReactionItem.fromJson(Map<String, dynamic> json) {
    return ReactionItem(
        (json["userID"] ?? "").toString(),
        (json["activeSkinTone"] ?? "").toString(),
        json["emoji"],
        (json["imageUrl"] ?? "").toString(),
        json["isCustom"] == true,
        json["names"] is List
            ? (json["names"] as List).map((name) => name.toString()).toList()
            : [],
        (json["unified"] ?? "").toString(),
        (json["unifiedWithoutSkinTone"] ?? "").toString(),
        (json["entityID"] ?? "").toString());
  }
}
