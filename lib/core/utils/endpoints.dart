class Endpoints {
  /// Sent as the Origin header on every request - both backends 403/reject
  /// requests with no Origin at all (checked for presence only, not value).
  static const String origin = 'https://chatterloop.app';

  String apiUrl = 'https://realtime.chatterloop.app';
  String userApiUrl = 'https://user.chatterloop.app';
  String sseRoute = '/u/sseNotifications/';

  String jwtChecker = '/auth/jwtchecker';
  String login = '/api/user/auth';

  /// Third-party (Google) auth - takes a Google ID token and logs the user
  /// in, auto-creating the account on first use. Same response shape as
  /// `login` (result: {authtoken, usertoken, allowed_modules, ...}). Mirrors
  /// webapp's ThirdPartyAuthenticationRequest -> POST /api/user/tp_auth.
  String tpAuth = '/api/user/tp_auth';
  String signup = '/api/user/me';
  String verifyEmail = '/api/user/verification';
  String updateProfile = '/api/user/me';
  String search = '/api/user/search/'; // :query
  String publicProfile = '/api/user/auth/'; // :username
  String contacts = '/api/user/contacts';
  String poke = '/api/user/poke';
  String getPosts = '/posts/feed';
  String getContacts = '/u/getContacts';
  String activeContacts = '/u/activecontacts';
  String getNotifications = '/u/getNotifications';
  String readNotifications = '/u/readnotifications';

  /// The real, live-wired conversation list endpoint (verified against
  /// webapp/src/app/tabs/feed/Messages.tsx -> InitConversationListRequest).
  /// The old /u/initConversationList this used to point at has zero call
  /// sites in the current webapp - dead/legacy, do not revert to it.
  String getConversationList = '/m/conversations';

  /// Resolves a conversation's setup/details (participants, display name,
  /// avatar) before anything else is fetched - critically, unlike
  /// initConversation/getConversationInfo below, this one synthesizes a
  /// valid response for a brand-new single conversation that has no Mongo
  /// Conversations doc yet (e.g. opened via a contact's Message button
  /// before any message was ever sent). Verified against webapp's
  /// InitConversationInfoRequest / ConversationV2.tsx, which gates its
  /// entire message-fetch effect on this resolving first - without it,
  /// that exact scenario left the screen spinning forever, per webapp's
  /// own comment on the same code path.
  String getConversationSetup = '/m/conversation/'; // :conversationID
  String initConversation = '/u/initConversation/'; // :conversationID
  String getConversationInfo =
      '/m/conversationinfo/'; // :conversationID/:conversationType (single, group, server)
  String seenNewMessages = '/u/seenNewMessages';
  String postIsTyping = '/m/istypingbroadcast';
  String sendNewMessage = '/u/sendMessage';
  String replyAssist = '/prompt/reply-assist';

  /// Combined upload+send endpoint for image/file/voice message attachments
  /// - unlike sendNewMessage above, this is a single multipart/form-data
  /// call that both stores the file(s) to object storage AND creates the
  /// UserMessage document server-side, matching webapp's SendFilesRequest
  /// exactly (server/routes/users/index.js's POST /u/sendFiles). No
  /// separate upload-then-create-post step like the profile photo flow.
  String sendFiles = '/u/sendFiles';

  /// Only mounted under the Messages router (server/index.js: app.use("/m",
  /// Messages)) - there is no /u/addreaction, unlike seenNewMessages/
  /// sendNewMessage above which happen to live under both routers.
  String addReaction = '/m/addreaction';

  /// Sender-only soft delete - server sets UserMessage.isDeleted = true and
  /// broadcasts it over the same "messages_list" SSE channel (payload gets
  /// a deletedMessageID field), matching webapp's DeleteMessageRequest.
  String deleteMessage = '/m/deletemessage';

  /// Realms/pages this account administers (filtered client-side to
  /// is_admin) - powers the "Switch account" list, matches webapp's
  /// EntitySwitcher -> GetMyRealmsRequest(1, 20, "page").
  String myRealms = '/api/realm/my-list';

  /// {realm_id} -> re-issues the authtoken with a different `entity` claim
  /// (same userID, acting as the page instead). Only realms of type "page"
  /// support this; server enforces OWNER/ADMIN membership.
  String entitySwitch = '/api/user/entity/switch';

  /// Switches back to the account's own personal entity - 400s if already
  /// acting as yourself.
  String entitySwitchBack = '/api/user/entity/switch-back';

  // ─── Calling (Node backend) ──────────────────────────────────────────────
  // /u/call*: JWT-signed {token} bodies (see CallApi) - relay a signaling
  // event to the other participant(s) over their existing SSE connection.
  // /webrtc/*: plain JSON bodies (see WebrtcApi) - the mediasoup REST half
  // of the join-room -> create-transport -> produce/consume sequence; the
  // actual response data for each of these arrives asynchronously over SSE,
  // not in the HTTP response (server/routes/webrtc/index.js).

  /// Rings every other participant's device (JWT relay only - no mediasoup
  /// room is touched here).
  String call = '/u/call';
  String rejectCall = '/u/rejectcall';
  String endCall = '/u/endcall';

  String webrtcJoinRoom = '/webrtc/join-room';
  String webrtcCreateTransport = '/webrtc/create-transport';
  String webrtcTransportConnect = '/webrtc/transport-connect';
  String webrtcProduce = '/webrtc/produce';
  String webrtcConsume = '/webrtc/consume';
  String webrtcCloseProducer = '/webrtc/close-producer';
  String webrtcLeaveRoom = '/webrtc/leave-room';
  String webrtcParticipantStatus = '/webrtc/participant-status';
  String webrtcReconnect = '/webrtc/reconnect';

  /// Simulcast encoding presets ({camera, screenshare}, each a list of
  /// {rid, maxBitrate, scaleResolutionDownBy}) - plain synchronous JSON
  /// response (unlike the rest of /webrtc/*, this one isn't SSE-relayed).
  /// webapp fetches this before joining and passes it straight through to
  /// transport.produce()'s encodings param for camera video specifically.
  String webrtcEncodings = '/webrtc/encodings';
}
