import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/requests/http_requests.dart';
import 'package:chatterloop_app/core/routes/app_routes.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/messages_models/messages_list_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class MessagesView extends StatefulWidget {
  const MessagesView({super.key});

  @override
  MessagesStateView createState() => MessagesStateView();
}

class MessagesStateView extends State<MessagesView> {
  List<MessageItem> messagesList = [];

  @override
  void initState() {
    super.initState();
  }

  Future<void> getConversationListProcess() async {
    EncodedResponse? getConversationListResponse =
        await APIRequests().getConversationListRequest();

    if (getConversationListResponse != null) {
      Map<String, dynamic>? decodedConversationList =
          jwt.verifyJwt(getConversationListResponse.result, secretKey);

      List<dynamic> rawConversationList =
          decodedConversationList?["conversationslist"];

      List<MessageItem> spreadedConversationList = rawConversationList
          .map((message) => MessageItem.fromJson(message))
          .toList();

      setState(() {
        messagesList = spreadedConversationList;
      });

      if (kDebugMode) {
        print(rawConversationList);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AppState>(builder: (context, state) {
      if (messagesList.isEmpty) {
        getConversationListProcess();
      }
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Container(
              color: Color(0xfff0f2f5),
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
                                      width: 0.5, color: Color(0xffd2d2d2)))),
                          child: Padding(
                            padding: EdgeInsets.only(
                                top: 30, bottom: 0, left: 10, right: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        navigatorKey.currentState
                                            ?.pushNamed("/home");
                                      },
                                      child: SizedBox(
                                          width: 45,
                                          height: 40,
                                          child: Center(
                                            child: Icon(
                                              color: Color(0xff555555),
                                              Icons.arrow_back_ios,
                                              size: 20,
                                            ),
                                          )),
                                    ),
                                    SizedBox(
                                      width: 2,
                                    ),
                                    Icon(
                                      Icons.messenger_outline_rounded,
                                      size: 23,
                                      color: Color(0xff9cc2ff),
                                    ),
                                    SizedBox(
                                      width: 5,
                                    ),
                                    Text("Messages",
                                        style: TextStyle(
                                            fontSize: 17,
                                            color: Color(0xFF565656),
                                            fontWeight: FontWeight.bold)),
                                  ],
                                )
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                            child: ListView.builder(
                                padding: EdgeInsets.only(
                                    top: 0, bottom: 10, left: 10, right: 10),
                                shrinkWrap: true,
                                // controller: _scrollController,
                                itemCount: messagesList.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == 0) {
                                    return SizedBox(
                                      width: MediaQuery.of(context).size.width,
                                      child: Padding(
                                        padding:
                                            EdgeInsets.only(top: 10, bottom: 5),
                                        child: Row(
                                          children: [
                                            GestureDetector(
                                              onTap: () {},
                                              child: ConstrainedBox(
                                                  constraints: BoxConstraints(
                                                      minHeight: 35),
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                        color:
                                                            Color(0xFFc7daff),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(7)),
                                                    child: Padding(
                                                      padding: EdgeInsets.only(
                                                          top: 5,
                                                          bottom: 5,
                                                          left: 7,
                                                          right: 7),
                                                      child: Center(
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              color: Color(
                                                                  0xff1c7def),
                                                              Icons
                                                                  .people_alt_outlined,
                                                              size: 20,
                                                            ),
                                                            SizedBox(
                                                              width: 2,
                                                            ),
                                                            Text(
                                                              "Create Group Chat",
                                                              style: TextStyle(
                                                                  fontSize: 14,
                                                                  color: Color(
                                                                      0xFF1c7def),
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold),
                                                            )
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  )),
                                            ),
                                            SizedBox(
                                              width: 5,
                                            ),
                                            GestureDetector(
                                              onTap: () {},
                                              child: ConstrainedBox(
                                                  constraints: BoxConstraints(
                                                      minHeight: 35),
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                        color:
                                                            Color(0xFFffdb99),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(7)),
                                                    child: Padding(
                                                      padding: EdgeInsets.only(
                                                          top: 5,
                                                          bottom: 5,
                                                          left: 7,
                                                          right: 7),
                                                      child: Center(
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              color: Color(
                                                                  0xffe69500),
                                                              Icons
                                                                  .dataset_outlined,
                                                              size: 20,
                                                            ),
                                                            SizedBox(
                                                              width: 2,
                                                            ),
                                                            Text(
                                                              "Create Server",
                                                              style: TextStyle(
                                                                  fontSize: 14,
                                                                  color: Color(
                                                                      0xFFe69500),
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold),
                                                            )
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  )),
                                            )
                                          ],
                                        ),
                                      ),
                                    );
                                  }

                                  // adjust loop by index minus 1 one rendering the list
                                  return SizedBox(
                                    width: MediaQuery.of(context).size.width,
                                    child: Column(
                                      children: [
                                        Text(messagesList[index - 1].content),
                                        SizedBox(
                                          height: 5,
                                        )
                                      ],
                                    ),
                                  );
                                }))
                      ]),
                ],
              ),
            ),
          ),
        ),
      );
    }, converter: (store) {
      return store.state;
    });
  }
}
