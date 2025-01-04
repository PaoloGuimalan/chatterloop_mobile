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
