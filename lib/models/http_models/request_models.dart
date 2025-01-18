class ISeenNewMessagesRequest {
  String conversationID;
  int range;
  List<String> receivers;

  ISeenNewMessagesRequest(this.conversationID, this.range, this.receivers);

  Map<String, dynamic> toJson() {
    return {
      'conversationID': conversationID,
      'range': range,
      'receivers': receivers
    };
  }

  factory ISeenNewMessagesRequest.fromJson(Map<String, dynamic> json) {
    return ISeenNewMessagesRequest(
        json["conversationID"],
        json["range"],
        (json["receivers"] as List)
            .map((receiver) => receiver.toString())
            .toList());
  }
}

class IisTypingRequest {
  String conversationID;
  List<String> receivers;

  IisTypingRequest(this.conversationID, this.receivers);

  Map<String, dynamic> toJson() {
    return {'conversationID': conversationID, 'receivers': receivers};
  }

  factory IisTypingRequest.fromJson(Map<String, dynamic> json) {
    return IisTypingRequest(
        json["conversationID"],
        (json["receivers"] as List)
            .map((receiver) => receiver.toString())
            .toList());
  }
}

class ISendMessagePayload {
  String conversationID;
  String pendingID;
  List<String> receivers;
  String content;
  bool isReply;
  String replyingTo;
  String messageType;
  String conversationType;

  ISendMessagePayload(
      this.conversationID,
      this.pendingID,
      this.receivers,
      this.content,
      this.isReply,
      this.replyingTo,
      this.messageType,
      this.conversationType);

  Map<String, dynamic> toJson() {
    return {
      'conversationID': conversationID,
      'pendingID': pendingID,
      'receivers': receivers,
      'content': content,
      'isReply': isReply,
      'replyingTo': replyingTo,
      'messageType': messageType,
      'conversationType': conversationType
    };
  }

  factory ISendMessagePayload.fromJson(Map<String, dynamic> json) {
    return ISendMessagePayload(
      json["conversationID"],
      json["pendingID"],
      (json["receivers"] as List)
          .map((receiver) => receiver.toString())
          .toList(),
      json["content"],
      json["isReply"],
      json["replyingTo"],
      json["messageType"],
      json["conversationType"],
    );
  }
}
