import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:flutter/material.dart';

class PendingContentWidget extends StatefulWidget {
  final String messageID;
  final String content;
  final String contentType;
  const PendingContentWidget(
      {super.key,
      required this.messageID,
      required this.content,
      required this.contentType});

  @override
  PendingContentWidgetState createState() => PendingContentWidgetState();
}

class PendingContentWidgetState extends State<PendingContentWidget> {
  late String _messageID;
  late String _content;
  late String _contentType;
  @override
  void initState() {
    super.initState();
    _messageID = widget.messageID;
    _content = widget.content;
    _contentType = widget.contentType;
  }

  Widget messageTypeSwitch(String content, String messageType, String messageID,
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
                        : ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: 40, maxHeight: 40),
                            child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    elevation: 0,
                                    padding: EdgeInsets.only(
                                        top: 0, bottom: 0, left: 0, right: 0)),
                                onPressed: () {},
                                child: Center(
                                  child: Icon(
                                    Icons.delete,
                                    color: Color(0xFF565656),
                                    size: 18,
                                  ),
                                )),
                          ),
                    isReply
                        ? SizedBox(
                            height: 0,
                          )
                        : ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: 40, maxHeight: 40),
                            child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    elevation: 0,
                                    padding: EdgeInsets.only(
                                        top: 0, bottom: 0, left: 0, right: 0)),
                                onPressed: () {},
                                child: Center(
                                  child: Icon(
                                    Icons.reply,
                                    color: Color(0xFF565656),
                                    size: 20,
                                  ),
                                )),
                          )
                  ],
                )),
          SizedBox(
            width: 5,
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 270),
            child: Container(
              decoration: BoxDecoration(
                  color: isCurrentUser ? Color(0xff1c7def) : Color(0xffdedede),
                  borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding:
                    EdgeInsets.only(top: 10, bottom: 10, left: 7, right: 7),
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
                        : ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: 40, maxHeight: 40),
                            child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    elevation: 0,
                                    padding: EdgeInsets.only(
                                        top: 0, bottom: 0, left: 0, right: 0)),
                                onPressed: () {},
                                child: Center(
                                  child: Icon(
                                    Icons.reply,
                                    color: Color(0xFF565656),
                                    size: 20,
                                  ),
                                )),
                          )
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
                        : ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: 40, maxHeight: 40),
                            child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    elevation: 0,
                                    padding: EdgeInsets.only(
                                        top: 0, bottom: 0, left: 0, right: 0)),
                                onPressed: () {},
                                child: Center(
                                  child: Icon(
                                    Icons.delete,
                                    color: Color(0xFF565656),
                                    size: 18,
                                  ),
                                )),
                          ),
                    isReply
                        ? SizedBox(
                            height: 0,
                          )
                        : ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: 40, maxHeight: 40),
                            child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    elevation: 0,
                                    padding: EdgeInsets.only(
                                        top: 0, bottom: 0, left: 0, right: 0)),
                                onPressed: () {},
                                child: Center(
                                  child: Icon(
                                    Icons.reply,
                                    color: Color(0xFF565656),
                                    size: 20,
                                  ),
                                )),
                          )
                  ],
                )),
          SizedBox(
            width: 5,
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 270),
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
                        : ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: 40, maxHeight: 40),
                            child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    elevation: 0,
                                    padding: EdgeInsets.only(
                                        top: 0, bottom: 0, left: 0, right: 0)),
                                onPressed: () {},
                                child: Center(
                                  child: Icon(
                                    Icons.reply,
                                    color: Color(0xFF565656),
                                    size: 20,
                                  ),
                                )),
                          )
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
                        : ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: 40, maxHeight: 40),
                            child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    elevation: 0,
                                    padding: EdgeInsets.only(
                                        top: 0, bottom: 0, left: 0, right: 0)),
                                onPressed: () {},
                                child: Center(
                                  child: Icon(
                                    Icons.delete,
                                    color: Color(0xFF565656),
                                    size: 18,
                                  ),
                                )),
                          ),
                    isReply
                        ? SizedBox(
                            height: 0,
                          )
                        : ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: 40, maxHeight: 40),
                            child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    elevation: 0,
                                    padding: EdgeInsets.only(
                                        top: 0, bottom: 0, left: 0, right: 0)),
                                onPressed: () {},
                                child: Center(
                                  child: Icon(
                                    Icons.reply,
                                    color: Color(0xFF565656),
                                    size: 20,
                                  ),
                                )),
                          )
                  ],
                )),
          SizedBox(
            width: 5,
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 270),
            child: Container(
              color: Colors.black,
              child: VideoPlayerScreen(
                  videoUrl:
                      content.split("%%%")[0].replaceAll("###", "%23%23%23")),
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
                        : ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: 40, maxHeight: 40),
                            child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    elevation: 0,
                                    padding: EdgeInsets.only(
                                        top: 0, bottom: 0, left: 0, right: 0)),
                                onPressed: () {},
                                child: Center(
                                  child: Icon(
                                    Icons.reply,
                                    color: Color(0xFF565656),
                                    size: 20,
                                  ),
                                )),
                          )
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
                        : ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: 40, maxHeight: 40),
                            child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    elevation: 0,
                                    padding: EdgeInsets.only(
                                        top: 0, bottom: 0, left: 0, right: 0)),
                                onPressed: () {},
                                child: Center(
                                  child: Icon(
                                    Icons.delete,
                                    color: Color(0xFF565656),
                                    size: 18,
                                  ),
                                )),
                          ),
                    isReply
                        ? SizedBox(
                            height: 0,
                          )
                        : ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: 40, maxHeight: 40),
                            child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    elevation: 0,
                                    padding: EdgeInsets.only(
                                        top: 0, bottom: 0, left: 0, right: 0)),
                                onPressed: () {},
                                child: Center(
                                  child: Icon(
                                    Icons.reply,
                                    color: Color(0xFF565656),
                                    size: 20,
                                  ),
                                )),
                          )
                  ],
                )),
          SizedBox(
            width: 5,
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 270, minHeight: 70),
            child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xffe4e4e4),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding:
                        EdgeInsets.only(top: 0, bottom: 0, left: 0, right: 0)),
                onPressed: () {},
                child: Container(
                  decoration:
                      BoxDecoration(borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: EdgeInsets.only(
                        top: 10, bottom: 10, left: 10, right: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Icon(
                          Icons.file_copy_outlined,
                          color: Colors.black,
                          size: 35,
                        ),
                        SizedBox(
                          width: 10,
                        ),
                        Expanded(
                            child: Text(
                          content.split("%%%")[1],
                          style: TextStyle(fontSize: 14, color: Colors.black),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ))
                      ],
                    ),
                  ),
                )),
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
                        : ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: 40, maxHeight: 40),
                            child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    elevation: 0,
                                    padding: EdgeInsets.only(
                                        top: 0, bottom: 0, left: 0, right: 0)),
                                onPressed: () {},
                                child: Center(
                                  child: Icon(
                                    Icons.reply,
                                    color: Color(0xFF565656),
                                    size: 20,
                                  ),
                                )),
                          )
                  ],
                ))
        ],
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
            height: 0,
          ),
          SizedBox(
            height: 5,
          ),
          Column(
            children: [
              Opacity(
                opacity: 0.6,
                child: messageTypeSwitch(
                    _content,
                    _contentType,
                    _messageID,
                    true,
                    true,
                    true), // pretend isReply to disable message buttons
              ),
              Padding(
                padding: EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      "...sending",
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF565656),
                      ),
                      overflow: TextOverflow.ellipsis,
                    )
                  ],
                ),
              )
            ],
          )
        ],
      ),
    );
  }
}
