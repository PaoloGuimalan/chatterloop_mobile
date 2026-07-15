import 'package:chatterloop_app/core/redux/actions.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:redux/redux.dart';

ReduxActions reducers = ReduxActions();

AppState _setUserAuth(AppState state, dynamic action) {
  return state.copyWith(
      authState: reducers.setUserAuth(state, action).userAuth);
}

/// Unlike every other reducer wrapper here, this does NOT copyWith back onto
/// the existing state - reducers.resetAppState already returns a complete
/// fresh AppState (see its doc comment), and merging it in via copyWith
/// would defeat the entire point by re-preserving the old messages/contacts/
/// notifications/presence/etc. this action exists to clear.
AppState _resetAppState(AppState state, dynamic action) {
  return reducers.resetAppState(state, action);
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

AppState _setActiveUsersList(AppState state, dynamic action) {
  return state.copyWith(
      presenceProp: reducers.setActiveUsersList(state, action).presence);
}

AppState _updateActiveUser(AppState state, dynamic action) {
  return state.copyWith(
      presenceProp: reducers.updateActiveUser(state, action).presence);
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

AppState _setCurrentCall(AppState state, dynamic action) {
  return state.copyWith(
      currentCallProp: reducers.setCurrentCall(state, action).currentCall);
}

/// Nullable-field clear - see AppState.copyWith's clearCurrentCallProp and
/// ReduxActions.setCurrentCall's doc comment for why this bypasses
/// reducers.dart entirely instead of following the usual extraction
/// pattern. Every wrapper in this file is registered as a TypedReducer
/// parameterized on AppState and dynamic, so combineReducers invokes ALL of them
/// on EVERY dispatch regardless of action.type (dynamic matches
/// everything) - the other wrappers stay safe by delegating to a
/// reducers.xyz method that internally switches on action.type and
/// no-ops (returns state unchanged) for anything else. This one has no
/// such method to delegate to, so it must do that action.type check
/// itself - skipping it would clear currentCall on literally every
/// Redux dispatch in the app, not just this action.
AppState _clearCurrentCall(AppState state, dynamic action) {
  if (action is DispatchModel && action.type == clearCurrentCallT) {
    return state.copyWith(clearCurrentCallProp: true);
  }
  return state;
}

AppState _setPendingIncomingCall(AppState state, dynamic action) {
  return state.copyWith(
      pendingIncomingCallProp:
          reducers.setPendingIncomingCall(state, action).pendingIncomingCall);
}

/// Same reasoning as _clearCurrentCall above.
AppState _clearPendingIncomingCall(AppState state, dynamic action) {
  if (action is DispatchModel && action.type == clearPendingIncomingCallT) {
    return state.copyWith(clearPendingIncomingCallProp: true);
  }
  return state;
}

final appReducer = combineReducers<AppState>([
  TypedReducer<AppState, dynamic>(_setUserAuth).call,
  TypedReducer<AppState, dynamic>(_resetAppState).call,
  TypedReducer<AppState, dynamic>(_setFeedPosts).call,
  TypedReducer<AppState, dynamic>(_setMessagesList).call,
  TypedReducer<AppState, dynamic>(_setContactsList).call,
  TypedReducer<AppState, dynamic>(_setIsTypingList).call,
  TypedReducer<AppState, dynamic>(_setNotificationsList).call,
  TypedReducer<AppState, dynamic>(_setActiveUsersList).call,
  TypedReducer<AppState, dynamic>(_updateActiveUser).call,
  TypedReducer<AppState, dynamic>(_setIsUsingReplyAssist).call,
  TypedReducer<AppState, dynamic>(_setReplyAssistContext).call,
  TypedReducer<AppState, dynamic>(_setCurrentCall).call,
  TypedReducer<AppState, dynamic>(_clearCurrentCall).call,
  TypedReducer<AppState, dynamic>(_setPendingIncomingCall).call,
  TypedReducer<AppState, dynamic>(_clearPendingIncomingCall).call,
]);

class StateStore {
  final Store<AppState> store =
      Store<AppState>(appReducer, initialState: AppState());
}

/// Single app-wide store instance, accessible without a BuildContext - used
/// by code that runs outside the widget tree (SSE event handling) instead
/// of the old AppRoutes.navigatorKey.currentContext! fallback pattern.
final Store<AppState> appStore = StateStore().store;
