import 'package:chatterloop_app/models/messages_models/messages_list_model.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_state_model.dart';
import 'package:chatterloop_app/models/post_models/user_post_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';

class AppState {
  UserAuth userAuth;
  List<UserPost> posts;
  List<MessageItem> messages;
  List<UserContacts> contacts;
  NotificationsStateModel notificationsstate;
  List<IsTypingMetaData> isTypingList;
  bool isUsingReplyAssist;
  List<ReplyAssistContext> replyAssistContext;

  AppState(
      {this.userAuth = const UserAuth(
          null,
          UserAccount("", UserFullname("", "", ""), "", false, false, null,
              null, null, null)),
      this.posts = const [],
      this.messages = const [],
      this.contacts = const [],
      this.isTypingList = const [],
      this.notificationsstate = const NotificationsStateModel([], 0),
      this.isUsingReplyAssist = false,
      this.replyAssistContext = const []});

  AppState copyWith(
      {UserAuth? authState,
      List<UserPost>? postslist,
      List<MessageItem>? messageslist,
      List<UserContacts>? contactslist,
      List<IsTypingMetaData>? istypinglistprop,
      NotificationsStateModel? notificationsstateprop,
      bool? isUsingReplyAssistProp,
      List<ReplyAssistContext>? replyAssistContextProp}) {
    return AppState(
        userAuth: authState ?? userAuth,
        posts: postslist ?? posts,
        messages: messageslist ?? messages,
        contacts: contactslist ?? contacts,
        isTypingList: istypinglistprop ?? isTypingList,
        notificationsstate: notificationsstateprop ?? notificationsstate,
        isUsingReplyAssist: isUsingReplyAssistProp ?? isUsingReplyAssist,
        replyAssistContext: replyAssistContextProp ?? replyAssistContext);
  }
}
