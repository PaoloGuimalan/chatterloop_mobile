import 'package:chatterloop_app/models/messages_models/messages_list_model.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_state_model.dart';
import 'package:chatterloop_app/models/post_models/user_post_model.dart';
import 'package:chatterloop_app/models/user_models/contact_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';

class AppState {
  UserAuth userAuth;
  List<UserPost> posts;
  List<MessageItem> messages;
  List<Contact> contacts;
  NotificationsStateModel notificationsstate;
  List<IsTypingMetaData> isTypingList;
  bool isUsingReplyAssist;
  List<ReplyAssistContext> replyAssistContext;

  /// Online status + last-seen time per entity id, among contacts only -
  /// matches the server's own scope (UpdateContactswSessionStatus only
  /// ever notifies confirmed contacts of a session change), so this never
  /// needs filtering by relationship on the read side.
  Map<String, PresenceInfo> presence;

  AppState(
      {this.userAuth = const UserAuth(
          null,
          UserAccount(
              "", "", "", "", "", "", false, false, null, null, null, null)),
      this.posts = const [],
      this.messages = const [],
      this.contacts = const [],
      this.isTypingList = const [],
      this.notificationsstate = const NotificationsStateModel([], 0),
      this.isUsingReplyAssist = false,
      this.replyAssistContext = const [],
      this.presence = const {}});

  AppState copyWith(
      {UserAuth? authState,
      List<UserPost>? postslist,
      List<MessageItem>? messageslist,
      List<Contact>? contactslist,
      List<IsTypingMetaData>? istypinglistprop,
      NotificationsStateModel? notificationsstateprop,
      bool? isUsingReplyAssistProp,
      List<ReplyAssistContext>? replyAssistContextProp,
      Map<String, PresenceInfo>? presenceProp}) {
    return AppState(
        userAuth: authState ?? userAuth,
        posts: postslist ?? posts,
        messages: messageslist ?? messages,
        contacts: contactslist ?? contacts,
        isTypingList: istypinglistprop ?? isTypingList,
        notificationsstate: notificationsstateprop ?? notificationsstate,
        isUsingReplyAssist: isUsingReplyAssistProp ?? isUsingReplyAssist,
        replyAssistContext: replyAssistContextProp ?? replyAssistContext,
        presence: presenceProp ?? presence);
  }
}
