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
