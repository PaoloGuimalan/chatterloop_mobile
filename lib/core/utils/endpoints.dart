class Endpoints {
  String apiUrl = 'https://chatterloop.onrender.com';
  String sseRoute = '/u/sseNotifications/';

  String jwtChecker = '/auth/jwtchecker';
  String login = '/auth/login';
  String getPosts = '/posts/feed';
  String getContacts = '/u/getContacts';

  String getConversationList = '/u/initConversationList';
  String initConversation = '/u/initConversation/'; // :conversationID
  String getConversationInfo =
      '/m/conversationinfo/'; // :conversationID/:conversationType (single, group, server)
  String seenNewMessages = '/u/seenNewMessages';
}
