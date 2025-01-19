import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/routes/app_routes.dart';
import 'package:chatterloop_app/core/utils/content_validator.dart';
import 'package:chatterloop_app/models/messages_models/messages_list_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:chatterloop_app/models/view_prop_models/conversation_view_props.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class MessageItemView extends StatefulWidget {
  final MessageItem message;
  final String userID;

  const MessageItemView(
      {super.key, required this.message, required this.userID});

  @override
  MessageItemViewState createState() => MessageItemViewState();
}

class MessageItemViewState extends State<MessageItemView> {
  late MessageItem _message;
  late String _userID;
  late bool _isCurrentUserSender;

  @override
  void initState() {
    super.initState();
    _message = widget.message;
    _userID = widget.userID;
    _isCurrentUserSender =
        widget.message.sender == widget.userID ? true : false;
  }

  Widget messageItemIdentified(
      String conversationTypeProp, bool hasTypingActivityProp) {
    switch (conversationTypeProp) {
      case "single":
        UsersContactPreview conversationUserLead =
            _userID == _message.users[0].userID
                ? _message.users[1]
                : _message.users[0];
        return Row(
          children: [
            Padding(
              padding: EdgeInsets.only(left: 15, right: 15),
              child: Center(
                child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: 50, maxWidth: 50),
                    child: Container(
                      decoration: BoxDecoration(
                          color: Color(0xffd2d2d2),
                          border:
                              Border.all(color: Color(0xffd2d2d2), width: 1),
                          borderRadius: BorderRadius.circular(50)),
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: Image.network(
                          conversationUserLead.profile != "" &&
                                  conversationUserLead.profile != "none"
                              ? conversationUserLead.profile
                              : ContentValidator().singleChatPreviewImage,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )),
              ),
            ),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                  SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: Text(
                      "${conversationUserLead.fullname.firstName}${conversationUserLead.fullname.middleName == "N/A" ? "" : " ${conversationUserLead.fullname.middleName}"} ${conversationUserLead.fullname.lastName}",
                      style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF565656),
                          fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: Text(
                      hasTypingActivityProp
                          ? "is typing..."
                          : "${_isCurrentUserSender && _message.messageType != "notif" ? "you: " : ""}${_message.isDeleted != null && _message.isDeleted as bool ? "Message deleted" : _message.messageType == "text" || _message.messageType == "notif" ? _message.content : _message.messageType == "image" ? "Sent a photo" : _message.messageType.contains("video") ? "Sent a video" : _message.messageType.contains("audio") ? "Sent an audio" : "Sent a file"}",
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF565656),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: Text(
                      "${_message.messageDate.date} . ${_message.messageDate.time}",
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF565656),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                ])),
            _message.unread > 0
                ? SizedBox(
                    width: 30,
                    height: 60,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10)),
                          width: 30,
                          height: 17,
                          child: Center(
                            child: Text(
                              _message.unread > 99
                                  ? "+99"
                                  : _message.unread.toString(),
                              style:
                                  TextStyle(fontSize: 12, color: Colors.white),
                            ),
                          ),
                        )
                      ],
                    ),
                  )
                : SizedBox(
                    width: 6,
                  )
          ],
        );
      case "group":
        return Row(
          children: [
            Padding(
              padding: EdgeInsets.only(left: 15, right: 15),
              child: Center(
                child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: 50, maxWidth: 50),
                    child: Container(
                      decoration: BoxDecoration(
                          color: Color(0xffd2d2d2),
                          border:
                              Border.all(color: Color(0xffd2d2d2), width: 1),
                          borderRadius: BorderRadius.circular(50)),
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: Image.network(
                          _message.groupdetails?.profile != "" &&
                                  _message.groupdetails?.profile != "none" &&
                                  _message.groupdetails?.profile != null
                              ? _message.groupdetails?.profile as String
                              : ContentValidator().groupChatPreviewImage,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )),
              ),
            ),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                  SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Text(
                              _message.groupdetails?.groupName as String,
                              style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF1c7def),
                                  fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(
                              width: 5,
                            ),
                            Icon(
                              color: Color(0xFF1c7def),
                              Icons.people_alt_outlined,
                              size: 20,
                            )
                          ],
                        )
                      ],
                    ),
                  ),
                  SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: Text(
                      hasTypingActivityProp
                          ? "someone is typing..."
                          : "${_isCurrentUserSender && _message.messageType != "notif" ? "you: " : ""}${_message.isDeleted != null && _message.isDeleted as bool ? "Message deleted" : _message.messageType == "text" || _message.messageType == "notif" ? _message.content : _message.messageType == "image" ? "Sent a photo" : _message.messageType.contains("video") ? "Sent a video" : _message.messageType.contains("audio") ? "Sent an audio" : "Sent a file"}",
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF565656),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: Text(
                      "${_message.messageDate.date} . ${_message.messageDate.time}",
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF565656),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                ])),
            _message.unread > 0
                ? SizedBox(
                    width: 30,
                    height: 60,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10)),
                          width: 30,
                          height: 17,
                          child: Center(
                            child: Text(
                              _message.unread > 99
                                  ? "+99"
                                  : _message.unread.toString(),
                              style:
                                  TextStyle(fontSize: 12, color: Colors.white),
                            ),
                          ),
                        )
                      ],
                    ),
                  )
                : SizedBox(
                    width: 6,
                  )
          ],
        );
      case "server":
        return Row(
          children: [
            Padding(
              padding: EdgeInsets.only(left: 15, right: 15),
              child: Center(
                child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: 50, maxWidth: 50),
                    child: Container(
                      decoration: BoxDecoration(
                          color: Color(0xffd2d2d2),
                          border:
                              Border.all(color: Color(0xffd2d2d2), width: 1),
                          borderRadius: BorderRadius.circular(50)),
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: Image.network(
                          _message.serverdetails?.profile != "" &&
                                  _message.serverdetails?.profile != "none" &&
                                  _message.serverdetails?.profile != null
                              ? _message.serverdetails?.profile as String
                              : ContentValidator().serverMainPreviewImage,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )),
              ),
            ),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                  SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Text(
                              _message.serverdetails?.serverName as String,
                              style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xffe69500),
                                  fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(
                              width: 5,
                            ),
                            Icon(
                              color: Color(0xffe69500),
                              Icons.dataset_outlined,
                              size: 22,
                            )
                          ],
                        ),
                        Text(
                          _message.groupdetails?.groupName as String,
                          style: TextStyle(
                              fontSize: 12,
                              color: Color(0xffe69500),
                              fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      ],
                    ),
                  ),
                  SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: Text(
                      hasTypingActivityProp
                          ? "someone is typing..."
                          : "${_isCurrentUserSender && _message.messageType != "notif" ? "you: " : ""}${_message.isDeleted != null && _message.isDeleted as bool ? "Message deleted" : _message.messageType == "text" || _message.messageType == "notif" ? _message.content : _message.messageType == "image" ? "Sent a photo" : _message.messageType.contains("video") ? "Sent a video" : _message.messageType.contains("audio") ? "Sent an audio" : "Sent a file"}",
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF565656),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: Text(
                      "${_message.messageDate.date} . ${_message.messageDate.time}",
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF565656),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                ])),
            _message.unread > 0
                ? SizedBox(
                    width: 30,
                    height: 60,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10)),
                          width: 30,
                          height: 20,
                          child: Center(
                            child: Text(
                              _message.unread > 99
                                  ? "+99"
                                  : _message.unread.toString(),
                              style:
                                  TextStyle(fontSize: 12, color: Colors.white),
                            ),
                          ),
                        )
                      ],
                    ),
                  )
                : SizedBox(
                    width: 6,
                  )
          ],
        );
      default:
        return Text("No Type");
    }
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AppState>(builder: (context, state) {
      bool hasConversationTypingActivity = state.isTypingList
              .where(
                  (typing) => typing.conversationID == _message.conversationID)
              .toList()
              .isNotEmpty
          ? true
          : false;
      return SizedBox(
        width: MediaQuery.of(context).size.width,
        child: Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 600, minHeight: 85),
              child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding:
                          EdgeInsets.only(top: 5, bottom: 5, left: 0, right: 0),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7))),
                  onPressed: () {
                    if (_message.conversationType == "single") {
                      UsersContactPreview conversationUserLead =
                          _userID == _message.users[0].userID
                              ? _message.users[1]
                              : _message.users[0];
                      String previewName =
                          "${conversationUserLead.fullname.firstName}${conversationUserLead.fullname.middleName == "N/A" ? "" : " ${conversationUserLead.fullname.middleName}"} ${conversationUserLead.fullname.lastName}";

                      privateNavigatorKey.currentState?.pushNamed(
                          "/conversation",
                          arguments: ConversationViewProps(
                              _message.conversationID,
                              _message.conversationType,
                              ConversationPreview(
                                  ContentValidator()
                                      .validateConversationProfile(
                                          conversationUserLead.profile,
                                          _message.conversationType),
                                  previewName)));
                    } else if (_message.conversationType == "group") {
                      privateNavigatorKey.currentState?.pushNamed(
                          "/conversation",
                          arguments: ConversationViewProps(
                              _message.conversationID,
                              _message.conversationType,
                              ConversationPreview(
                                  ContentValidator()
                                      .validateConversationProfile(
                                          _message.groupdetails?.profile,
                                          _message.conversationType),
                                  _message.groupdetails?.groupName ?? "")));
                    }
                  },
                  child: Container(
                    key: ValueKey(hasConversationTypingActivity),
                    width: MediaQuery.of(context).size.width,
                    decoration: BoxDecoration(
                        color: Colors.transparent,
                        // color: Colors.white,
                        // border: Border.all(color: Color(0xffd2d2d2), width: 1),
                        borderRadius: BorderRadius.circular(7)),
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.only(top: 6, bottom: 6, right: 4),
                        child: messageItemIdentified(_message.conversationType,
                            hasConversationTypingActivity),
                      ),
                    ),
                  )),
            ),
            SizedBox(
              height: 5,
            )
          ],
        ),
      );
    }, converter: (store) {
      return store.state;
    });
  }
}
