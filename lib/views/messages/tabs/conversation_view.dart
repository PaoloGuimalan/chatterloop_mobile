import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/requests/sse_connection.dart';
import 'package:chatterloop_app/core/reusables/loaders/spinning_loader.dart';
import 'package:chatterloop_app/core/reusables/loaders/typing_loader.dart';
import 'package:chatterloop_app/core/reusables/widgets/message_content_widget.dart';
import 'package:chatterloop_app/core/reusables/widgets/pending_content_widget.dart';
import 'package:chatterloop_app/core/utils/content_validator.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/core/calls/call_controller.dart';
import 'package:chatterloop_app/core/requests/call_api.dart';
import 'package:chatterloop_app/models/call_models/call_session_model.dart';
import 'package:chatterloop_app/models/call_models/call_signed_payloads_model.dart';
import 'package:chatterloop_app/models/call_models/incoming_call_alert_model.dart';
import 'package:chatterloop_app/models/http_models/request_models.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/messages_models/conversation_info_model.dart';
import 'package:chatterloop_app/models/messages_models/message_content_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:visibility_detector/visibility_detector.dart';

class ConversationView extends StatefulWidget {
  final String conversationId;

  const ConversationView({super.key, required this.conversationId});

  @override
  ConversationStateView createState() => ConversationStateView();
}

/// Matches webapp's ConversationV2.tsx MAX_ATTACHMENT_SIZE - files over
/// this are silently dropped client-side (mirrors webapp's toast: "Cannot
/// upload files greater than 25mb") rather than sent and rejected by the
/// server's own equal 25MB multiparty.Form({maxFilesSize}) limit.
const int _maxAttachmentBytes = 25 * 1024 * 1024;

class ConversationStateView extends State<ConversationView> {
  StreamSubscription<SSEModel>? _eventBusSubscription;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _controller = TextEditingController();
  final AudioRecorder _voiceRecorder = AudioRecorder();
  bool _isRecordingVoice = false;

  /// Attachments picked but not yet sent - matches webapp's composer
  /// staging (imgList/nonImgList in ConversationV2.tsx): picking no longer
  /// sends immediately, it queues here for review, and the actual send
  /// button flushes whatever's staged (plus any typed text) together in
  /// one go. Voice messages are the one exception - webapp sends those
  /// immediately on stop with no staging/preview step, so that flow is
  /// untouched here too.
  List<({String path, String messageType})> _stagedFiles = [];

  bool isInitialized = false;
  bool isSeenMessageInitialized = false;
  bool isAutoScroll = true;

  /// Accumulated by _queueMessageSeen as messages become visible on
  /// screen, flushed via _flushSeenMessages after a 500ms debounce -
  /// matches webapp's ConversationV2.tsx unreadmessages state.
  List<String> _unreadMessageIds = [];
  Timer? _seenDebounceTimer;
  bool isSettingUp = true;
  String? conversationLoadError;
  Map<String, dynamic>? conversationSetup;
  List<MessageContent> conversationContentList = [];
  List<PendingMessages> pendingMessagesList = [];
  late List<dynamic> combinedPendingAndMessagesList;
  ConversationInfoModel? conversationInfo;
  IsReplying isReplying = IsReplying(false, "");
  String messageValue = "";
  int range = 20;
  bool isTyping = false;
  bool isRefreshed = false;
  bool isTypingTimedOut = false;
  int totalMessages = 0;

  // Resolved once at mount, not recomputed per build - feeds the
  // initial-load kickoff below, which must only ever run once per screen
  // instance (see _startLoading's doc comment).
  late final String _myAccountId;

