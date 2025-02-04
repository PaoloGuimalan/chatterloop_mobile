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

AppState _setNotificationsList(AppState state, dynamic action) {
  return state.copyWith(
      notificationsstateprop:
          reducers.setNotificationsList(state, action).notificationsstate);
}

AppState _setIsTypingList(AppState state, dynamic action) {
  return state.copyWith(
      istypinglistprop: reducers.setIsTypingList(state, action).isTypingList);
}

AppState _setIsUsingReplyAssist(AppState state, dynamic action) {
  return state.copyWith(
      isUsingReplyAssistProp:
          reducers.setIsUsingReplyAssist(state, action).isUsingReplyAssist);
}

AppState _setReplyAssistContext(AppState state, dynamic action) {
  return state.copyWith(
      replyAssistContextProp:
          reducers.setReplyAssistContext(state, action).replyAssistContext);
}

final appReducer = combineReducers<AppState>([
  TypedReducer<AppState, dynamic>(_setUserAuth).call,
  TypedReducer<AppState, dynamic>(_setFeedPosts).call,
  TypedReducer<AppState, dynamic>(_setMessagesList).call,
  TypedReducer<AppState, dynamic>(_setContactsList).call,
  TypedReducer<AppState, dynamic>(_setIsTypingList).call,
  TypedReducer<AppState, dynamic>(_setNotificationsList).call,
  TypedReducer<AppState, dynamic>(_setIsUsingReplyAssist).call,
  TypedReducer<AppState, dynamic>(_setReplyAssistContext).call
]);

class StateStore {
  final Store<AppState> store =
      Store<AppState>(appReducer, initialState: AppState());
}
