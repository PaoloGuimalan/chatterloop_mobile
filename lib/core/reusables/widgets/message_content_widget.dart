import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/models/messages_models/message_content_model.dart';
import 'package:flutter/material.dart';

class MessageContentWidget extends StatefulWidget {
  final MessageContent messageContent;
  final String previousContentUserID;
  final String currentUserID;
  const MessageContentWidget(
      {super.key,
      required this.messageContent,
      required this.previousContentUserID,
      required this.currentUserID});

  @override
  MessageContentWidgetState createState() => MessageContentWidgetState();
}

class MessageContentWidgetState extends State<MessageContentWidget> {
  late MessageContent _messageContent;
  late String _previousContentUserID;
  late String _currentUserID;
  @override
  void initState() {
    super.initState();
    _messageContent = widget.messageContent;
    _previousContentUserID = widget.previousContentUserID;
    _currentUserID = widget.currentUserID;
  }

  Widget messageTypeSwitch(String content, String messageType,
      bool isParentSenderCurrentUser, bool isCurrentUser, bool isReply) {
    if (messageType == "text") {
      return Row(
        mainAxisAlignment:
            isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          !isParentSenderCurrentUser
              ? SizedBox(
                  width: 0,
                )
              : Expanded(
                  child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    isReply
                        ? SizedBox(
                            height: 0,
                          )
                        : Text("...")
                  ],
                )),
          SizedBox(
            width: 5,
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 300),
            child: Container(
              decoration: BoxDecoration(
                  color: isCurrentUser ? Color(0xff1c7def) : Color(0xffdedede),
                  borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: EdgeInsets.all(7),
                child: Text(
                  content,
                  style: TextStyle(
                      fontSize: 14,
                      color: isCurrentUser ? Colors.white : Colors.black),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 5,
          ),
          isParentSenderCurrentUser
              ? SizedBox(
                  width: 0,
                )
              : Expanded(
                  child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    isReply
                        ? SizedBox(
                            height: 0,
                          )
                        : Text("...")
                  ],
                ))
        ],
      );
    } else if (messageType == "image") {
      return Row(
        mainAxisAlignment:
            isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          !isParentSenderCurrentUser
              ? SizedBox(
                  width: 0,
                )
              : Expanded(
                  child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    isReply
                        ? SizedBox(
                            height: 0,
                          )
                        : Text("...")
                  ],
                )),
          SizedBox(
            width: 5,
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 300),
            child: Center(
              child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: double.infinity,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                        color: Color(0xffd2d2d2),
                        // borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Color(0xffd2d2d2), width: 1)),
                    child: Padding(
                      padding: EdgeInsets.all(0),
                      child: Image.network(
                        content,
                        fit: BoxFit.cover,
                      ),
                    ),
                  )),
            ),
          ),
          SizedBox(
            width: 5,
          ),
          isParentSenderCurrentUser
              ? SizedBox(
                  width: 0,
                )
              : Expanded(
                  child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    isReply
                        ? SizedBox(
                            height: 0,
                          )
                        : Text("...")
                  ],
                ))
        ],
      );
    } else if (messageType.contains("video")) {
      return Row(
        mainAxisAlignment:
            isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          !isParentSenderCurrentUser
              ? SizedBox(
                  width: 0,
                )
              : Expanded(
                  child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    isReply
                        ? SizedBox(
                            height: 0,
                          )
                        : Text("...")
                  ],
                )),
          SizedBox(
            width: 5,
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 300),
            child: VideoPlayerScreen(
                videoUrl:
                    content.split("%%%")[0].replaceAll("###", "%23%23%23")),
          ),
          SizedBox(
            width: 5,
          ),
          isParentSenderCurrentUser
              ? SizedBox(
                  width: 0,
                )
              : Expanded(
                  child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    isReply
                        ? SizedBox(
                            height: 0,
                          )
                        : Text("...")
                  ],
                ))
        ],
      );
    } else if (messageType == "notif") {
      return Column(
        children: [
          SizedBox(
            height: 4,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 300),
                child: Container(
                  decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: EdgeInsets.all(7),
                    child: Text(
                      content,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Color(0xFF565656)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(
            height: 4,
          )
        ],
      );
    } else {
      return SizedBox(
        height: 0,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 2, bottom: 2, left: 0, right: 0),
      child: Column(
        children: [
          SizedBox(
            height: _messageContent.isReply ? 7 : 0,
          ),
          _previousContentUserID != _messageContent.sender ||
                  _previousContentUserID == "end"
              ? Column(
                  children: [
                    SizedBox(
                      height: 5,
                    ),
                    _messageContent.conversationType != "single" &&
                            _messageContent.messageType != "notif" &&
                            _currentUserID != _messageContent.sender
                        ? Row(
                            mainAxisAlignment:
                                _messageContent.sender == _currentUserID
                                    ? MainAxisAlignment.end
                                    : MainAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(
                                    left: 7, right: 7, bottom: 2),
                                child: Text(
                                  _messageContent.sender,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF565656),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                            ],
                          )
                        : SizedBox(
                            height: 0,
                          )
                  ],
                )
              : SizedBox(
                  height: 0,
                ),
          SizedBox(
            height: _messageContent.isReply ? 0 : 5,
          ),
          _messageContent.isReply
              ? Column(
                  children: [
                    SizedBox(
                      height: 0,
                    ),
                    Row(
                      mainAxisAlignment:
                          _messageContent.sender == _currentUserID
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                      children: [
                        Padding(
                          padding:
                              EdgeInsets.only(left: 7, right: 7, bottom: 7),
                          child: Text(
                            "replied to @${_messageContent.replyedmessage?[0].sender}",
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF565656),
                                fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      ],
                    ),
                    Opacity(
                      opacity: 0.6,
                      child: messageTypeSwitch(
                          _messageContent.replyedmessage?[0].content as String,
                          _messageContent.replyedmessage?[0].messageType
                              as String,
                          _messageContent.sender == _currentUserID,
                          _messageContent.replyedmessage?[0].sender ==
                              _currentUserID,
                          true),
                    )
                  ],
                )
              : SizedBox(
                  height: 0,
                ),
          messageTypeSwitch(
              _messageContent.content,
              _messageContent.messageType,
              _messageContent.sender == _currentUserID,
              _messageContent.sender == _currentUserID,
              false)
        ],
      ),
    );
  }
}
