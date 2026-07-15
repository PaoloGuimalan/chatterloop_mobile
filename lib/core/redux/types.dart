const String setUserAuthT = "SET_USER_AUTH";

/// Unlike setUserAuthT (which merges the new auth into the existing state,
/// preserving messages/contacts/notifications/etc.), this wholesale-replaces
/// AppState with a fresh default instance carrying only the given userAuth -
/// used after an entity switch so every entity-scoped slice actually clears
/// instead of briefly showing the previous entity's stale data, matching
/// webapp's full page reload on switch.
const String resetAppStateT = "RESET_APP_STATE";
const String setFeedPostsT = "SET_FEED_POSTS";

const String setMessagesListT = "SET_MESSAGES_LIST";
const String setContactsListT = "SET_CONTACTS_LIST";
const String setNotificationsListT = "SET_NOTIFICATIONS_LIST";

const String setIsTypingListT = "SET_ISTYPING_LIST";
const String removeIsTypingListT = "REMOVE_ISTYPING_LIST";

/// Bulk-replace, from the one-time GET /u/activecontacts snapshot on app
/// init. Live changes after that come from individual "active_users" SSE
/// events instead (updateActiveUserT) - the snapshot alone would go stale
/// the moment a contact connects/disconnects after this app's own session
/// started.
const String setActiveUsersListT = "SET_ACTIVE_USERS_LIST";
const String updateActiveUserT = "UPDATE_ACTIVE_USER";

const String setIsUsingReplyAssistT = "SET_IS_USING_REPLY_ASSIST";

const String setReplyAssistContextT = "SET_REPLY_ASSIST_CONTEXT";
const String removeReplyAssistContextT = "REMOVE_REPLY_ASSIST_CONTEXT";
const String clearReplyAssistContextT = "CLEAR_REPLY_ASSIST_CONTEXT";
