import 'package:flutter/foundation.dart';

class ContentValidator {
  final String singleChatPreviewImage =
      'https://chatterloop.netlify.app/assets/default-e4788211.png';
  final String groupChatPreviewImage =
      'https://chatterloop.netlify.app/assets/group-chat-icon-d6f42fe5.jpg';
  final String serverMainPreviewImage =
      'https://chatterloop.netlify.app/assets/servericon-e125462b.png';

  late final Map<String, String> conversationTypeImage;

  ContentValidator() {
    conversationTypeImage = {
      "single": singleChatPreviewImage,
      "group": groupChatPreviewImage,
      "server": serverMainPreviewImage
    };
  }

  String validateConversationProfile(String? profile, String conversationType) {
    if (profile == null ||
        profile == "" ||
        profile == "N/A" ||
        profile == "none") {
      return conversationTypeImage[conversationType] as String;
    } else {
      return profile;
    }
  }

  void printer(dynamic data) {
    if (kDebugMode) {
      print(data);
    }
  }
}
