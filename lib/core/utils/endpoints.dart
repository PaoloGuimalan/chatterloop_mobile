class Endpoints {
  /// Sent as the Origin header on every request - both backends 403/reject
  /// requests with no Origin at all (checked for presence only, not value).
  static const String origin = 'https://chatterloop.app';

  String apiUrl = 'https://realtime.chatterloop.app';
  String userApiUrl = 'https://user.chatterloop.app';
  String sseRoute = '/u/sseNotifications/';

  String jwtChecker = '/auth/jwtchecker';
  String login = '/api/user/auth';
  String signup = '/api/user/me';
  String verifyEmail = '/api/user/verification';
  String getPosts = '/posts/feed';
  String getContacts = '/u/getContacts';
  String getNotifications = '/u/getNotifications';
  String readNotifications = '/u/readnotifications';

  String getConversationList = '/u/initConversationList';
  String initConversation = '/u/initConversation/'; // :conversationID
  String getConversationInfo =
      '/m/conversationinfo/'; // :conversationID/:conversationType (single, group, server)
  String seenNewMessages = '/u/seenNewMessages';
  String postIsTyping = '/m/istypingbroadcast';
  String sendNewMessage = '/u/sendMessage';
  String replyAssist = '/prompt/reply-assist';
}
