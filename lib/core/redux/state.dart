import 'package:chatterloop_app/models/messages_models/messages_list_model.dart';
import 'package:chatterloop_app/models/post_models/user_post_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';

class AppState {
  UserAuth userAuth;
  List<UserPost> posts;
  List<MessageItem> messages;
  List<UserContacts> contacts;

  AppState(
      {this.userAuth = const UserAuth(
          null,
          UserAccount("", UserFullname("", "", ""), "", false, false, null,
              null, null, null)),
      this.posts = const [],
      this.messages = const [],
      this.contacts = const []});

  AppState copyWith(
      {UserAuth? authState,
      List<UserPost>? postslist,
      List<MessageItem>? messageslist,
      List<UserContacts>? contactslist}) {
    return AppState(
        userAuth: authState ?? userAuth,
        posts: postslist ?? posts,
        messages: messageslist ?? messages,
        contacts: contactslist ?? contacts);
  }
}
