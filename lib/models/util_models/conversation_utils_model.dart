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

class IsTypingMetaData {
  String userID;
  String conversationID;

  Map<String, dynamic> toJson() {
    return {"userID": userID, "conversationID": conversationID};
  }

  IsTypingMetaData(this.userID, this.conversationID);

  factory IsTypingMetaData.fromJson(Map<String, dynamic> json) {
    return IsTypingMetaData(json["userID"], json["conversationID"]);
  }
}

class ReplyAssistContext {
  bool me;
  String messageID;

  ReplyAssistContext(this.me, this.messageID);

  Map<String, dynamic> toJson() {
    return {"me": me, "messageID": messageID};
  }

  factory ReplyAssistContext.fromJson(Map<String, dynamic> json) {
    return ReplyAssistContext(json["me"], json["messageID"]);
  }
}
