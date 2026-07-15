import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';

// call_session_model.dart/incoming_call_alert_model.dart types flow through
// as action.payload (dynamic) below - no direct import needed here, same as
// every other reducer method in this file.

class ReduxActions {
  AppState setUserAuth(AppState state, DispatchModel action) {
    switch (action.type) {
      case setUserAuthT:
        return AppState(userAuth: action.payload);
      default:
        return state;
    }
  }

  AppState resetAppState(AppState state, DispatchModel action) {
    switch (action.type) {
      case resetAppStateT:
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

  AppState setActiveUsersList(AppState state, DispatchModel action) {
    switch (action.type) {
      case setActiveUsersListT:
        return AppState(presence: action.payload);
      default:
        return state;
    }
  }

  AppState updateActiveUser(AppState state, DispatchModel action) {
    switch (action.type) {
      case updateActiveUserT:
        ActiveUserUpdate payload = action.payload;
        Map<String, PresenceInfo> updated =
            Map<String, PresenceInfo>.from(state.presence);
        updated[payload.entityId] = PresenceInfo(
            online: payload.isOnline,
            lastSeen: payload.isOnline ? null : payload.lastSeen);
        return AppState(presence: updated);
      default:
        return state;
    }
  }

  AppState setIsUsingReplyAssist(AppState state, DispatchModel action) {
    switch (action.type) {
      case setIsUsingReplyAssistT:
        return AppState(isUsingReplyAssist: action.payload);
      default:
        return state;
    }
  }

  AppState setReplyAssistContext(AppState state, DispatchModel action) {
    switch (action.type) {
      case setReplyAssistContextT:
        ReplyAssistContext payload = action.payload;
        List<ReplyAssistContext> currentList = state.replyAssistContext
            .where((replyAssist) => replyAssist.messageID != payload.messageID)
            .toList();
        return AppState(replyAssistContext: [...currentList, payload]);
      case removeReplyAssistContextT:
        ReplyAssistContext payload = action.payload;
        List<ReplyAssistContext> currentList = state.replyAssistContext
            .where((replyAssist) => replyAssist.messageID != payload.messageID)
            .toList();
        return AppState(replyAssistContext: [...currentList]);
      case clearReplyAssistContextT:
        return AppState(replyAssistContext: []);
      default:
        return state;
    }
  }

  /// clearCurrentCallT is handled directly in store.dart's wrapper (via
  /// AppState.copyWith's clearCurrentCallProp flag) instead of here -
  /// currentCall is nullable, so "clear" can't be expressed by returning
  /// AppState(currentCall: null) and extracting it the way every other
  /// slice above does (copyWith's `?? currentCall` fallback would just
  /// treat that null as "no change").
  AppState setCurrentCall(AppState state, DispatchModel action) {
    switch (action.type) {
      case setCurrentCallT:
        return AppState(currentCall: action.payload);
      default:
        return state;
    }
  }

  /// Same nullable-clear caveat as setCurrentCall above -
  /// clearPendingIncomingCallT is handled directly in store.dart.
  AppState setPendingIncomingCall(AppState state, DispatchModel action) {
    switch (action.type) {
      case setPendingIncomingCallT:
        return AppState(pendingIncomingCall: action.payload);
      default:
        return state;
    }
  }
}