  @override
  void initState() {
    super.initState();
    // appStore (a plain global, not StoreProvider.of(context)) - the
    // latter calls dependOnInheritedWidgetOfExactType, which asserts if
    // used before initState() completes.
    _myAccountId = appStore.state.userAuth.user.entityId;
    combinedPendingAndMessagesList = [
      ...conversationContentList,
      ...pendingMessagesList
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.addListener(_onScroll);
    });
    _startLoading();
  }

  /// Kicks off the initial message/participant fetch and the SSE
  /// subscription exactly once, on mount. This used to live inline in
  /// build() guarded by `if (conversationContentList.isEmpty &&
  /// !isInitialized)` - but StoreConnector rebuilds this widget on every
  /// unrelated Redux change (typing, other conversations, notifications),
  /// and a build()-time guard re-enters on every one of those rebuilds
  /// until the async response lands, which under any rebuild pressure
  /// (or a slow/failed response) produced a visible request loop and, for
  /// the SSE listener specifically, re-subscribed a new listener on every
  /// re-entry without cancelling the previous one.
  ///
  /// Everything below is gated on getConversationSetupRequest resolving
  /// first - matching webapp's ConversationV2.tsx, which explicitly does
  /// the same (see InitConversationInfoRequest's doc comment there) because
  /// initConversation/getConversationInfo have no fallback for a brand-new
  /// single conversation with no Mongo doc yet (e.g. opened via a
  /// contact's Message button before any message was ever sent) - without
  /// this step first, that exact case left the screen spinning forever.
  Future<void> _startLoading() async {
    final setup = await ConversationsApi()
        .getConversationSetupRequest(widget.conversationId);
    if (!mounted) return;
    if (setup == null) {
      setState(() {
        isSettingUp = false;
        conversationLoadError = "This conversation could not be loaded.";
      });
      return;
    }
    setState(() {
      conversationSetup = setup;
      isSettingUp = false;
    });

    final loadedMessages =
        await initConversationProcess(widget.conversationId, range);
    if (!mounted) return;
    if (!loadedMessages) {
      setState(() {
        conversationLoadError = "This conversation could not be loaded.";
      });
      return;
    }
    getConversationInfoProcess(widget.conversationId, _conversationType);
    _eventBusSubscription = eventBus.on<SSEModel>().listen((SSEModel event) {
      if (event.event == "messages_list") {
        if (mounted) {
          // Deletion reuses this same broadcast channel (matches webapp's
          // sse.ts reload vs reload_deleted_message split) - the payload's
          // message.deletedMessageID marks a soft-delete instead of "go
          // refetch a page". Handled as an in-place mutation (flip
          // isDeleted on the matching MessageContent, no list reshuffle)
          // rather than falling into the full-page refetch below, which
          // would be wasted work for a single-field change and would also
          // fight the reply-in-place logic elsewhere in this file.
          final deletedMessageID = _deletedMessageIdFromSseEvent(event);
          if (deletedMessageID != null) {
            final target = conversationContentList
                .where((message) => message.messageID == deletedMessageID)
                .toList();
            if (target.isNotEmpty) {
              setState(() => target[0].isDeleted = true);
            }
            return;
          }

          int newRange = range + 1;
          // Marking messages seen is no longer driven from here - it used
          // to fire against _unseenMessageIDs computed from
          // conversationContentList BEFORE the refetch below had actually
          // run, which meant the payload never included the very message
          // that just arrived (the reason it triggered this branch in the
          // first place). Now it's driven entirely by which messages are
          // actually visible on screen (see _seenTrackedMessage/
          // _queueMessageSeen), matching webapp's ConversationV2.tsx -
          // this refetch just needs to bring the new message in; once it
          // renders, VisibilityDetector picks it up on its own if it's
          // actually in view.
          initConversationProcess(widget.conversationId, newRange).then((_) {
            if (mounted) {
              setState(() {
                range = newRange;
              });
            }
          });
        }
      }
    });
  }

  /// Server pushes deletes over the same "messages_list" SSE channel used
  /// for every other message event (routes/messages/index.js's
  /// MessagesTrigger), distinguished only by message.deletedMessageID being
  /// present on the payload - there's no separate event name to switch on.
  /// Also scopes to this screen's conversation, since the channel fires for
  /// every conversation the socket is subscribed to, not just the open one.
  String? _deletedMessageIdFromSseEvent(SSEModel event) {
    try {
      final parsed = jsonDecode(event.data as String);
      final message = parsed["message"];
      if (message is! Map) return null;
      if (message["conversationID"]?.toString() != widget.conversationId) {
        return null;
      }
      return message["deletedMessageID"]?.toString();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _eventBusSubscription?.cancel();
    _seenDebounceTimer?.cancel();
    _scrollController.dispose();
    _voiceRecorder.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final minScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;

      if (currentScroll >= minScroll - 20) {
        if (!(range >= totalMessages)) {
          if (mounted) {
            // Was gated on conversationInfo != null - conversationInfo is
            // participant info, unrelated to whether more messages can be
            // fetched, and stays null for longer than expected on some
            // conversations (see getConversationInfoRequest's fallback
            // handling), which silently blocked load-more entirely.
            // widget.conversationId is available immediately, matching
            // every other initConversationProcess call site in this file.
            if (!isRefreshed) {
              int oldRangeAdd = range + 20;

              setState(() {
                isRefreshed = true;
              });
              // range only advances once the fetch actually lands (mirrors
              // the SSE listener's own .then(...) pattern in _startLoading)
              // - bumping it eagerly here made the "more to load" spinner
              // (gated on range >= totalMessages) disappear the instant a
              // scroll triggered a fetch, before the new messages had
              // actually arrived to replace it.
              initConversationProcess(widget.conversationId, oldRangeAdd)
                  .then((_) {
                if (mounted) {
                  setState(() {
                    range = oldRangeAdd;
                  });
                }
              });

              Future.delayed(Duration(milliseconds: 2500), () {
                if (mounted) {
                  setState(() {
                    isRefreshed = false;
                  });
                }
              });
            }
          }
        }
      }
    }
  }

  /// The conversation's real type - only known once conversationSetup has
  /// resolved (see _startLoading); "single" is a safe default while
  /// loading, since every _conversationType check below just degrades to
  /// the single-conversation path until the real value lands.
  String get _conversationType =>
      conversationSetup?['conversationType']?.toString() ?? "single";

  /// The other participant's (single) or the realm/group's (group) display
  /// name and avatar - both come from the same "details" object GET
  /// /m/conversation/:conversationID returns (see _startLoading), matching
  /// webapp's ConversationV2.tsx exactly (conversationsetup.details.display_name
  /// / .profile). This is the ONLY source for header identity - this screen
  /// used to also accept a richer navigation-time "extra" object, which
  /// worked when opened from the Messages list or Contacts (which had that
  /// data on hand already) but left the header/avatar permanently blank
  /// when opened from Profile's or Search's "Message" button, neither of
  /// which have anything but the conversationID to hand over. Matches
  /// ConversationV2.tsx's actual contract: it only takes a conversationID
  /// and resolves everything else itself via InitConversationInfoRequest.
  String get _headerDisplayName {
    final details = conversationSetup?['details'];
    final name = details is Map ? details['display_name']?.toString() : null;
    return (name != null && name.isNotEmpty && name != "Unknown User")
        ? name
        : "";
  }

  String get _headerAvatarSrc {
    final details = conversationSetup?['details'];
    final profile = details is Map ? details['profile']?.toString() : null;
    return (profile != null && profile.isNotEmpty && profile != "none")
        ? profile
        : "";
  }

  /// Every other participant's entityID to ring - mirrors webapp's
  /// ConversationV2.tsx initializeCall's own fallback chain exactly:
  /// conversationSetup.details.entity_id for a single conversation (the
  /// one source confirmed to resolve even before conversationInfo has
  /// loaded), else conversationInfo.users (excluding self), else
  /// conversationSetup's raw participant_ids as a last resort.
  List<String> get _callRecipients {
    if (_conversationType == "single") {
      final other = _headerEntityId;
      return other != null && other.isNotEmpty ? [other] : [];
    }
    final myEntityId = appStore.state.userAuth.user.entityId;
    final fromInfo = (conversationInfo?.users ?? [])
        .map((u) => u.entityID)
        .where((id) => id.isNotEmpty && id != myEntityId)
        .toSet()
        .toList();
    if (fromInfo.isNotEmpty) return fromInfo;
    final rawParticipantIds = conversationSetup?['participant_ids'];
    if (rawParticipantIds is List) {
      return rawParticipantIds
          .map((id) => id.toString())
          .where((id) => id.isNotEmpty && id != myEntityId)
          .toList();
    }
    return [];
  }

  /// Caller-side entry point for both call buttons - mirrors webapp's
  /// initializeCall: fire the ring signal (CallRequest), then immediately
  /// join our own mediasoup room without waiting for the callee to answer
  /// (an SFU room supports joining before anyone else has). callType is
  /// "audio" or "video" - video capture/rendering itself is M7's concern,
  /// this always produces mic-only for now regardless of which button was
  /// tapped, same limitation the M1-M4 milestones already carried.
  Future<void> _initiateCall(String callType) async {
    if (_conversationType != "single" && _conversationType != "group") return;
    if (appStore.state.currentCall != null) return; // already on a call
    final recipients = _callRecipients;
    if (recipients.isEmpty) return;

    final me = appStore.state.userAuth.user;
    final caller = CallerInfo(name: me.firstname, entityId: me.entityId);
    final callDisplayName = _conversationType == "single"
        ? me.firstname
        : "$_headerDisplayName (Group)";

    // Fire-and-forget - the callee's incoming-call screen is driven by the
    // "incomingcall" SSE event this triggers, not by anything in this
    // response.
    CallApi().callRequest(ICallRequest(
      callType: callType,
      callDisplayName: callDisplayName,
      conversationType: _conversationType,
      conversationID: widget.conversationId,
      caller: caller,
      recepients: recipients,
      displayImage: _conversationType == "single" ? _headerAvatarSrc : "none",
    ));

    final joined = await CallController.instance.joinCall(
      conversationID: widget.conversationId,
      conversationType: _conversationType,
      callType: callType,
      isOutgoing: true,
      recepients: recipients,
      startCameraOff: callType != "video",
    );
    if (!joined) return;

    appStore.dispatch(DispatchModel(
        setCurrentCallT,
        CallSession(
            conversationID: widget.conversationId,
            conversationType: _conversationType,
            callType: callType,
            isOutgoing: true,
            recepients: recipients)));

    if (mounted) context.push('/call/active');
  }

  /// The other participant's entity id, single conversations only - a
  /// group's avatar has no single "online" state to show (matches webapp's
  /// activeuserSpecific gating on conversationType === "single").
  String? get _headerEntityId {
    if (_conversationType != "single") return null;
    final details = conversationSetup?['details'];
    return details is Map ? details['entity_id']?.toString() : null;
  }

  /// "Active Now" while online, else "Active <time since> ago" once we
  /// have a last-seen timestamp for them, else the generic fallback text -
  /// matches webapp's userSessionStatusFromContacts, simplified to always
  /// use a relative label instead of its live-vs-snapshot formatting split
  /// (see date_words.dart's timeSince doc comment for why).
  String _headerSubtitle(AppState state) {
    if (_conversationType != "single") return "Members are Active";
    final entityId = _headerEntityId;
    if (entityId == null) return "Recently Active";
    final info = state.presence[entityId];
    if (info == null) return "Recently Active";
    if (info.online) return "Active Now";
    if (info.lastSeen != null) return "Active ${timeSince(info.lastSeen!)}";
    return "Recently Active";
  }

  /// Resolves message.sender (an entity id) to something worth showing a
  /// human - "You" for the current account, else the matching participant's
  /// name from conversationInfo.usersWithInfo, falling back to the raw id
  /// only if neither is available yet (e.g. conversationInfo hasn't loaded).
  String _resolveSenderName(String entityId) {
    if (entityId == _myAccountId) return "You";

    // Single conversations only ever have two participants - if it isn't
    // "me", it's the other person, already named by _headerDisplayName
    // (same conversationSetup.details this pulls from). Reliable regardless
    // of whether conversationInfo has finished loading, or whether its id
    // fields actually match this message's sender.
    if (_conversationType == "single" && _headerDisplayName.isNotEmpty) {
      return _headerDisplayName;
    }

    // GET /m/conversation/:id (conversationSetup) is the endpoint
    // confirmed working for this exact screen (see _startLoading) - try it
    // before the older conversationInfo.usersWithInfo, which comes back
    // empty/mismatched more often (e.g. the connection-less-conversation
    // edge case documented on ConversationInfoModel.fromJson).
    final setupDetails = conversationSetup?['details'];
    if (setupDetails is Map &&
        setupDetails['entity_id']?.toString() == entityId) {
      final name = setupDetails['display_name']?.toString();
      if (name != null && name.isNotEmpty && name != "Unknown User") {
        return name;
      }
    }

    final matches = conversationInfo?.usersWithInfo
        .where((u) => u.entityID == entityId)
        .toList();
    if (matches != null && matches.isNotEmpty) return matches.first.displayName;

    if (kDebugMode) {
      print("[_resolveSenderName] no match for entityId=$entityId");
      print("  conversationSetup.details=${conversationSetup?['details']}");
      print("  conversationInfo.usersWithInfo="
          "${conversationInfo?.usersWithInfo.map((u) => '{entityID:${u.entityID}, userID:${u.userID}, name:${u.displayName}}').toList()}");
    }
    // No source has this participant's name (seen live: the /conversationinfo
    // endpoint returning usersWithInfo: null for a group - the deployed
    // server's current behavior there doesn't match what this repo's
    // getRealmWithUsers/formatToDesiredStructure would produce, which always
    // .map()s to an array, never null - a deploy-lag mismatch, not something
    // fixable from here). A 36-char uuid is a worse fallback than a short,
    // honestly-unresolved label.
    return "Member ${entityId.length >= 4 ? entityId.substring(entityId.length - 4) : entityId}";
  }

  String _seenersLabel(List<String> seeners) =>
      seeners.map(_resolveSenderName).join(", ");

  /// Returns whether messages actually loaded - used by _startLoading to
  /// tell "failed" apart from "still in flight" so a failure on the first
  /// call surfaces an error instead of leaving the screen spinning forever
  /// with no explanation (the exact bug already found and fixed once for
  /// getConversationSetupRequest - this closes the same gap here, since a
  /// thrown/malformed response previously left isInitialized stuck false
  /// with nothing catching it).
  Future<bool> initConversationProcess(
      String conversationID, int rangeProp) async {
    try {
      EncodedResponse? initConversationResponse = await ConversationsApi()
          .initConversationRequest(conversationID, rangeProp);
      if (initConversationResponse == null) return false;

      Map<String, dynamic>? decodedInitConversation =
          JwtCodec.decode(initConversationResponse.result);

      final rawMessages = decodedInitConversation?["messages"];
      if (rawMessages is! List) return false;

      List<MessageContent> messageContentList = rawMessages
          .whereType<Map>()
          .map((message) =>
              MessageContent.fromJson(Map<String, dynamic>.from(message)))
          .toList();

      if (mounted) {
        setState(() {
          conversationContentList = messageContentList;
          combinedPendingAndMessagesList = [
            ...messageContentList,
            ...pendingMessagesList
          ];
          isInitialized = true;
          totalMessages = _intValue(decodedInitConversation?["total"]);
        });
      }
      return true;
    } catch (e, stack) {
      if (kDebugMode) {
        print("ERROR parsing conversation messages");
        print(e);
        print(stack);
      }
      return false;
    }
  }

  int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> getConversationInfoProcess(
      String conversationID, String conversationType) async {
    EncodedResponse? getConversationInfoResponse = await ConversationsApi()
        .getConversationInfoRequest(conversationID, conversationType);

    if (getConversationInfoResponse != null) {
      Map<String, dynamic>? decodedGetConversationInfo =
          JwtCodec.decode(getConversationInfoResponse.result);

      // Confirmed by hitting the endpoint directly: a normally-populated
      // response really is double-wrapped - createJWT({data:
      // flattenedResults}) decodes to {data: {data: {...actual fields...}}}.
      // A previous "fix" here dropped to single-level ["data"] access based
      // only on the degenerate formatConnectionData([]) => {} edge case,
      // where the extra ["data"] read as null - but that same shallow read
      // was silently wrong for every normal response, since {data: {...}}
      // only has one key ("data") and nothing else, so every real field
      // (contactID, usersWithInfo, users, ...) always came back missing.
      // Self-detect instead of hardcoding either shape: if the first level
      // has its own nested "data" map, unwrap once more; otherwise use it
      // as-is (covers the {} degenerate case, which has no "data" key to
      // unwrap and must be used directly).
      dynamic level1 = decodedGetConversationInfo?["data"];
      dynamic rawGetConversationInfo =
          (level1 is Map && level1["data"] is Map) ? level1["data"] : level1;
      if (rawGetConversationInfo is! Map) return;

      if (kDebugMode) {
        print("[getConversationInfoProcess] raw usersWithInfo="
            "${rawGetConversationInfo["usersWithInfo"]}");
      }

      ConversationInfoModel conversationInfoFinal =
          ConversationInfoModel.fromJson(
              Map<String, dynamic>.from(rawGetConversationInfo));

      if (mounted) {
        setState(() {
          conversationInfo = conversationInfoFinal;
        });
      }

      // if (kDebugMode) {
      //   // print(rawContactsList);
      //   print(rawGetConversationInfo);
      // }
    }
  }

  /// Wraps a confirmed message's bubble with viewport-visibility tracking,
  /// matching webapp's ConversationV2.tsx exactly: each message that
  /// becomes visible and isn't already in its own `seeners` gets queued,
  /// and a 500ms debounce (reset on every new addition) is what actually
  /// fires the seen-messages call - not a one-shot call on conversation
  /// open, and not the SSE "messages_list" refetch (see _startLoading's
  /// comment on why that path was racy). This is the ONLY thing that marks
  /// messages seen now, same as webapp - there is no separate initial-load
  /// call to coexist with; messages visible right after the conversation
  /// opens (scrolled to wherever it lands) get caught by this the same way
  /// newly-arrived ones do once they're actually on screen.
  Widget _seenTrackedMessage(MessageContent content, Widget child) {
    return VisibilityDetector(
      key: ValueKey('seen-${content.messageID}'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction < 0.5) return;
        if (content.seeners.contains(_myAccountId)) return;
        _queueMessageSeen(content.messageID);
      },
      child: child,
    );
  }

  /// Add-only, dedupe-by-skip (not move-to-front like webapp's version -
  /// VisibilityDetector's callback fires more chattily than a hook that
  /// only reacts to a clean in/out transition, so re-queuing something
  /// already pending would keep resetting the timer indefinitely during a
  /// slow scroll). Resets the same 500ms debounce webapp uses on every
  /// genuinely new addition.
  void _queueMessageSeen(String messageID) {
    if (_unreadMessageIds.contains(messageID)) return;
    if (mounted) {
      setState(() => _unreadMessageIds = [messageID, ..._unreadMessageIds]);
    } else {
      _unreadMessageIds = [messageID, ..._unreadMessageIds];
    }
    _seenDebounceTimer?.cancel();
    _seenDebounceTimer =
        Timer(const Duration(milliseconds: 500), _flushSeenMessages);
  }

  Future<void> _flushSeenMessages() async {
    if (_unreadMessageIds.isEmpty || conversationInfo == null) return;
    final ids = List<String>.from(_unreadMessageIds);
    final seen = await ConversationsApi().seenNewMessagesRequest(
        ISeenNewMessagesRequest(widget.conversationId, range,
            conversationInfo!.users.map((user) => user.entityID).toList(), ids),
        range);
    if (!mounted || seen == null) return;
    setState(() => _unreadMessageIds =
        _unreadMessageIds.where((id) => !seen.contains(id)).toList());
  }

  Future<void> postReplyAssistProcess(
      String conversationID, List<ReplyAssistContext> messageIDs) async {
    MessageBasedResponse? postReplyAssistResponse = await ConversationsApi()
        .postReplyAssistRequest(conversationID, messageIDs);

    if (postReplyAssistResponse != null) {
      _controller.text = postReplyAssistResponse.message;
      setState(() {
        messageValue = postReplyAssistResponse.message;
      });
      if (kDebugMode) {
        // print(rawContactsList);
        print(postReplyAssistResponse.message);
      }
    }
  }

  Future<void> isTypingProcess(IisTypingRequest payload) async {
    if (mounted) {
      setState(() {
        isSeenMessageInitialized = true;
      });
    }

    EncodedResponse? postIsTypingResponse =
        await ConversationsApi().isTypingRequest(payload);

    if (postIsTypingResponse != null) {
      if (kDebugMode) {
        // print(rawContactsList);
        print(postIsTypingResponse);
      }
    }
  }

  void isTypingTimeout(String conversationID, List<String> receivers) {
    if (!isTyping) {
      setState(() {
        isTyping = true;
        isTypingTimedOut = true;
      });
      isTypingProcess(IisTypingRequest(conversationID, receivers));
      Future.delayed(Duration(milliseconds: 5000), () {
        setState(() {
          isTyping = false;
          isTypingTimedOut = false;
        });
      });
    }
  }

  String messageReplyIdentifier(String messageTypeProp, String contentProp) {
    if (messageTypeProp == "text") {
      return contentProp;
    } else if (messageTypeProp == "image") {
      return "a photo";
    } else if (messageTypeProp.contains("video")) {
      return "a video";
    } else if (messageTypeProp.contains("audio")) {
      return "an audio";
    } else {
      return "a file";
    }
  }

  void sendMessageProcess(
      String userID,
      String conversationID,
      List<String> receivers,
      String messageType,
      String conversationType,
      String contentValue,
      bool isReplyingProp,
      String replyingToProp) async {
    String pendingID =
        "${userID}_${conversationID}_${pendingMessagesList.length + 1}_${ContentValidator().generateRandomNumber(10)}";

    ContentValidator().printer(pendingID);
    ContentValidator().printer(contentValue);

    setState(() {
      messageValue = "";
      isReplying = IsReplying(false, "");
      _controller.clear();
    });

    if (contentValue.trim() != "") {
      List<PendingMessages> newPendingMessagesList = [...pendingMessagesList];
      newPendingMessagesList.add(
          PendingMessages(conversationID, pendingID, contentValue, "text"));

      ContentValidator().printer(contentValue.trim());
      // ContentValidator().printer(receivers);

      if (mounted) {
        setState(() {
          pendingMessagesList = newPendingMessagesList;
          combinedPendingAndMessagesList = [
            ...conversationContentList,
            ...newPendingMessagesList
          ];
        });
      }

      EncodedResponse? sendMessageResponse = await ConversationsApi()
          .sendMessageRequest(ISendMessagePayload(
              conversationID,
              pendingID,
              receivers,
              contentValue,
              isReplyingProp,
              replyingToProp,
              messageType,
              conversationType));

      if (sendMessageResponse != null) {
        if (kDebugMode) {
          // print(rawContactsList);
          print(sendMessageResponse);
        }
      }
    }
  }

  /// Shared by the image picker, file picker, and voice recorder below -
  /// matches webapp's SendFilesRequest exactly (see ConversationsApi
  /// .sendFilesRequest's doc comment): one multipart POST that both
  /// uploads and creates the message(s), with an optimistic pending entry
  /// per file added locally first (same pendingID-reconciliation pattern
  /// combinedPendingAndMessagesList already uses for text messages - no
  /// extra bookkeeping needed here for that part).
  Future<void> sendFilesProcess(
      String userID,
      String conversationID,
      String conversationType,
      List<({String path, String messageType})> files,
      bool isReplyingProp,
      String replyingToProp) async {
    if (files.isEmpty) return;

    setState(() {
      isReplying = IsReplying(false, "");
    });

    final pendingIDs = <String>[];
    final newPendingMessagesList = [...pendingMessagesList];
    for (var i = 0; i < files.length; i++) {
      final pendingID =
          "${userID}_${conversationID}_${pendingMessagesList.length + i + 1}_${ContentValidator().generateRandomNumber(10)}";
      pendingIDs.add(pendingID);
      newPendingMessagesList.add(PendingMessages(
          conversationID, pendingID, files[i].path, files[i].messageType));
    }

    if (mounted) {
      setState(() {
        pendingMessagesList = newPendingMessagesList;
        combinedPendingAndMessagesList = [
          ...conversationContentList,
          ...newPendingMessagesList
        ];
      });
    }

    await ConversationsApi().sendFilesRequest(
      conversationID: conversationID,
      isReply: isReplyingProp,
      replyingTo: replyingToProp,
      conversationType: conversationType,
      pendingIDs: pendingIDs,
      filePaths: files.map((f) => f.path).toList(),
    );
  }

  void _attachmentTooLarge() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Cannot upload files greater than 25mb")),
    );
  }

  /// Stages picked images for review instead of sending immediately -
  /// pickMultiImage matches webapp's picker resolving to File[] (multiple
  /// selection, not one-at-a-time). Oversized picks are dropped from the
  /// batch (matches webapp's addFilesToComposer, which silently filters
  /// rather than blocking the whole selection over one bad file).
  Future<void> _pickImages() async {
    final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (picked.isEmpty || !mounted) return;
    var droppedAny = false;
    final accepted = <({String path, String messageType})>[];
    for (final file in picked) {
      if (await File(file.path).length() > _maxAttachmentBytes) {
        droppedAny = true;
        continue;
      }
      accepted.add((path: file.path, messageType: "image"));
    }
    if (!mounted) return;
    if (droppedAny) _attachmentTooLarge();
    if (accepted.isEmpty) return;
    setState(() => _stagedFiles = [..._stagedFiles, ...accepted]);
  }

  /// Same staging as _pickImages, any file type, multi-select - the real
  /// messageType (mimetype) is resolved server-side from each multipart
  /// part's content-type header once uploaded (matches webapp - the
  /// server never trusts a client-supplied type). "file" here is only a
  /// local placeholder so the staged-preview/pending-message widgets pick
  /// the generic file-card branch instead of misreading it as text/image.
  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    final files = result?.files ?? [];
    if (files.isEmpty || !mounted) return;
    var droppedAny = false;
    final accepted = <({String path, String messageType})>[];
    for (final file in files) {
      final path = file.path;
      if (path == null) continue;
      if (await File(path).length() > _maxAttachmentBytes) {
        droppedAny = true;
        continue;
      }
      accepted.add((path: path, messageType: "file"));
    }
    if (!mounted) return;
    if (droppedAny) _attachmentTooLarge();
    if (accepted.isEmpty) return;
    setState(() => _stagedFiles = [..._stagedFiles, ...accepted]);
  }

  void _removeStagedFile(int index) {
    setState(() {
      _stagedFiles = [..._stagedFiles]..removeAt(index);
    });
  }

  /// One thumbnail (image) or file-icon chip in the pre-send preview
  /// strip, with a tap-to-remove "x" badge.
  Widget _stagedAttachmentChip(int index) {
    final file = _stagedFiles[index];
    final isImage = file.messageType == "image";
    return Padding(
      padding: const EdgeInsets.only(left: 6, top: 8, bottom: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 60,
            height: 60,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Color(0xffe4e4e4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: isImage
                ? Image.file(File(file.path),
                    width: 60, height: 60, fit: BoxFit.cover)
                : Center(
                    child: Icon(Icons.insert_drive_file_outlined,
                        color: Color(0xFF565656), size: 26),
                  ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: () => _removeStagedFile(index),
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: Colors.black87),
                child: Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Diverges from webapp's exact voice-message UI on one point: webapp's
  /// stop button has no cancel step, but the user explicitly asked for a
  /// cancel affordance here, so recording now exposes a separate
  /// stop-and-send vs. cancel action instead of a single toggle.
  Future<void> _startVoiceRecording() async {
    if (!await _voiceRecorder.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text("Microphone access is required to send a voice message")),
      );
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _voiceRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path);
    if (!mounted) return;
    setState(() => _isRecordingVoice = true);
  }

  Future<void> _stopAndSendVoiceRecording(AppState state) async {
    final path = await _voiceRecorder.stop();
    if (!mounted) return;
    setState(() => _isRecordingVoice = false);
    if (path == null || conversationInfo == null) return;
    if (await File(path).length() > _maxAttachmentBytes) {
      _attachmentTooLarge();
      return;
    }
    await sendFilesProcess(
      state.userAuth.user.entityId,
      widget.conversationId,
      conversationInfo?.type as String,
      [(path: path, messageType: "audio/m4a")],
      isReplying.isReply,
      isReplying.replyingTo,
    );
  }

  /// Stops the in-progress recording and discards it - no message is sent
  /// and the partial recording file is deleted rather than left orphaned
  /// in the temp directory.
  Future<void> _cancelVoiceRecording() async {
    final path = await _voiceRecorder.stop();
    if (mounted) setState(() => _isRecordingVoice = false);
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AppState>(
      builder: (context, state) {
        final p = cl(context);
        return PopScope(
          canPop: true,
          // The message TextField below keeps focus (and the keyboard
          // open) right up until this screen is torn down. Without
          // releasing it here, the OS keyboard doesn't close with the
          // route transition - it stays up and reopens against whatever
          // the previous screen's next focusable field ends up being, even
          // though nothing there was tapped. Covers every way off this
          // screen (back button below, system back gesture/hardware back
          // button) since they all funnel through the same pop mechanics.
          onPopInvokedWithResult: (didPop, result) {
            FocusManager.instance.primaryFocus?.unfocus();
          },
          child: Scaffold(
            backgroundColor: p.bg,
            resizeToAvoidBottomInset: true,
            // top: false - the header below already hardcodes its own status-bar
            // offset (padding top: 30); only bottom needs SafeArea here, to
            // keep the message input clear of the device's gesture/nav bar.
            body: SafeArea(
              top: false,
              child: Center(
                child: Container(
                  color: p.surface,
                  width: MediaQuery.of(context).size.width,
                  child: Stack(
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            height: 90,
                            decoration: BoxDecoration(
                              color: p.surface,
                              border: Border(
                                bottom: BorderSide(
                                  width: 0.5,
                                  color: p.border,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding:
                                  EdgeInsets.only(top: 30, left: 5, right: 10),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                        maxWidth: 40, maxHeight: 40),
                                    child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            elevation: 0,
                                            padding: EdgeInsets.only(
                                                top: 0,
                                                bottom: 0,
                                                left: 0,
                                                right: 0)),
                                        onPressed: () {
                                          context.pop();
                                        },
                                        child: Center(
                                          child: Icon(
                                            Icons.arrow_back_ios_new_rounded,
                                            color: p.text2,
                                            size: 20,
                                          ),
                                        )),
                                  ),
                                  SizedBox(width: 2),
                                  // CLAvatar instead of a raw Image.network -
                                  // that had no clipping on the child at all
                                  // (BoxDecoration's borderRadius only paints
                                  // the container's own background, it doesn't
                                  // clip children; needed ClipOval/clipBehavior
                                  // for that), so the image rendered as an
                                  // unclipped rectangle over/around the
                                  // rounded background instead of filling a
                                  // clean circle.
                                  // conversationSetup is null until
                                  // getConversationSetupRequest resolves (see
                                  // _startLoading) - rendering CLAvatar/Text
                                  // against the empty strings _headerDisplayName/
                                  // _headerAvatarSrc fall back to in that window
                                  // showed a blank-initialed avatar and an empty
                                  // name line, which reads as broken rather than
                                  // "still loading".
                                  conversationSetup == null
                                      ? CLSkeleton(
                                          width: 40,
                                          height: 40,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        )
                                      : CLAvatar(
                                          id: widget.conversationId,
                                          name: _headerDisplayName,
                                          src: _headerAvatarSrc,
                                          size: 40,
                                          online: _headerEntityId != null &&
                                              (state.presence[_headerEntityId]
                                                      ?.online ??
                                                  false),
                                        ),
                                  SizedBox(width: 15),
                                  Expanded(
                                    child: conversationSetup == null
                                        ? Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              CLSkeleton(
                                                  width: 120, height: 13),
                                              SizedBox(height: 6),
                                              CLSkeleton(width: 80, height: 11),
                                            ],
                                          )
                                        : Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                _headerDisplayName,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: p.text,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                _headerSubtitle(state),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: p.text2,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      ConstrainedBox(
                                        constraints: BoxConstraints(
                                            maxWidth: 40, maxHeight: 40),
                                        child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.transparent,
                                                elevation: 0,
                                                padding: EdgeInsets.only(
                                                    top: 0,
                                                    bottom: 0,
                                                    left: 0,
                                                    right: 0)),
                                            onPressed: () =>
                                                _initiateCall("audio"),
                                            child: Center(
                                              child: Icon(
                                                Icons.call,
                                                color: p.brand,
                                                size: 24,
                                              ),
                                            )),
                                      ),
                                      SizedBox(
                                        width: 2,
                                      ),
                                      ConstrainedBox(
                                        constraints: BoxConstraints(
                                            maxWidth: 40, maxHeight: 40),
                                        child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.transparent,
                                                elevation: 0,
                                                padding: EdgeInsets.only(
                                                    top: 0,
                                                    bottom: 0,
                                                    left: 0,
                                                    right: 0)),
                                            onPressed: () =>
                                                _initiateCall("video"),
                                            child: Center(
                                              child: Icon(
                                                Icons.videocam_rounded,
                                                color: p.green,
                                                size: 24,
                                              ),
                                            )),
                                      ),
                                      SizedBox(
                                        width: 2,
                                      ),
                                      ConstrainedBox(
                                        constraints: BoxConstraints(
                                            maxWidth: 40, maxHeight: 40),
                                        child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.transparent,
                                                elevation: 0,
                                                padding: EdgeInsets.only(
                                                    top: 0,
                                                    bottom: 0,
                                                    left: 0,
                                                    right: 0)),
                                            onPressed: () {},
                                            child: Center(
                                              child: Icon(
                                                Icons.info,
                                                color: Color(0xff1c7def),
                                                size: 24,
                                              ),
                                            )),
                                      )
                                    ],
                                  )
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: conversationLoadError != null
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.error_outline,
                                              size: 40, color: p.text3),
                                          const SizedBox(height: 10),
                                          Text(conversationLoadError!,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  color: p.text2,
                                                  fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                  )
                                : (isSettingUp || !isInitialized)
                                    ? const CLMessageListSkeleton()
                                    : combinedPendingAndMessagesList.isEmpty
                                        ? Center(
                                            child: Padding(
                                              padding: const EdgeInsets.all(24),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                      Icons.chat_bubble_outline,
                                                      size: 40,
                                                      color: p.text3),
                                                  const SizedBox(height: 10),
                                                  Text("No messages yet",
                                                      style: TextStyle(
                                                          color: p.text,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 15)),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                      "Say hello to start the conversation.",
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: TextStyle(
                                                          color: p.text2,
                                                          fontSize: 13)),
                                                ],
                                              ),
                                            ),
                                          )
                                        : ListView.builder(
                                            // No ValueKey here on purpose - it
                                            // used to be recomputed from
                                            // unreadTotal/newMessageIDOnTop,
                                            // which change from unrelated
                                            // Redux activity (typing, other
                                            // conversations) independent of
                                            // this list's own content. A
                                            // changing key forces Flutter to
                                            // discard and rebuild the whole
                                            // Viewport/Scrollable as a brand
                                            // new widget; if that happened
                                            // mid-drag it desynced the active
                                            // scroll gesture from the new
                                            // Scrollable, throwing a
                                            // RangeError - reproduced by a
                                            // long scroll in a group
                                            // conversation. itemBuilder
                                            // already re-runs with fresh
                                            // state/conversationInfo on every
                                            // rebuild regardless of key, so
                                            // nothing here depended on it to
                                            // stay current.
                                            reverse: true,
                                            controller: _scrollController,
                                            padding: EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 5),
                                            itemCount:
                                                combinedPendingAndMessagesList
                                                    .length, //conversationContentList.length
                                            itemBuilder: (context, index) {
                                              bool
                                                  hasConversationTypingActivity =
                                                  state.isTypingList
                                                          .where((typing) =>
                                                              typing
                                                                  .conversationID ==
                                                              widget
                                                                  .conversationId)
                                                          .toList()
                                                          .isNotEmpty
                                                      ? true
                                                      : false;

                                              if (index ==
                                                  combinedPendingAndMessagesList
                                                          .length -
                                                      1) {
                                                return Column(
                                                  children: [
                                                    // MessageContent item
                                                    if (!(range >=
                                                        totalMessages))
                                                      Padding(
                                                        padding:
                                                            EdgeInsets.only(
                                                                top: 10),
                                                        child:
                                                            SpinningLoaderWidget(
                                                                isLoading: true,
                                                                isFromServer:
                                                                    false),
                                                      ),
                                                    if (combinedPendingAndMessagesList[
                                                            combinedPendingAndMessagesList
                                                                    .length -
                                                                1 -
                                                                index]
                                                        is MessageContent)
                                                      Column(
                                                        children: [
                                                          _seenTrackedMessage(
                                                            combinedPendingAndMessagesList[
                                                                    combinedPendingAndMessagesList
                                                                            .length -
                                                                        1 -
                                                                        index]
                                                                as MessageContent,
                                                            SizedBox(
                                                              width:
                                                                  MediaQuery.of(
                                                                          context)
                                                                      .size
                                                                      .width,
                                                              child:
                                                                  MessageContentWidget(
                                                                key: ValueKey((combinedPendingAndMessagesList[combinedPendingAndMessagesList.length -
                                                                            1 -
                                                                            index]
                                                                        as MessageContent)
                                                                    .messageID),
                                                                messageContent: combinedPendingAndMessagesList[
                                                                        combinedPendingAndMessagesList.length -
                                                                            1 -
                                                                            index]
                                                                    as MessageContent,
                                                                previousContentUserID: index >
                                                                            0 &&
                                                                        index <
                                                                            combinedPendingAndMessagesList.length -
                                                                                1
                                                                    ? combinedPendingAndMessagesList[combinedPendingAndMessagesList.length -
                                                                            1 -
                                                                            index -
                                                                            1]
                                                                        .sender
                                                                    : index == 0
                                                                        ? "start"
                                                                        : "end",
                                                                currentUserID:
                                                                    state
                                                                        .userAuth
                                                                        .user
                                                                        .entityId,
                                                                resolveSenderName:
                                                                    _resolveSenderName,
                                                                isSingleConversation:
                                                                    _conversationType ==
                                                                        "single",
                                                                conversationID:
                                                                    widget
                                                                        .conversationId,
                                                                onPressed: (bool
                                                                        isReply,
                                                                    String
                                                                        replyingTo) {
                                                                  if (mounted) {
                                                                    StoreProvider.of<AppState>(
                                                                            context)
                                                                        .dispatch(DispatchModel(
                                                                            setIsUsingReplyAssistT,
                                                                            false));
                                                                    StoreProvider.of<AppState>(
                                                                            context)
                                                                        .dispatch(DispatchModel(
                                                                            clearReplyAssistContextT,
                                                                            []));
                                                                    setState(
                                                                        () {
                                                                      isReplying = IsReplying(
                                                                          isReply,
                                                                          replyingTo);
                                                                    });
                                                                  }
                                                                },
                                                              ),
                                                            ),
                                                          ),
                                                          if (combinedPendingAndMessagesList[
                                                                  combinedPendingAndMessagesList
                                                                          .length -
                                                                      1 -
                                                                      index]
                                                              is MessageContent)
                                                            (combinedPendingAndMessagesList[combinedPendingAndMessagesList.length -
                                                                                1 -
                                                                                index]
                                                                            as MessageContent)
                                                                        .messageType !=
                                                                    "notif"
                                                                ? conversationInfo !=
                                                                        null
                                                                    ? (combinedPendingAndMessagesList[combinedPendingAndMessagesList.length - 1 - index] as MessageContent).seeners.length ==
                                                                            conversationInfo
                                                                                ?.users.length
                                                                        ? index - pendingMessagesList.length ==
                                                                                0
                                                                            ? Padding(
                                                                                padding: EdgeInsets.symmetric(vertical: 4, horizontal: 7),
                                                                                child: SizedBox(
                                                                                  width: double.infinity,
                                                                                  child: Text(
                                                                                    _conversationType == "single" ? "Seen" : "Seen by everyone",
                                                                                    textAlign: (combinedPendingAndMessagesList[combinedPendingAndMessagesList.length - 1 - index] as MessageContent).sender == state.userAuth.user.entityId ? TextAlign.end : TextAlign.start,
                                                                                    style: TextStyle(
                                                                                      fontSize: 12,
                                                                                      color: Color(0xFF565656),
                                                                                    ),
                                                                                  ),
                                                                                ),
                                                                              )
                                                                            : SizedBox
                                                                                .shrink()
                                                                        : index - pendingMessagesList.length ==
                                                                                0
                                                                            ? _conversationType !=
                                                                                    "single"
                                                                                ? Padding(
                                                                                    padding: EdgeInsets.symmetric(vertical: 4, horizontal: 7),
                                                                                    child: SizedBox(
                                                                                      width: double.infinity,
                                                                                      child: Text(
                                                                                        "Seen by ${_seenersLabel((combinedPendingAndMessagesList[combinedPendingAndMessagesList.length - 1 - index] as MessageContent).seeners)}",
                                                                                        textAlign: (combinedPendingAndMessagesList[combinedPendingAndMessagesList.length - 1 - index] as MessageContent).sender == state.userAuth.user.entityId ? TextAlign.end : TextAlign.start,
                                                                                        style: TextStyle(
                                                                                          fontSize: 12,
                                                                                          color: Color(0xFF565656),
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                  )
                                                                                : SizedBox
                                                                                    .shrink()
                                                                            : SizedBox
                                                                                .shrink()
                                                                    : SizedBox
                                                                        .shrink()
                                                                : SizedBox
                                                                    .shrink(),
                                                          if (index == 0)
                                                            TypingIndicator(
                                                                isTyping:
                                                                    hasConversationTypingActivity)
                                                          else
                                                            SizedBox.shrink(),
                                                        ],
                                                      ),

                                                    // PendingMessages item
                                                    if (combinedPendingAndMessagesList[
                                                            combinedPendingAndMessagesList
                                                                    .length -
                                                                1 -
                                                                index]
                                                        is PendingMessages)
                                                      Column(
                                                        children: [
                                                          SizedBox(
                                                            width:
                                                                MediaQuery.of(
                                                                        context)
                                                                    .size
                                                                    .width,
                                                            child:
                                                                PendingContentWidget(
                                                              key: ValueKey((combinedPendingAndMessagesList[combinedPendingAndMessagesList
                                                                              .length -
                                                                          1 -
                                                                          index]
                                                                      as PendingMessages)
                                                                  .pendingID),
                                                              messageID: (combinedPendingAndMessagesList[combinedPendingAndMessagesList
                                                                              .length -
                                                                          1 -
                                                                          index]
                                                                      as PendingMessages)
                                                                  .pendingID,
                                                              content: (combinedPendingAndMessagesList[combinedPendingAndMessagesList
                                                                              .length -
                                                                          1 -
                                                                          index]
                                                                      as PendingMessages)
                                                                  .content,
                                                              contentType: (combinedPendingAndMessagesList[combinedPendingAndMessagesList
                                                                              .length -
                                                                          1 -
                                                                          index]
                                                                      as PendingMessages)
                                                                  .type,
                                                            ),
                                                          ),
                                                          if (index == 0)
                                                            TypingIndicator(
                                                                isTyping:
                                                                    hasConversationTypingActivity)
                                                          else
                                                            SizedBox.shrink(),
                                                        ],
                                                      ),
                                                  ],
                                                );
                                              } else {
                                                if (combinedPendingAndMessagesList[
                                                        combinedPendingAndMessagesList
                                                                .length -
                                                            1 -
                                                            index]
                                                    is MessageContent) {
                                                  MessageContent contentItem =
                                                      combinedPendingAndMessagesList[
                                                          combinedPendingAndMessagesList
                                                                  .length -
                                                              1 -
                                                              index];
                                                  String previousContentUserID = index >
                                                              0 &&
                                                          index <
                                                              combinedPendingAndMessagesList
                                                                      .length -
                                                                  1
                                                      ? combinedPendingAndMessagesList[
                                                              combinedPendingAndMessagesList
                                                                      .length -
                                                                  1 -
                                                                  index -
                                                                  1]
                                                          .sender
                                                      : index == 0
                                                          ? "start"
                                                          : "end";

                                                  return Column(
                                                    children: [
                                                      _seenTrackedMessage(
                                                        contentItem,
                                                        SizedBox(
                                                          width: MediaQuery.of(
                                                                  context)
                                                              .size
                                                              .width,
                                                          child:
                                                              MessageContentWidget(
                                                                  key: ValueKey(
                                                                      contentItem
                                                                          .messageID),
                                                                  messageContent:
                                                                      contentItem,
                                                                  previousContentUserID:
                                                                      previousContentUserID,
                                                                  currentUserID: state
                                                                      .userAuth
                                                                      .user
                                                                      .entityId,
                                                                  resolveSenderName:
                                                                      _resolveSenderName,
                                                                  isSingleConversation:
                                                                      _conversationType ==
                                                                          "single",
                                                                  conversationID:
                                                                      widget
                                                                          .conversationId,
                                                                  onPressed: (bool
                                                                          isReply,
                                                                      String
                                                                          replyingTo) {
                                                                    if (mounted) {
                                                                      StoreProvider.of<AppState>(context).dispatch(DispatchModel(
                                                                          setIsUsingReplyAssistT,
                                                                          false));
                                                                      StoreProvider.of<AppState>(
                                                                              context)
                                                                          .dispatch(DispatchModel(
                                                                              clearReplyAssistContextT,
                                                                              []));
                                                                      setState(
                                                                          () {
                                                                        isReplying = IsReplying(
                                                                            isReply,
                                                                            replyingTo);
                                                                      });
                                                                    }
                                                                  }),
                                                        ),
                                                      ),
                                                      contentItem.messageType !=
                                                              "notif"
                                                          ? conversationInfo !=
                                                                  null
                                                              ? contentItem
                                                                          .seeners
                                                                          .length ==
                                                                      conversationInfo
                                                                          ?.users
                                                                          .length
                                                                  ? index - pendingMessagesList.length ==
                                                                          0
                                                                      ? Padding(
                                                                          padding: EdgeInsets.only(
                                                                              top: 4,
                                                                              bottom: 2,
                                                                              left: 7,
                                                                              right: 7),
                                                                          child:
                                                                              SizedBox(
                                                                            width:
                                                                                double.infinity,
                                                                            child:
                                                                                Text(
                                                                              _conversationType == "single" ? "Seen" : "Seen by everyone",
                                                                              textAlign: contentItem.sender == state.userAuth.user.entityId ? TextAlign.end : TextAlign.start,
                                                                              style: TextStyle(
                                                                                fontSize: 12,
                                                                                color: Color(0xFF565656),
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        )
                                                                      : SizedBox(
                                                                          height:
                                                                              0,
                                                                        )
                                                                  : index - pendingMessagesList.length ==
                                                                          0
                                                                      ? _conversationType !=
                                                                              "single"
                                                                          ? Padding(
                                                                              padding: EdgeInsets.only(top: 4, bottom: 2, left: 7, right: 7),
                                                                              child: SizedBox(
                                                                                width: double.infinity,
                                                                                child: Text(
                                                                                  "Seen by ${_seenersLabel(contentItem.seeners)}",
                                                                                  textAlign: contentItem.sender == state.userAuth.user.entityId ? TextAlign.end : TextAlign.start,
                                                                                  style: TextStyle(
                                                                                    fontSize: 12,
                                                                                    color: Color(0xFF565656),
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                            )
                                                                          : SizedBox(
                                                                              height: 0,
                                                                            )
                                                                      : SizedBox(
                                                                          height:
                                                                              0,
                                                                        )
                                                              : SizedBox(
                                                                  height: 0,
                                                                )
                                                          : SizedBox(
                                                              height: 0,
                                                            ),
                                                      index == 0
                                                          ? TypingIndicator(
                                                              isTyping:
                                                                  hasConversationTypingActivity,
                                                            )
                                                          : SizedBox(
                                                              height: 0,
                                                            )
                                                    ],
                                                  );
                                                } else if (combinedPendingAndMessagesList[
                                                    combinedPendingAndMessagesList
                                                            .length -
                                                        1 -
                                                        index] is PendingMessages) {
                                                  PendingMessages contentItem =
                                                      combinedPendingAndMessagesList[
                                                          combinedPendingAndMessagesList
                                                                  .length -
                                                              1 -
                                                              index];

                                                  if (conversationContentList
                                                      .where((item) =>
                                                          item.pendingID ==
                                                          contentItem.pendingID)
                                                      .toList()
                                                      .isEmpty) {
                                                    return Column(
                                                      children: [
                                                        SizedBox(
                                                          width: MediaQuery.of(
                                                                  context)
                                                              .size
                                                              .width,
                                                          child:
                                                              PendingContentWidget(
                                                            key: ValueKey(
                                                                contentItem
                                                                    .pendingID),
                                                            messageID:
                                                                contentItem
                                                                    .pendingID,
                                                            content: contentItem
                                                                .content,
                                                            contentType:
                                                                contentItem
                                                                    .type,
                                                          ),
                                                        ),
                                                        index == 0
                                                            ? TypingIndicator(
                                                                isTyping:
                                                                    hasConversationTypingActivity,
                                                              )
                                                            : SizedBox(
                                                                height: 0,
                                                              )
                                                      ],
                                                    );
                                                  } else {
                                                    return SizedBox();
                                                  }
                                                } else {
                                                  return SizedBox();
                                                }
                                              }
                                            },
                                          ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeInOut,
                            height: isReplying.isReply ? 80 : 0,
                            width: MediaQuery.of(context).size.width,
                            child: Padding(
                              padding: EdgeInsets.only(
                                  top: 5, left: 5, right: 5, bottom: 2),
                              child: Container(
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(7)),
                                child: ClipRect(
                                  child: AnimatedContainer(
                                      duration: Duration(milliseconds: 500),
                                      decoration: BoxDecoration(
                                          color: conversationContentList
                                                  .where((message) =>
                                                      message.messageID ==
                                                      isReplying.replyingTo)
                                                  .toList()
                                                  .isNotEmpty
                                              ? conversationContentList
                                                          .where((message) =>
                                                              message
                                                                  .messageID ==
                                                              isReplying
                                                                  .replyingTo)
                                                          .toList()[0]
                                                          .sender ==
                                                      state.userAuth.user
                                                          .entityId
                                                  ? Color(0xff1c7def)
                                                  : Color(0xffdedede)
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(7)),
                                      child: Padding(
                                        padding: EdgeInsets.all(7),
                                        child: isReplying.isReply
                                            ? Row(
                                                mainAxisSize: MainAxisSize.max,
                                                children: [
                                                  Expanded(
                                                      child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.start,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisSize:
                                                        MainAxisSize.max,
                                                    children: [
                                                      Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .start,
                                                          mainAxisSize:
                                                              MainAxisSize.max,
                                                          children: [
                                                            Text(
                                                              "Replying to ${conversationContentList.where((message) => message.messageID == isReplying.replyingTo).toList().isNotEmpty ? conversationContentList.where((message) => message.messageID == isReplying.replyingTo).toList()[0].sender == state.userAuth.user.entityId ? "your message" : "@${conversationContentList.where((message) => message.messageID == isReplying.replyingTo).toList()[0].sender}" : ""}",
                                                              style: TextStyle(
                                                                  fontSize: 12,
                                                                  color: conversationContentList
                                                                          .where((message) =>
                                                                              message.messageID ==
                                                                              isReplying
                                                                                  .replyingTo)
                                                                          .toList()
                                                                          .isNotEmpty
                                                                      ? conversationContentList.where((message) => message.messageID == isReplying.replyingTo).toList()[0].sender ==
                                                                              state
                                                                                  .userAuth.user.entityId
                                                                          ? Colors
                                                                              .white
                                                                          : Colors
                                                                              .black
                                                                      : Colors
                                                                          .transparent,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold),
                                                              textAlign:
                                                                  TextAlign
                                                                      .justify,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            )
                                                          ]),
                                                      Expanded(
                                                        child: SizedBox(),
                                                      ),
                                                      Text(
                                                        conversationContentList
                                                                .where((message) =>
                                                                    message
                                                                        .messageID ==
                                                                    isReplying
                                                                        .replyingTo)
                                                                .toList()
                                                                .isNotEmpty
                                                            ? messageReplyIdentifier(
                                                                conversationContentList
                                                                    .where((message) =>
                                                                        message
                                                                            .messageID ==
                                                                        isReplying
                                                                            .replyingTo)
                                                                    .toList()[0]
                                                                    .messageType,
                                                                conversationContentList
                                                                    .where((message) =>
                                                                        message
                                                                            .messageID ==
                                                                        isReplying
                                                                            .replyingTo)
                                                                    .toList()[0]
                                                                    .content)
                                                            : "",
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: conversationContentList
                                                                  .where((message) =>
                                                                      message
                                                                          .messageID ==
                                                                      isReplying
                                                                          .replyingTo)
                                                                  .toList()
                                                                  .isNotEmpty
                                                              ? conversationContentList
                                                                          .where((message) =>
                                                                              message.messageID ==
                                                                              isReplying
                                                                                  .replyingTo)
                                                                          .toList()[
                                                                              0]
                                                                          .sender ==
                                                                      state
                                                                          .userAuth
                                                                          .user
                                                                          .id
                                                                  ? Colors.white
                                                                  : Colors.black
                                                              : Colors
                                                                  .transparent,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                        maxLines: 2,
                                                        textAlign:
                                                            TextAlign.justify,
                                                      ),
                                                      Expanded(
                                                        child: SizedBox(),
                                                      ),
                                                    ],
                                                  )),
                                                  Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.start,
                                                    mainAxisSize:
                                                        MainAxisSize.max,
                                                    children: [
                                                      ConstrainedBox(
                                                        constraints:
                                                            BoxConstraints(
                                                                maxHeight: 22,
                                                                maxWidth: 22),
                                                        child: ElevatedButton(
                                                            style: ElevatedButton.styleFrom(
                                                                backgroundColor:
                                                                    Color(
                                                                        0xffdedede),
                                                                elevation: 0,
                                                                padding: EdgeInsets
                                                                    .only(
                                                                        top: 0,
                                                                        bottom:
                                                                            0,
                                                                        left: 0,
                                                                        right:
                                                                            0)),
                                                            onPressed: () {
                                                              if (mounted) {
                                                                setState(() {
                                                                  isReplying =
                                                                      IsReplying(
                                                                          false,
                                                                          "");
                                                                });
                                                                StoreProvider.of<
                                                                            AppState>(
                                                                        context)
                                                                    .dispatch(DispatchModel(
                                                                        setIsUsingReplyAssistT,
                                                                        false));
                                                                StoreProvider.of<
                                                                            AppState>(
                                                                        context)
                                                                    .dispatch(
                                                                        DispatchModel(
                                                                            clearReplyAssistContextT,
                                                                            []));
                                                              }
                                                            },
                                                            child: SizedBox(
                                                              width: 22,
                                                              height: 22,
                                                              child: Column(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .start,
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .center,
                                                                children: [
                                                                  Container(
                                                                    decoration: BoxDecoration(
                                                                        color: Colors
                                                                            .transparent,
                                                                        borderRadius:
                                                                            BorderRadius.circular(22)),
                                                                    width: 22,
                                                                    height: 22,
                                                                    child:
                                                                        Center(
                                                                      child:
                                                                          Icon(
                                                                        color: Colors
                                                                            .white,
                                                                        Icons
                                                                            .close,
                                                                        size:
                                                                            12,
                                                                      ),
                                                                    ),
                                                                  )
                                                                ],
                                                              ),
                                                            )),
                                                      )
                                                    ],
                                                  )
                                                ],
                                              )
                                            : null,
                                      )),
                                ),
                              ),
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeInOut,
                            height: isReplying.isReply ? 50 : 0,
                            width: MediaQuery.of(context).size.width,
                            child: Padding(
                              padding: EdgeInsets.only(
                                  top: 2, left: 5, right: 5, bottom: 5),
                              child: Container(
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(7)),
                                child: ClipRect(
                                  child: AnimatedContainer(
                                      duration: Duration(milliseconds: 500),
                                      decoration: BoxDecoration(
                                          color: conversationContentList
                                                  .where((message) =>
                                                      message.messageID ==
                                                      isReplying.replyingTo)
                                                  .toList()
                                                  .isNotEmpty
                                              ? conversationContentList
                                                          .where((message) =>
                                                              message
                                                                  .messageID ==
                                                              isReplying
                                                                  .replyingTo)
                                                          .toList()[0]
                                                          .sender ==
                                                      state.userAuth.user
                                                          .entityId
                                                  ? Color(0xff1c7def)
                                                  : Color(0xffdedede)
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(7)),
                                      child: Padding(
                                        padding: EdgeInsets.all(7),
                                        child: isReplying.isReply
                                            ? Row(
                                                mainAxisSize: MainAxisSize.max,
                                                children: [
                                                  Expanded(
                                                      child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .center,
                                                    mainAxisSize:
                                                        MainAxisSize.max,
                                                    children: [
                                                      Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .start,
                                                          mainAxisSize:
                                                              MainAxisSize.max,
                                                          children: [
                                                            Text(
                                                              state.isUsingReplyAssist
                                                                  ? "Select messages for context"
                                                                  : "Use AI Reply Assist?",
                                                              style: TextStyle(
                                                                  fontSize: 12,
                                                                  color: conversationContentList
                                                                          .where((message) =>
                                                                              message.messageID ==
                                                                              isReplying
                                                                                  .replyingTo)
                                                                          .toList()
                                                                          .isNotEmpty
                                                                      ? conversationContentList.where((message) => message.messageID == isReplying.replyingTo).toList()[0].sender ==
                                                                              state
                                                                                  .userAuth.user.entityId
                                                                          ? Colors
                                                                              .white
                                                                          : Colors
                                                                              .black
                                                                      : Colors
                                                                          .transparent,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold),
                                                              textAlign:
                                                                  TextAlign
                                                                      .justify,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            )
                                                          ]),
                                                      Expanded(
                                                        child: SizedBox(),
                                                      ),
                                                      state.isUsingReplyAssist
                                                          ? Row(
                                                              children: [
                                                                ElevatedButton(
                                                                    style: ElevatedButton
                                                                        .styleFrom(
                                                                            backgroundColor: Colors
                                                                                .white,
                                                                            shape:
                                                                                RoundedRectangleBorder(
                                                                              borderRadius: BorderRadius.circular(10), // Rounded corners if needed
                                                                            )),
                                                                    onPressed:
                                                                        () => {
                                                                              // ContentValidator().printer(jsonEncode(state.replyAssistContext.map((rac) => rac.toJson()).toList()))
                                                                              postReplyAssistProcess(widget.conversationId, state.replyAssistContext)
                                                                            },
                                                                    child: Text(
                                                                      "Generate",
                                                                      style: TextStyle(
                                                                          fontSize:
                                                                              12,
                                                                          color:
                                                                              Color(0xFF565656)),
                                                                    )),
                                                                SizedBox(
                                                                  width: 5,
                                                                ),
                                                                ElevatedButton(
                                                                    style: ElevatedButton
                                                                        .styleFrom(
                                                                            backgroundColor: Colors
                                                                                .white,
                                                                            shape:
                                                                                RoundedRectangleBorder(
                                                                              borderRadius: BorderRadius.circular(10), // Rounded corners if needed
                                                                            )),
                                                                    onPressed:
                                                                        () => {
                                                                              StoreProvider.of<AppState>(context).dispatch(DispatchModel(setIsUsingReplyAssistT, false)),
                                                                              StoreProvider.of<AppState>(context).dispatch(DispatchModel(clearReplyAssistContextT, []))
                                                                            },
                                                                    child: Text(
                                                                      "Cancel",
                                                                      style: TextStyle(
                                                                          fontSize:
                                                                              12,
                                                                          color:
                                                                              Color(0xFF565656)),
                                                                    ))
                                                              ],
                                                            )
                                                          : ElevatedButton(
                                                              style: ElevatedButton
                                                                  .styleFrom(
                                                                      backgroundColor:
                                                                          Colors
                                                                              .white,
                                                                      shape:
                                                                          RoundedRectangleBorder(
                                                                        borderRadius:
                                                                            BorderRadius.circular(10), // Rounded corners if needed
                                                                      )),
                                                              onPressed: () => {
                                                                    StoreProvider.of<AppState>(
                                                                            context)
                                                                        .dispatch(DispatchModel(
                                                                            setIsUsingReplyAssistT,
                                                                            true))
                                                                  },
                                                              child: Text(
                                                                "Yes",
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    color: Color(
                                                                        0xFF565656)),
                                                              )),
                                                    ],
                                                  )),
                                                ],
                                              )
                                            : null,
                                      )),
                                ),
                              ),
                            ),
                          ),
                          // Attachments picked but not yet sent - matches
                          // webapp's composer attachment strip. Reviewable
                          // (each chip has its own remove "x") before
                          // hitting send, rather than uploading the
                          // instant something's picked.
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                            height: _stagedFiles.isEmpty ? 0 : 76,
                            color: p.surface,
                            child: ClipRect(
                              child: _stagedFiles.isEmpty
                                  ? const SizedBox.shrink()
                                  : ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: _stagedFiles.length,
                                      itemBuilder: (context, index) =>
                                          _stagedAttachmentChip(index),
                                    ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: p.surface,
                              border: Border(
                                top: BorderSide(
                                  width: 0.5,
                                  color: p.border,
                                ),
                              ),
                            ),
                            width: MediaQuery.of(context).size.width,
                            height: 55,
                            child: Padding(
                              padding: EdgeInsets.only(left: 5, right: 2),
                              child: Center(
                                child: Row(
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        ConstrainedBox(
                                          constraints: BoxConstraints(
                                              maxWidth: 40, maxHeight: 40),
                                          child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  elevation: 0,
                                                  padding: EdgeInsets.only(
                                                      top: 0,
                                                      bottom: 0,
                                                      left: 0,
                                                      right: 0)),
                                              onPressed: _pickFiles,
                                              child: Center(
                                                child: Icon(
                                                  Icons.add_circle_rounded,
                                                  color: CLColors.brand300,
                                                  size: 22,
                                                ),
                                              )),
                                        ),
                                        ConstrainedBox(
                                          constraints: BoxConstraints(
                                              maxWidth: 40, maxHeight: 40),
                                          child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  elevation: 0,
                                                  padding: EdgeInsets.only(
                                                      top: 0,
                                                      bottom: 0,
                                                      left: 0,
                                                      right: 0)),
                                              onPressed: _pickImages,
                                              child: Center(
                                                child: Icon(
                                                  Icons
                                                      .add_photo_alternate_rounded,
                                                  color: CLColors.brand300,
                                                  size: 24,
                                                ),
                                              )),
                                        ),
                                        if (_isRecordingVoice)
                                          ConstrainedBox(
                                            constraints: BoxConstraints(
                                                maxWidth: 40, maxHeight: 40),
                                            child: ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.transparent,
                                                    elevation: 0,
                                                    padding: EdgeInsets.only(
                                                        top: 0,
                                                        bottom: 0,
                                                        left: 0,
                                                        right: 0)),
                                                onPressed:
                                                    _cancelVoiceRecording,
                                                child: Center(
                                                  child: Icon(
                                                    Icons.close_rounded,
                                                    color: CLColors.pink,
                                                    size: 22,
                                                  ),
                                                )),
                                          ),
                                        ConstrainedBox(
                                          constraints: BoxConstraints(
                                              maxWidth: 40, maxHeight: 40),
                                          child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  elevation: 0,
                                                  padding: EdgeInsets.only(
                                                      top: 0,
                                                      bottom: 0,
                                                      left: 0,
                                                      right: 0)),
                                              onPressed: _isRecordingVoice
                                                  ? () =>
                                                      _stopAndSendVoiceRecording(
                                                          state)
                                                  : _startVoiceRecording,
                                              child: Center(
                                                child: Icon(
                                                  _isRecordingVoice
                                                      ? Icons.stop_circle
                                                      : Icons.mic_none_rounded,
                                                  color: _isRecordingVoice
                                                      ? CLColors.pink
                                                      : CLColors.brand300,
                                                  size: 24,
                                                ),
                                              )),
                                        )
                                      ],
                                    ),
                                    SizedBox(
                                      width: 0,
                                    ),
                                    Expanded(
                                        child: Padding(
                                      padding: EdgeInsets.all(5),
                                      child: Container(
                                        height: 45,
                                        decoration: BoxDecoration(
                                            color: p.input,
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        child: TextField(
                                          controller: _controller,
                                          onChanged: (value) {
                                            if (mounted) {
                                              setState(() {
                                                messageValue = value;
                                                if (value.trim() != "") {
                                                  if (conversationInfo !=
                                                      null) {
                                                    isTypingTimeout(
                                                        widget.conversationId,
                                                        conversationInfo!.users
                                                            .map((user) => user
                                                                .entityID
                                                                .toString())
                                                            .toList());
                                                  }
                                                }
                                              });
                                            }
                                          },
                                          style: TextStyle(
                                              fontSize: 12, color: p.text),
                                          decoration: InputDecoration(
                                              contentPadding: EdgeInsets.only(
                                                  top: 6,
                                                  bottom: 6,
                                                  left: 8,
                                                  right: 8),
                                              hintText: 'Write a message....',
                                              hintStyle:
                                                  TextStyle(color: p.text3),
                                              border: InputBorder.none),
                                        ),
                                      ),
                                    )),
                                    SizedBox(
                                      width: 0,
                                    ),
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                          maxWidth: 45, maxHeight: 40),
                                      child: ElevatedButton(
                                          key: ValueKey(
                                              "${combinedPendingAndMessagesList.length}_${pendingMessagesList.length}_${conversationContentList.length}"),
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.transparent,
                                              elevation: 0,
                                              padding: EdgeInsets.only(
                                                  top: 0,
                                                  bottom: 0,
                                                  left: 0,
                                                  right: 0)),
                                          onPressed: () {
                                            if (conversationInfo == null) {
                                              return;
                                            }
                                            final hasText =
                                                messageValue.trim().isNotEmpty;
                                            final hasFiles =
                                                _stagedFiles.isNotEmpty;
                                            if (!hasText && !hasFiles) return;

                                            // Captured before either send
                                            // call - sendMessageProcess
                                            // resets isReplying via
                                            // setState synchronously (the
                                            // part of an async function
                                            // before its first await runs
                                            // immediately), so reading
                                            // isReplying again afterward
                                            // for the files send would see
                                            // it already cleared.
                                            final wasReplying =
                                                isReplying.isReply;
                                            final replyingToId =
                                                isReplying.replyingTo;

                                            if (hasText) {
                                              sendMessageProcess(
                                                  state.userAuth.user.entityId,
                                                  widget.conversationId,
                                                  conversationInfo!.users
                                                      .map((user) =>
                                                          user.entityID)
                                                      .toList(),
                                                  "text",
                                                  conversationInfo?.type
                                                      as String,
                                                  messageValue,
                                                  wasReplying,
                                                  replyingToId);
                                            }
                                            if (hasFiles) {
                                              final filesToSend = _stagedFiles;
                                              setState(() => _stagedFiles = []);
                                              sendFilesProcess(
                                                  state.userAuth.user.entityId,
                                                  widget.conversationId,
                                                  conversationInfo?.type
                                                      as String,
                                                  filesToSend,
                                                  wasReplying,
                                                  replyingToId);
                                            }
                                            StoreProvider.of<AppState>(context)
                                                .dispatch(DispatchModel(
                                                    setIsUsingReplyAssistT,
                                                    false));
                                            StoreProvider.of<AppState>(context)
                                                .dispatch(DispatchModel(
                                                    clearReplyAssistContextT,
                                                    []));
                                          },
                                          child: Center(
                                            child: Icon(
                                              Icons.send_rounded,
                                              color: Color(0xff1c7def),
                                              size: 24,
                                            ),
                                          )),
                                    )
                                  ],
                                ),
                              ),
                            ),
                          )
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      converter: (store) {
        return store.state;
      },
    );
  }
}
