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

AppState _setMessagesList(AppState state, dynamic action) {
  return state.copyWith(
      messageslist: reducers.setMessagesList(state, action).messages);
}

AppState _setContactsList(AppState state, dynamic action) {
  return state.copyWith(
      contactslist: reducers.setContactsList(state, action).contacts);
}

AppState _setIsTypingList(AppState state, dynamic action) {
  return state.copyWith(
      istypinglistprop: reducers.setIsTypingList(state, action).isTypingList);
}

final appReducer = combineReducers<AppState>([
  TypedReducer<AppState, dynamic>(_setUserAuth).call,
  TypedReducer<AppState, dynamic>(_setFeedPosts).call,
  TypedReducer<AppState, dynamic>(_setMessagesList).call,
  TypedReducer<AppState, dynamic>(_setContactsList).call,
  TypedReducer<AppState, dynamic>(_setIsTypingList).call
]);

class StateStore {
  final Store<AppState> store =
      Store<AppState>(appReducer, initialState: AppState());
}
