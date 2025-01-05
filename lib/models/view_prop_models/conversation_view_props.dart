class ConversationViewProps {
  String conversationID;
  String conversationType;
  ConversationPreview conversationPreview;

  ConversationViewProps(
      this.conversationID, this.conversationType, this.conversationPreview);
}

class ConversationPreview {
  String profile;
  String previewName;

  ConversationPreview(this.profile, this.previewName);
}
