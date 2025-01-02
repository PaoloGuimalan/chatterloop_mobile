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
        json["userID"],
        json["activeSkinTone"],
        json["emoji"],
        json["imageUrl"],
        json["isCustom"],
        (json["names"] as List).map((name) => name.toString()).toList(),
        json["unified"],
        json["unifiedWithoutSkinTone"]);
  }
}
