import 'package:chatterloop_app/models/user_models/user_auth_model.dart';

class AppState {
  UserAuth userAuth;

  AppState(
      {this.userAuth = const UserAuth(
          null, UserAccount("", UserFullname("", "", ""), "", false, false))});

  AppState copyWith({UserAuth? authState}) {
    return AppState(
      userAuth: authState ?? userAuth,
    );
  }
}
