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
  String updateProfile = '/api/user/me';
  String search = '/api/user/search/'; // :query
  String publicProfile = '/api/user/auth/'; // :username
  String contacts = '/api/user/contacts';
  String getPosts = '/posts/feed';
  String getContacts = '/u/getContacts';
  String getNotifications = '/u/getNotifications';
  String readNotifications = '/u/readnotifications';

  /// The real, live-wired conversation list endpoint (verified against
  /// webapp/src/app/tabs/feed/Messages.tsx -> InitConversationListRequest).
  /// The old /u/initConversationList this used to point at has zero call
  /// sites in the current webapp - dead/legacy, do not revert to it.
  String getConversationList = '/m/conversations';
  String initConversation = '/u/initConversation/'; // :conversationID
  String getConversationInfo =
      '/m/conversationinfo/'; // :conversationID/:conversationType (single, group, server)
  String seenNewMessages = '/u/seenNewMessages';
  String postIsTyping = '/m/istypingbroadcast';
  String sendNewMessage = '/u/sendMessage';
  String replyAssist = '/prompt/reply-assist';
}
