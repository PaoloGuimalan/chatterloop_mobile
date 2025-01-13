import 'dart:math';

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

  int generateRandomNumber(int digits) {
    if (digits < 1) {
      throw Exception("Number of digits must be at least 1");
    }
    final random = Random();
    int min = pow(10, digits - 1).toInt();
    int max = pow(10, digits).toInt() - 1;

    if (max <= 4294967296) {
      return random.nextInt(max - min + 1) + min;
    } else {
      return random.nextInt(4294967296) + min;
    }
  }

  void printer(dynamic data) {
    if (kDebugMode) {
      print(data);
    }
  }
}
