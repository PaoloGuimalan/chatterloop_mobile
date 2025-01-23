import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';

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

  AppState setMessagesList(AppState state, DispatchModel action) {
    switch (action.type) {
      case setMessagesListT:
        return AppState(messages: action.payload);
      default:
        return state;
    }
  }

  AppState setContactsList(AppState state, DispatchModel action) {
    switch (action.type) {
      case setContactsListT:
        return AppState(contacts: action.payload);
      default:
        return state;
    }
  }

  AppState setNotificationsList(AppState state, DispatchModel action) {
    switch (action.type) {
      case setNotificationsListT:
        return AppState(notificationsstate: action.payload);
      default:
        return state;
    }
  }

  AppState setIsTypingList(AppState state, DispatchModel action) {
    switch (action.type) {
      case setIsTypingListT:
        IsTypingMetaData payload = action.payload;
        List<IsTypingMetaData> currentList = state.isTypingList
            .where((typing) => !(typing.userID == payload.userID &&
                typing.conversationID == payload.conversationID))
            .toList();

        return AppState(isTypingList: [...currentList, payload]);
      case removeIsTypingListT:
        IsTypingMetaData payload = action.payload;
        List<IsTypingMetaData> currentList = state.isTypingList
            .where((typing) => !(typing.userID == payload.userID &&
                typing.conversationID == payload.conversationID))
            .toList();

        return AppState(isTypingList: currentList);
      default:
        return state;
    }
  }
}
