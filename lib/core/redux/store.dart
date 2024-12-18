import 'package:chatterloop_app/core/redux/actions.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:redux/redux.dart';

ReduxActions reducers = ReduxActions();

AppState _setUserAuth(AppState state, dynamic action) {
  return state.copyWith(
      authState: reducers.setUserAuth(state, action).userAuth);
}

AppState _setFeedPosts(AppState state, dynamic action) {
  return state.copyWith(postslist: reducers.setFeedPosts(state, action).posts);
}

final appReducer = combineReducers<AppState>([
  TypedReducer<AppState, dynamic>(_setUserAuth).call,
  TypedReducer<AppState, dynamic>(_setFeedPosts).call
]);

class StateStore {
  final Store<AppState> store =
      Store<AppState>(appReducer, initialState: AppState());
}
