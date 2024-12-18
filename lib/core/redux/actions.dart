import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';

class ReduxActions {
  AppState setUserAuth(AppState state, DispatchModel action) {
    switch (action.type) {
      case setUserAuthT:
        return AppState(userAuth: action.payload);
      default:
        return state;
    }
  }

  AppState setFeedPosts(AppState state, DispatchModel action) {
    switch (action.type) {
      case setFeedPostsT:
        return AppState(posts: action.payload);
      default:
        return state;
    }
  }
}
