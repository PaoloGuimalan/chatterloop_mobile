import 'package:chatterloop_app/models/messages_models/messages_list_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:flutter/material.dart';

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

  Widget messageItemIdentified(String conversationTypeProp) {
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
                              : 'https://chatterloop.netlify.app/assets/default-e4788211.png',
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
                      "${_isCurrentUserSender ? "you: " : ""}${_message.content}",
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
                ]))
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
                              : 'https://chatterloop.netlify.app/assets/group-chat-icon-d6f42fe5.jpg',
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
                      "${_isCurrentUserSender ? "you: " : ""}${_message.content}",
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
                ]))
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
                              : 'https://chatterloop.netlify.app/assets/servericon-e125462b.png',
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
                      "${_isCurrentUserSender ? "you: " : ""}${_message.content}",
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
                ]))
          ],
        );
      default:
        return Text("No Type");
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width,
      child: Column(
        children: [
          Container(
            width: MediaQuery.of(context).size.width,
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Color(0xffd2d2d2), width: 1),
                borderRadius: BorderRadius.circular(7)),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 400, minHeight: 85),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 6, bottom: 6, right: 10),
                  child: messageItemIdentified(_message.conversationType),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 5,
          )
        ],
      ),
    );
  }
}
