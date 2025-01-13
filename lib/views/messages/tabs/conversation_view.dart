import 'dart:async';

import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/requests/http_requests.dart';
import 'package:chatterloop_app/core/requests/sse_connection.dart';
import 'package:chatterloop_app/core/reusables/widgets/message_content_widget.dart';
import 'package:chatterloop_app/core/routes/app_routes.dart';
import 'package:chatterloop_app/models/http_models/request_models.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/messages_models/conversation_info_model.dart';
import 'package:chatterloop_app/models/messages_models/message_content_model.dart';
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
  bool isInitialized = false;
  bool isSeenMessageInitialized = false;
  bool isAutoScroll = true;
  List<MessageContent> conversationContentList = [];
  ConversationInfoModel? conversationInfo;
  int range = 20;

  @override
  void initState() {
    super.initState();
    // _conversationMetaData = widget.conversationMetaData;
  }

  @override
  void dispose() {
    _eventBusSubscription?.cancel();
    super.dispose();
  }

  Future<void> initConversationProcess(
      String conversationID, int rangeProp) async {
    EncodedResponse? initConversationResponse =
        await APIRequests().initConversationRequest(conversationID, rangeProp);

    if (initConversationResponse != null) {
      Map<String, dynamic>? decodedInitConversation =
          jwt.verifyJwt(initConversationResponse.result, secretKey);

      List<dynamic> rawInitConversation = decodedInitConversation?["messages"];

      List<MessageContent> messageContentList = rawInitConversation
          .map((message) => MessageContent.fromJson(message))
          .toList();

      if (mounted) {
        setState(() {
          conversationContentList = messageContentList;
          isInitialized = true;
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

  @override
  Widget build(BuildContext context) {
    final ConversationViewProps conversationMetaData =
        ModalRoute.of(context)?.settings.arguments as ConversationViewProps;
    return StoreConnector<AppState, AppState>(
      builder: (context, state) {
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
                                        privateNavigatorKey.currentState
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
                                "${range}_${conversationMetaData.conversationID}"),
                            reverse: true,
                            controller: _scrollController,
                            padding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            itemCount: conversationContentList.length,
                            itemBuilder: (context, index) {
                              MessageContent contentItem =
                                  conversationContentList[
                                      conversationContentList.length -
                                          1 -
                                          index];
                              String previousContentUserID = index > 0 &&
                                      index < conversationContentList.length - 1
                                  ? conversationContentList[
                                          conversationContentList.length -
                                              1 -
                                              index -
                                              1]
                                      .sender
                                  : index == 0
                                      ? "start"
                                      : "end";

                              return SizedBox(
                                width: MediaQuery.of(context).size.width,
                                child: MessageContentWidget(
                                  messageContent: contentItem,
                                  previousContentUserID: previousContentUserID,
                                  currentUserID: state.userAuth.user.userID,
                                ),
                              );
                            },
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
                                        onChanged: (value) {},
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
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            elevation: 0,
                                            padding: EdgeInsets.only(
                                                top: 0,
                                                bottom: 0,
                                                left: 0,
                                                right: 0)),
                                        onPressed: () {},
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
