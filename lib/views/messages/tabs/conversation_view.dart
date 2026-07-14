import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
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
import 'package:chatterloop_app/models/http_models/request_models.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/messages_models/conversation_info_model.dart';
import 'package:chatterloop_app/models/messages_models/message_content_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';
import 'package:chatterloop_app/models/view_prop_models/conversation_view_props.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

class ConversationView extends StatefulWidget {
  final String conversationId;
  final Object? extra;

  const ConversationView({super.key, required this.conversationId, this.extra});

  @override
  ConversationStateView createState() => ConversationStateView();
}

class ConversationStateView extends State<ConversationView> {
  StreamSubscription<SSEModel>? _eventBusSubscription;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _controller = TextEditingController();

  bool isInitialized = false;
  bool isSeenMessageInitialized = false;
  bool isAutoScroll = true;
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

  // Resolved once at mount, not recomputed per build - both feed the
  // initial-load kickoff below, which must only ever run once per screen
  // instance (see _startLoading's doc comment).
  late final ConversationViewProps conversationMetaData;
  late final String _myAccountId;

  @override
  void initState() {
    super.initState();
    final extra = widget.extra;
    conversationMetaData = extra is ConversationViewProps
        ? extra
        : ConversationViewProps(
            widget.conversationId, "single", ConversationPreview("", ""));
    // appStore (a plain global, not StoreProvider.of(context)) - the
    // latter calls dependOnInheritedWidgetOfExactType, which asserts if
    // used before initState() completes.
    _myAccountId = appStore.state.userAuth.user.id;
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
        .getConversationSetupRequest(conversationMetaData.conversationID);
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

    final loadedMessages = await initConversationProcess(
        conversationMetaData.conversationID, range);
    if (!mounted) return;
    if (!loadedMessages) {
      setState(() {
        conversationLoadError = "This conversation could not be loaded.";
      });
      return;
    }
    getConversationInfoProcess(conversationMetaData.conversationID,
        conversationMetaData.conversationType);
    _eventBusSubscription = eventBus.on<SSEModel>().listen((SSEModel event) {
      if (event.event == "messages_list") {
        if (mounted) {
          int newRange = range + 1;
          if (conversationInfo != null) {
            seenMessagesProcess(
                ISeenNewMessagesRequest(
                    conversationMetaData.conversationID,
                    range,
                    conversationInfo!.users
                        .map((user) => user.userID.toString())
                        .toList(),
                    _unseenMessageIDs(_myAccountId)),
                newRange);
          }
          initConversationProcess(conversationMetaData.conversationID, newRange)
              .then((_) {
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

  @override
  void dispose() {
    _eventBusSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final minScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;

      if (currentScroll >= minScroll - 20) {
        if (!(range >= totalMessages)) {
          // setState(() {
          //   int newPostLength = postLength + 10;
          //   postLength = newPostLength;

          //   getPostsProcess(context, newPostLength);
          // });
          if (mounted) {
            if (!isRefreshed) {
              int oldRangeAdd = range + 20;

              if (conversationInfo != null) {
                initConversationProcess(
                    conversationInfo!.contactID, oldRangeAdd);
                setState(() {
                  range = oldRangeAdd;
                  isRefreshed = true;
                });

                ContentValidator().printer('$currentScroll | $minScroll');
                if (kDebugMode) {
                  print('Triggered 20 pixels before top!');
                }

                Future.delayed(Duration(milliseconds: 2500), () {
                  setState(() {
                    isRefreshed = false;
                  });
                });
              }
            }
          }
        }
        // You can load more items here or perform any action.
      }
    }
  }

  List<String> _unseenMessageIDs(String myAccountId) {
    return conversationContentList
        .where((message) => !message.seeners.contains(myAccountId))
        .map((message) => message.messageID)
        .toList();
  }

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

      // Server wraps the payload once (createJWT({data: flattenedResults})),
      // so decoded["data"] IS flattenedResults - there's no second nested
      // "data" key. The extra ["data"] here always resolved to null,
      // leaving conversationInfo permanently unset (blocking send/seen/typing).
      dynamic rawGetConversationInfo = decodedGetConversationInfo?["data"];
      if (rawGetConversationInfo is! Map) return;

      ConversationInfoModel conversationInfoFinal =
          ConversationInfoModel.fromJson(
              Map<String, dynamic>.from(rawGetConversationInfo));

      if (mounted) {
        setState(() {
          conversationInfo = conversationInfoFinal;
        });
      }

      if (!isSeenMessageInitialized) {
        seenMessagesProcess(
            ISeenNewMessagesRequest(
                conversationMetaData.conversationID,
                range,
                conversationInfoFinal.users
                    .map((user) => user.userID.toString())
                    .toList(),
                _unseenMessageIDs(_myAccountId)),
            range);
      }

      // if (kDebugMode) {
      //   // print(rawContactsList);
      //   print(rawGetConversationInfo);
      // }
    }
  }

  Future<void> seenMessagesProcess(
      ISeenNewMessagesRequest payload, int rangeProp) async {
    if (mounted) {
      setState(() {
        isSeenMessageInitialized = true;
      });
    }

    EncodedResponse? getConversationInfoResponse =
        await ConversationsApi().seenNewMessagesRequest(payload, rangeProp);

    if (getConversationInfoResponse != null) {
      if (kDebugMode) {
        // print(rawContactsList);
        print(getConversationInfoResponse);
      }
    }
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

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AppState>(
      builder: (context, state) {
        final p = cl(context);
        final matchingMessages = state.messages
            .where((item) =>
                item.conversationID == conversationMetaData.conversationID)
            .toList();
        // Guarded on the *filtered* list being empty, not state.messages
        // overall - this conversation legitimately has no entry yet in
        // the conversations list right after being opened fresh (e.g.
        // from a contact's Message button before any message exists),
        // and .reduce()/[0] on an empty filtered list throws.
        int unreadTotal = matchingMessages.isEmpty
            ? 0
            : matchingMessages
                .map((message) => message.unread)
                .reduce((a, b) => a + b);
        String newMessageIDOnTop =
            matchingMessages.isEmpty ? "" : matchingMessages[0].messageID;

        return Scaffold(
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
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: 40,
                                    maxWidth: 40,
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: p.border,
                                      border: Border.all(
                                        color: p.border,
                                        width: 1,
                                      ),
                                      borderRadius: BorderRadius.circular(50),
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.all(10),
                                      child: Image.network(
                                        conversationMetaData
                                            .conversationPreview.profile,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 15),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        conversationMetaData
                                            .conversationPreview.previewName,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: p.text,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        conversationMetaData.conversationType ==
                                                "single"
                                            ? "Recently Active"
                                            : "Members are Active",
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
                                  crossAxisAlignment: CrossAxisAlignment.center,
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
                                          onPressed: () {},
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
                                          onPressed: () {},
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
                                                color: p.text2, fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                )
                              : (isSettingUp || !isInitialized)
                                  ? Center(
                                      child: CircularProgressIndicator(
                                          color: p.brand))
                                  : combinedPendingAndMessagesList.isEmpty
                                      ? Center(
                                          child: Padding(
                                            padding: const EdgeInsets.all(24),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.chat_bubble_outline,
                                                    size: 40, color: p.text3),
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
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                        color: p.text2,
                                                        fontSize: 13)),
                                              ],
                                            ),
                                          ),
                                        )
                                      : ListView.builder(
                                          key: ValueKey(
                                              "${pendingMessagesList.length}_${state.isTypingList.length}_${unreadTotal}_${newMessageIDOnTop}_${conversationContentList.isEmpty ? "" : conversationContentList[conversationContentList.length - 1].messageID}"),
                                          // key: ValueKey(
                                          //     "${range}_${conversationMetaData.conversationID}_${pendingMessagesList.length}_${conversationContentList.length}_${state.isTypingList.length}"),
                                          reverse: true,
                                          controller: _scrollController,
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 5),
                                          itemCount: combinedPendingAndMessagesList
                                              .length, //conversationContentList.length
                                          itemBuilder: (context, index) {
                                            bool hasConversationTypingActivity =
                                                state
                                                        .isTypingList
                                                        .where((typing) =>
                                                            typing
                                                                .conversationID ==
                                                            conversationMetaData
                                                                .conversationID)
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
                                                  if (!(range >= totalMessages))
                                                    Padding(
                                                      padding: EdgeInsets.only(
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
                                                          index] is MessageContent)
                                                    Column(
                                                      children: [
                                                        SizedBox(
                                                          width: MediaQuery.of(
                                                                  context)
                                                              .size
                                                              .width,
                                                          child:
                                                              MessageContentWidget(
                                                            messageContent: combinedPendingAndMessagesList[
                                                                    combinedPendingAndMessagesList
                                                                            .length -
                                                                        1 -
                                                                        index]
                                                                as MessageContent,
                                                            previousContentUserID: index >
                                                                        0 &&
                                                                    index <
                                                                        combinedPendingAndMessagesList.length -
                                                                            1
                                                                ? combinedPendingAndMessagesList[
                                                                        combinedPendingAndMessagesList.length -
                                                                            1 -
                                                                            index -
                                                                            1]
                                                                    .sender
                                                                : index == 0
                                                                    ? "start"
                                                                    : "end",
                                                            currentUserID: state
                                                                .userAuth
                                                                .user
                                                                .id,
                                                            onPressed: (bool
                                                                    isReply,
                                                                String
                                                                    replyingTo) {
                                                              if (mounted) {
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
                                                                setState(() {
                                                                  isReplying =
                                                                      IsReplying(
                                                                          isReply,
                                                                          replyingTo);
                                                                });
                                                              }
                                                            },
                                                          ),
                                                        ),
                                                        if (combinedPendingAndMessagesList[
                                                                combinedPendingAndMessagesList
                                                                        .length -
                                                                    1 -
                                                                    index]
                                                            is MessageContent)
                                                          (combinedPendingAndMessagesList[
                                                                              combinedPendingAndMessagesList.length - 1 - index]
                                                                          as MessageContent)
                                                                      .messageType !=
                                                                  "notif"
                                                              ? conversationInfo !=
                                                                      null
                                                                  ? (combinedPendingAndMessagesList[combinedPendingAndMessagesList.length - 1 - index] as MessageContent)
                                                                              .seeners
                                                                              .length ==
                                                                          conversationInfo
                                                                              ?.users
                                                                              .length
                                                                      ? index - pendingMessagesList.length ==
                                                                              0
                                                                          ? Padding(
                                                                              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 7),
                                                                              child: SizedBox(
                                                                                width: double.infinity,
                                                                                child: Text(
                                                                                  conversationMetaData.conversationType == "single" ? "Seen" : "Seen by everyone",
                                                                                  textAlign: (combinedPendingAndMessagesList[combinedPendingAndMessagesList.length - 1 - index] as MessageContent).sender == state.userAuth.user.id ? TextAlign.end : TextAlign.start,
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
                                                                          ? conversationMetaData.conversationType != "single"
                                                                              ? Padding(
                                                                                  padding: EdgeInsets.symmetric(vertical: 4, horizontal: 7),
                                                                                  child: SizedBox(
                                                                                    width: double.infinity,
                                                                                    child: Text(
                                                                                      "Seen by ${(combinedPendingAndMessagesList[combinedPendingAndMessagesList.length - 1 - index] as MessageContent).seeners.join(", ").replaceAll(state.userAuth.user.id, "you")}",
                                                                                      textAlign: (combinedPendingAndMessagesList[combinedPendingAndMessagesList.length - 1 - index] as MessageContent).sender == state.userAuth.user.id ? TextAlign.end : TextAlign.start,
                                                                                      style: TextStyle(
                                                                                        fontSize: 12,
                                                                                        color: Color(0xFF565656),
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                )
                                                                              : SizedBox.shrink()
                                                                          : SizedBox.shrink()
                                                                  : SizedBox.shrink()
                                                              : SizedBox.shrink(),
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
                                                          index] is PendingMessages)
                                                    Column(
                                                      children: [
                                                        SizedBox(
                                                          width: MediaQuery.of(
                                                                  context)
                                                              .size
                                                              .width,
                                                          child:
                                                              PendingContentWidget(
                                                            messageID: (combinedPendingAndMessagesList[
                                                                        combinedPendingAndMessagesList.length -
                                                                            1 -
                                                                            index]
                                                                    as PendingMessages)
                                                                .pendingID,
                                                            content: (combinedPendingAndMessagesList[
                                                                        combinedPendingAndMessagesList.length -
                                                                            1 -
                                                                            index]
                                                                    as PendingMessages)
                                                                .content,
                                                            contentType: (combinedPendingAndMessagesList[
                                                                        combinedPendingAndMessagesList.length -
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
                                                    SizedBox(
                                                      width:
                                                          MediaQuery.of(context)
                                                              .size
                                                              .width,
                                                      child:
                                                          MessageContentWidget(
                                                              messageContent:
                                                                  contentItem,
                                                              previousContentUserID:
                                                                  previousContentUserID,
                                                              currentUserID:
                                                                  state.userAuth
                                                                      .user.id,
                                                              onPressed: (bool
                                                                      isReply,
                                                                  String
                                                                      replyingTo) {
                                                                if (mounted) {
                                                                  StoreProvider.of<
                                                                              AppState>(
                                                                          context)
                                                                      .dispatch(DispatchModel(
                                                                          setIsUsingReplyAssistT,
                                                                          false));
                                                                  StoreProvider.of<
                                                                              AppState>(
                                                                          context)
                                                                      .dispatch(DispatchModel(
                                                                          clearReplyAssistContextT,
                                                                          []));
                                                                  setState(() {
                                                                    isReplying =
                                                                        IsReplying(
                                                                            isReply,
                                                                            replyingTo);
                                                                  });
                                                                }
                                                              }),
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
                                                                            top:
                                                                                4,
                                                                            bottom:
                                                                                2,
                                                                            left:
                                                                                7,
                                                                            right:
                                                                                7),
                                                                        child:
                                                                            SizedBox(
                                                                          width:
                                                                              double.infinity,
                                                                          child:
                                                                              Text(
                                                                            conversationMetaData.conversationType == "single"
                                                                                ? "Seen"
                                                                                : "Seen by everyone",
                                                                            textAlign: contentItem.sender == state.userAuth.user.id
                                                                                ? TextAlign.end
                                                                                : TextAlign.start,
                                                                            style:
                                                                                TextStyle(
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
                                                                    ? conversationMetaData.conversationType !=
                                                                            "single"
                                                                        ? Padding(
                                                                            padding: EdgeInsets.only(
                                                                                top: 4,
                                                                                bottom: 2,
                                                                                left: 7,
                                                                                right: 7),
                                                                            child:
                                                                                SizedBox(
                                                                              width: double.infinity,
                                                                              child: Text(
                                                                                "Seen by ${contentItem.seeners.join(", ").replaceAll(state.userAuth.user.id, "you")}",
                                                                                textAlign: contentItem.sender == state.userAuth.user.id ? TextAlign.end : TextAlign.start,
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
                                                          messageID: contentItem
                                                              .pendingID,
                                                          content: contentItem
                                                              .content,
                                                          contentType:
                                                              contentItem.type,
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
                                                            message.messageID ==
                                                            isReplying
                                                                .replyingTo)
                                                        .toList()[0]
                                                        .sender ==
                                                    state.userAuth.user.id
                                                ? Color(0xff1c7def)
                                                : Color(0xffdedede)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(7)),
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
                                                      CrossAxisAlignment.start,
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
                                                            "Replying to ${conversationContentList.where((message) => message.messageID == isReplying.replyingTo).toList().isNotEmpty ? conversationContentList.where((message) => message.messageID == isReplying.replyingTo).toList()[0].sender == state.userAuth.user.id ? "your message" : "@${conversationContentList.where((message) => message.messageID == isReplying.replyingTo).toList()[0].sender}" : ""}",
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
                                                                                .userAuth.user.id
                                                                        ? Colors
                                                                            .white
                                                                        : Colors
                                                                            .black
                                                                    : Colors
                                                                        .transparent,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold),
                                                            textAlign: TextAlign
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
                                                                      bottom: 0,
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
                                                                          BorderRadius.circular(
                                                                              22)),
                                                                  width: 22,
                                                                  height: 22,
                                                                  child: Center(
                                                                    child: Icon(
                                                                      color: Colors
                                                                          .white,
                                                                      Icons
                                                                          .close,
                                                                      size: 12,
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
                                                            message.messageID ==
                                                            isReplying
                                                                .replyingTo)
                                                        .toList()[0]
                                                        .sender ==
                                                    state.userAuth.user.id
                                                ? Color(0xff1c7def)
                                                : Color(0xffdedede)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(7)),
                                    child: Padding(
                                      padding: EdgeInsets.all(7),
                                      child: isReplying.isReply
                                          ? Row(
                                              mainAxisSize: MainAxisSize.max,
                                              children: [
                                                Expanded(
                                                    child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
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
                                                                                .userAuth.user.id
                                                                        ? Colors
                                                                            .white
                                                                        : Colors
                                                                            .black
                                                                    : Colors
                                                                        .transparent,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold),
                                                            textAlign: TextAlign
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
                                                                            borderRadius:
                                                                                BorderRadius.circular(10), // Rounded corners if needed
                                                                          )),
                                                                  onPressed:
                                                                      () => {
                                                                            // ContentValidator().printer(jsonEncode(state.replyAssistContext.map((rac) => rac.toJson()).toList()))
                                                                            postReplyAssistProcess(conversationMetaData.conversationID,
                                                                                state.replyAssistContext)
                                                                          },
                                                                  child: Text(
                                                                    "Generate",
                                                                    style: TextStyle(
                                                                        fontSize:
                                                                            12,
                                                                        color: Color(
                                                                            0xFF565656)),
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
                                                                            borderRadius:
                                                                                BorderRadius.circular(10), // Rounded corners if needed
                                                                          )),
                                                                  onPressed:
                                                                      () => {
                                                                            StoreProvider.of<AppState>(context).dispatch(DispatchModel(setIsUsingReplyAssistT,
                                                                                false)),
                                                                            StoreProvider.of<AppState>(context).dispatch(DispatchModel(clearReplyAssistContextT,
                                                                                []))
                                                                          },
                                                                  child: Text(
                                                                    "Cancel",
                                                                    style: TextStyle(
                                                                        fontSize:
                                                                            12,
                                                                        color: Color(
                                                                            0xFF565656)),
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
                                                                          BorderRadius.circular(
                                                                              10), // Rounded corners if needed
                                                                    )),
                                                            onPressed: () => {
                                                                  StoreProvider.of<
                                                                              AppState>(
                                                                          context)
                                                                      .dispatch(DispatchModel(
                                                                          setIsUsingReplyAssistT,
                                                                          true))
                                                                },
                                                            child: Text(
                                                              "Yes",
                                                              style: TextStyle(
                                                                  fontSize: 12,
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
                                    mainAxisAlignment: MainAxisAlignment.center,
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
                                            onPressed: () {},
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
                                            onPressed: () {},
                                            child: Center(
                                              child: Icon(
                                                Icons
                                                    .add_photo_alternate_rounded,
                                                color: CLColors.brand300,
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
                                                if (conversationInfo != null) {
                                                  isTypingTimeout(
                                                      conversationMetaData
                                                          .conversationID,
                                                      conversationInfo!.users
                                                          .map((user) => user
                                                              .userID
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
                                            backgroundColor: Colors.transparent,
                                            elevation: 0,
                                            padding: EdgeInsets.only(
                                                top: 0,
                                                bottom: 0,
                                                left: 0,
                                                right: 0)),
                                        onPressed: () {
                                          if (conversationInfo != null) {
                                            sendMessageProcess(
                                                state.userAuth.user.id,
                                                conversationMetaData
                                                    .conversationID,
                                                conversationInfo!.users
                                                    .map((user) =>
                                                        user.userID.toString())
                                                    .toList(),
                                                "text",
                                                conversationInfo?.type
                                                    as String,
                                                messageValue,
                                                isReplying.isReply,
                                                isReplying.replyingTo);
                                            StoreProvider.of<AppState>(context)
                                                .dispatch(DispatchModel(
                                                    setIsUsingReplyAssistT,
                                                    false));
                                            StoreProvider.of<AppState>(context)
                                                .dispatch(DispatchModel(
                                                    clearReplyAssistContextT,
                                                    []));
                                          }
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
        );
      },
      converter: (store) {
        return store.state;
      },
    );
  }
}
