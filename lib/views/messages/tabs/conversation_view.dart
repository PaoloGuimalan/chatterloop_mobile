import 'dart:async';

import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/http_requests.dart';
import 'package:chatterloop_app/core/requests/sse_connection.dart';
import 'package:chatterloop_app/core/reusables/loaders/spinning_loader.dart';
import 'package:chatterloop_app/core/reusables/loaders/typing_loader.dart';
import 'package:chatterloop_app/core/reusables/widgets/message_content_widget.dart';
import 'package:chatterloop_app/core/reusables/widgets/pending_content_widget.dart';
import 'package:chatterloop_app/core/routes/app_routes.dart';
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

class ConversationView extends StatefulWidget {
  // final MessageItem conversationMetaData;

  const ConversationView({super.key});

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

  @override
  void initState() {
    super.initState();
    combinedPendingAndMessagesList = [
      ...conversationContentList,
      ...pendingMessagesList
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.addListener(_onScroll);
    });
    // _conversationMetaData = widget.conversationMetaData;
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

  Future<void> initConversationProcess(
      String conversationID, int rangeProp) async {
    EncodedResponse? initConversationResponse =
        await APIRequests().initConversationRequest(conversationID, rangeProp);

    if (initConversationResponse != null) {
      Map<String, dynamic>? decodedInitConversation =
          jwt.verifyJwt(initConversationResponse.result, secretKey);

      List<dynamic> rawInitConversation = decodedInitConversation?["messages"];
      int totalMessagesResponse = decodedInitConversation?["total"];

      List<MessageContent> messageContentList = rawInitConversation
          .map((message) => MessageContent.fromJson(message))
          .toList();

      if (mounted) {
        setState(() {
          conversationContentList = messageContentList;
          combinedPendingAndMessagesList = [
            ...messageContentList,
            ...pendingMessagesList
          ];
          isInitialized = true;
          totalMessages = totalMessagesResponse;
        });
      }

      // if (kDebugMode) {
      //   // print(rawContactsList);
      //   print(messageContentList);
      // }
    }
  }

