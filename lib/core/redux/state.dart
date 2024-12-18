import 'package:chatterloop_app/models/post_models/user_post_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';

class AppState {
  UserAuth userAuth;
  List<UserPost> posts;

  AppState(
      {this.userAuth = const UserAuth(
          null,
          UserAccount("", UserFullname("", "", ""), "", false, false, null,
              null, null, null)),
      this.posts = const []});

  AppState copyWith({UserAuth? authState, List<UserPost>? postslist}) {
    return AppState(
      userAuth: authState ?? userAuth,
      posts: postslist ?? [],
    );
  }
}
