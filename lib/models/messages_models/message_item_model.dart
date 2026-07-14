class ReactionItem {
  final String userID;
  final String activeSkinTone;
  final dynamic emoji;
  final String imageUrl;
  final bool isCustom;
  final List<String> names;
  final String unified;
  final String unifiedWithoutSkinTone;

  ReactionItem(this.userID, this.activeSkinTone, this.emoji, this.imageUrl,
      this.isCustom, this.names, this.unified, this.unifiedWithoutSkinTone);

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
        (json["unifiedWithoutSkinTone"] ?? "").toString());
  }
}