  Future<void> getConversationInfoProcess(
      String conversationID, String conversationType) async {
    EncodedResponse? getConversationInfoResponse = await APIRequests()
        .getConversationInfoRequest(conversationID, conversationType);

    if (getConversationInfoResponse != null) {
      Map<String, dynamic>? decodedGetConversationInfo =
          jwt.verifyJwt(getConversationInfoResponse.result, secretKey);

      dynamic rawGetConversationInfo =
          decodedGetConversationInfo?["data"]["data"];

      ConversationInfoModel conversationInfoFinal =
          ConversationInfoModel.fromJson(rawGetConversationInfo);

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

  Future<void> seenMessagesProcess(
      ISeenNewMessagesRequest payload, int rangeProp) async {
    if (mounted) {
      setState(() {
        isSeenMessageInitialized = true;
      });
    }

    EncodedResponse? getConversationInfoResponse =
        await APIRequests().seenNewMessagesRequest(payload, rangeProp);

    if (getConversationInfoResponse != null) {
      if (kDebugMode) {
        // print(rawContactsList);
        print(getConversationInfoResponse);
      }
    }
  }

  Future<void> postReplyAssistProcess(
      String conversationID, List<ReplyAssistContext> messageIDs) async {
    MessageBasedResponse? postReplyAssistResponse =
        await APIRequests().postReplyAssistRequest(conversationID, messageIDs);

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
        await APIRequests().isTypingRequest(payload);

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

      EncodedResponse? sendMessageResponse = await APIRequests()
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
    final ConversationViewProps conversationMetaData =
        ModalRoute.of(context)?.settings.arguments as ConversationViewProps;
    return StoreConnector<AppState, AppState>(
      builder: (context, state) {
        int unreadTotal = state.messages.isEmpty
            ? 0
            : state.messages
                .where((item) =>
                    item.conversationID == conversationMetaData.conversationID)
                .map((message) => message.unread)
                .reduce((a, b) => a + b);
        String newMessageIDOnTop = state.messages.isEmpty
            ? ""
            : state.messages
                .where((item) =>
                    item.conversationID == conversationMetaData.conversationID)
                .toList()[0]
                .messageID;

        ContentValidator().printer(newMessageIDOnTop);

        if (conversationContentList.isEmpty && !isInitialized) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            initConversationProcess(conversationMetaData.conversationID, range);
            getConversationInfoProcess(conversationMetaData.conversationID,
                conversationMetaData.conversationType);
            _eventBusSubscription =
                eventBus.on<SSEModel>().listen((SSEModel event) {
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
                                .toList()),
                        newRange);
                  }
                  initConversationProcess(
                          conversationMetaData.conversationID, newRange)
                      .then((_) {
                    setState(() {
                      range = newRange;
                    });
                  });
                }
              }
            });
          });
        }

        if (!isSeenMessageInitialized) {
          if (conversationInfo != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              seenMessagesProcess(
                  ISeenNewMessagesRequest(
                      conversationMetaData.conversationID,
                      range,
                      conversationInfo!.users
                          .map((user) => user.userID.toString())
                          .toList()),
                  range);
            });
          }
        }
        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: Container(
                color: Colors.white,
                width: MediaQuery.of(context).size.width,
                child: Stack(
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          height: 90,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              bottom: BorderSide(
                                width: 0.5,
                                color: Color(0xffd2d2d2),
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
                                        AppRoutes
                                            .privateNavigatorKey.currentState
                                            ?.popAndPushNamed("/messages");
                                      },
                                      child: Center(
                                        child: Icon(
                                          Icons.arrow_back_ios_new_rounded,
                                          color: Color(0xff555555),
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
                                      color: Color(0xffd2d2d2),
                                      border: Border.all(
                                        color: Color(0xffd2d2d2),
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
                                          color: Color(0xFF565656),
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
                                          color: Color(0xFF565656),
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
                                              color: Color(0xff4994ec),
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
                                              color: Color(0xff4caf50),
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
                          child: ListView.builder(
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
                              bool hasConversationTypingActivity = state
                                      .isTypingList
                                      .where((typing) =>
                                          typing.conversationID ==
                                          conversationMetaData.conversationID)
                                      .toList()
                                      .isNotEmpty
                                  ? true
                                  : false;

                              if (index ==
                                  combinedPendingAndMessagesList.length - 1) {
                                return Column(
                                  children: [
                                    // MessageContent item
                                    if (!(range >= totalMessages))
                                      Padding(
                                        padding: EdgeInsets.only(top: 10),
                                        child: SpinningLoaderWidget(
                                            isLoading: true,
                                            isFromServer: false),
                                      ),
                                    if (combinedPendingAndMessagesList[
                                        combinedPendingAndMessagesList.length -
                                            1 -
                                            index] is MessageContent)
                                      Column(
                                        children: [
                                          SizedBox(
                                            width: MediaQuery.of(context)
                                                .size
                                                .width,
                                            child: MessageContentWidget(
                                              messageContent:
                                                  combinedPendingAndMessagesList[
                                                      combinedPendingAndMessagesList
                                                              .length -
                                                          1 -
                                                          index] as MessageContent,
                                              previousContentUserID: index >
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
                                                      : "end",
                                              currentUserID:
                                                  state.userAuth.user.userID,
                                              onPressed: (bool isReply,
                                                  String replyingTo) {
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
                                                  setState(() {
                                                    isReplying = IsReplying(
                                                        isReply, replyingTo);
                                                  });
                                                }
                                              },
                                            ),
                                          ),
                                          if (combinedPendingAndMessagesList[
                                              combinedPendingAndMessagesList.length -
                                                  1 -
                                                  index] is MessageContent)
                                            (combinedPendingAndMessagesList[
                                                                combinedPendingAndMessagesList.length -
                                                                    1 -
                                                                    index]
                                                            as MessageContent)
                                                        .messageType !=
                                                    "notif"
                                                ? conversationInfo != null
                                                    ? (combinedPendingAndMessagesList[
                                                                        combinedPendingAndMessagesList.length -
                                                                            1 -
                                                                            index]
                                                                    as MessageContent)
                                                                .seeners
                                                                .length ==
                                                            conversationInfo
                                                                ?.users.length
                                                        ? index -
                                                                    pendingMessagesList
                                                                        .length ==
                                                                0
                                                            ? Padding(
                                                                padding: EdgeInsets
                                                                    .symmetric(
                                                                        vertical:
                                                                            4,
                                                                        horizontal:
                                                                            7),
                                                                child: SizedBox(
                                                                  width: double
                                                                      .infinity,
                                                                  child: Text(
                                                                    conversationMetaData.conversationType ==
                                                                            "single"
                                                                        ? "Seen"
                                                                        : "Seen by everyone",
                                                                    textAlign: (combinedPendingAndMessagesList[combinedPendingAndMessagesList.length - 1 - index] as MessageContent).sender ==
                                                                            state
                                                                                .userAuth.user.userID
                                                                        ? TextAlign
                                                                            .end
                                                                        : TextAlign
                                                                            .start,
                                                                    style:
                                                                        TextStyle(
                                                                      fontSize:
                                                                          12,
                                                                      color: Color(
                                                                          0xFF565656),
                                                                    ),
                                                                  ),
                                                                ),
                                                              )
                                                            : SizedBox.shrink()
                                                        : index -
                                                                    pendingMessagesList
                                                                        .length ==
                                                                0
                                                            ? conversationMetaData
                                                                        .conversationType !=
                                                                    "single"
                                                                ? Padding(
                                                                    padding: EdgeInsets.symmetric(
                                                                        vertical:
                                                                            4,
                                                                        horizontal:
                                                                            7),
                                                                    child:
                                                                        SizedBox(
                                                                      width: double
                                                                          .infinity,
                                                                      child:
                                                                          Text(
                                                                        "Seen by ${(combinedPendingAndMessagesList[combinedPendingAndMessagesList.length - 1 - index] as MessageContent).seeners.join(", ").replaceAll(state.userAuth.user.userID, "you")}",
                                                                        textAlign: (combinedPendingAndMessagesList[combinedPendingAndMessagesList.length - 1 - index] as MessageContent).sender ==
                                                                                state.userAuth.user.userID
                                                                            ? TextAlign.end
                                                                            : TextAlign.start,
                                                                        style:
                                                                            TextStyle(
                                                                          fontSize:
                                                                              12,
                                                                          color:
                                                                              Color(0xFF565656),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  )
                                                                : SizedBox
                                                                    .shrink()
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
                                        combinedPendingAndMessagesList.length -
                                            1 -
                                            index] is PendingMessages)
                                      Column(
                                        children: [
                                          SizedBox(
                                            width: MediaQuery.of(context)
                                                .size
                                                .width,
                                            child: PendingContentWidget(
                                              messageID:
                                                  (combinedPendingAndMessagesList[
                                                              combinedPendingAndMessagesList
                                                                      .length -
                                                                  1 -
                                                                  index]
                                                          as PendingMessages)
                                                      .pendingID,
                                              content:
                                                  (combinedPendingAndMessagesList[
                                                              combinedPendingAndMessagesList
                                                                      .length -
                                                                  1 -
                                                                  index]
                                                          as PendingMessages)
                                                      .content,
                                              contentType:
                                                  (combinedPendingAndMessagesList[
                                                              combinedPendingAndMessagesList
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
                                    combinedPendingAndMessagesList.length -
                                        1 -
                                        index] is MessageContent) {
                                  MessageContent contentItem =
                                      combinedPendingAndMessagesList[
                                          combinedPendingAndMessagesList
                                                  .length -
                                              1 -
                                              index];
                                  String previousContentUserID = index > 0 &&
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
                                            MediaQuery.of(context).size.width,
                                        child: MessageContentWidget(
                                            messageContent: contentItem,
                                            previousContentUserID:
                                                previousContentUserID,
                                            currentUserID:
                                                state.userAuth.user.userID,
                                            onPressed: (bool isReply,
                                                String replyingTo) {
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
                                                setState(() {
                                                  isReplying = IsReplying(
                                                      isReply, replyingTo);
                                                });
                                              }
                                            }),
                                      ),
                                      contentItem.messageType != "notif"
                                          ? conversationInfo != null
                                              ? contentItem.seeners.length ==
                                                      conversationInfo
                                                          ?.users.length
                                                  ? index -
                                                              pendingMessagesList
                                                                  .length ==
                                                          0
                                                      ? Padding(
                                                          padding:
                                                              EdgeInsets.only(
                                                                  top: 4,
                                                                  bottom: 2,
                                                                  left: 7,
                                                                  right: 7),
                                                          child: SizedBox(
                                                            width:
                                                                double.infinity,
                                                            child: Text(
                                                              conversationMetaData
                                                                          .conversationType ==
                                                                      "single"
                                                                  ? "Seen"
                                                                  : "Seen by everyone",
                                                              textAlign: contentItem
                                                                          .sender ==
                                                                      state
                                                                          .userAuth
                                                                          .user
                                                                          .userID
                                                                  ? TextAlign
                                                                      .end
                                                                  : TextAlign
                                                                      .start,
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                color: Color(
                                                                    0xFF565656),
                                                              ),
                                                            ),
                                                          ),
                                                        )
                                                      : SizedBox(
                                                          height: 0,
                                                        )
                                                  : index -
                                                              pendingMessagesList
                                                                  .length ==
                                                          0
                                                      ? conversationMetaData
                                                                  .conversationType !=
                                                              "single"
                                                          ? Padding(
                                                              padding: EdgeInsets
                                                                  .only(
                                                                      top: 4,
                                                                      bottom: 2,
                                                                      left: 7,
                                                                      right: 7),
                                                              child: SizedBox(
                                                                width: double
                                                                    .infinity,
                                                                child: Text(
                                                                  "Seen by ${contentItem.seeners.join(", ").replaceAll(state.userAuth.user.userID, "you")}",
                                                                  textAlign: contentItem
                                                                              .sender ==
                                                                          state
                                                                              .userAuth
                                                                              .user
                                                                              .userID
                                                                      ? TextAlign
                                                                          .end
                                                                      : TextAlign
                                                                          .start,
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    color: Color(
                                                                        0xFF565656),
                                                                  ),
                                                                ),
                                                              ),
                                                            )
                                                          : SizedBox(
                                                              height: 0,
                                                            )
                                                      : SizedBox(
                                                          height: 0,
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
                                    combinedPendingAndMessagesList.length -
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
                                          width:
                                              MediaQuery.of(context).size.width,
                                          child: PendingContentWidget(
                                            messageID: contentItem.pendingID,
                                            content: contentItem.content,
                                            contentType: contentItem.type,
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
                                                    state.userAuth.user.userID
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
                                                            "Replying to ${conversationContentList.where((message) => message.messageID == isReplying.replyingTo).toList().isNotEmpty ? conversationContentList.where((message) => message.messageID == isReplying.replyingTo).toList()[0].sender == state.userAuth.user.userID ? "your message" : "@${conversationContentList.where((message) => message.messageID == isReplying.replyingTo).toList()[0].sender}" : ""}",
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
                                                                                .userAuth.user.userID
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
                                                                        .userID
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
                                                    state.userAuth.user.userID
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
                                                                                .userAuth.user.userID
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
                            color: Colors.white,
                            border: Border(
                              top: BorderSide(
                                width: 0.5,
                                color: Color(0xffd2d2d2),
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
                                                color: Color(0xff90caf9),
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
                                                color: Color(0xff8cbcd6),
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
                                          color: Color(0xfff6f6f6),
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
                                        style: TextStyle(fontSize: 12),
                                        decoration: InputDecoration(
                                            contentPadding: EdgeInsets.only(
                                                top: 6,
                                                bottom: 6,
                                                left: 8,
                                                right: 8),
                                            fillColor: Colors.white,
                                            hintText: 'Write a message....',
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
                                                state.userAuth.user.userID,
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
