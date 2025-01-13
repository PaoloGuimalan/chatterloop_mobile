class IsReplying {
  bool isReply;
  String replyingTo;

  IsReplying(this.isReply, this.replyingTo);

  factory IsReplying.fromJson(Map<String, dynamic> json) {
    return IsReplying(json["isReply"], json["replyingTo"]);
  }
}

class PendingMessages {
  String conversationID;
  String pendingID;
  String content;
  String type;

  PendingMessages(this.conversationID, this.pendingID, this.content, this.type);

  factory PendingMessages.fromJson(Map<String, dynamic> json) {
    return PendingMessages(json["conversationID"], json["pendingID"],
        json["content"], json["type"]);
  }
}
