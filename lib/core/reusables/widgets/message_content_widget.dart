import 'package:chatterloop_app/core/reusables/players/audio_player_widget.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/models/messages_models/message_content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_reactions/flutter_chat_reactions.dart';
import 'package:flutter_chat_reactions/utilities/hero_dialog_route.dart';

class MessageContentWidget extends StatefulWidget {
  final MessageContent messageContent;
  final String previousContentUserID;
  final String currentUserID;
  final void Function(bool, String) onPressed;
  const MessageContentWidget(
      {super.key,
      required this.messageContent,
      required this.previousContentUserID,
      required this.currentUserID,
      required this.onPressed});

  @override
  MessageContentWidgetState createState() => MessageContentWidgetState();
}

class MessageContentWidgetState extends State<MessageContentWidget> {
  late MessageContent _messageContent;
  late String _previousContentUserID;
  late String _currentUserID;
  late void Function(bool, String) _onPressed;

  @override
  void initState() {
    super.initState();
    _messageContent = widget.messageContent;
    _previousContentUserID = widget.previousContentUserID;
    _currentUserID = widget.currentUserID;
    _onPressed = widget.onPressed;
  }

  Widget messageTypeSwitch(
      String content,
      String messageType,
      String messageID,
      bool isParentSenderCurrentUser,
      bool isCurrentUser,
      bool isReply,
      bool isHoverPreview) {
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
                                onPressed: () {
                                  _onPressed(true, messageID);
                                },
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
            child: Column(
              crossAxisAlignment: isParentSenderCurrentUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                      color:
                          isCurrentUser ? Color(0xff1c7def) : Color(0xffdedede),
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
                _messageContent.reactions!.isNotEmpty && !isHoverPreview
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                    color: Color(0xffd2d2d2), width: 1),
                                borderRadius: BorderRadius.circular(10)),
                            child: Padding(
                              padding: EdgeInsets.only(
                                  top: 1, bottom: 1, left: 2, right: 2),
                              child: Row(
                                children: [
                                  ..._messageContent.reactions!
                                      .map((reaction) => Text(reaction.emoji))
                                ],
                              ),
                            ),
                          )
                        ],
                      )
                    : SizedBox(
                        height: 0,
                      )
              ],
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
                                onPressed: () {
                                  _onPressed(true, messageID);
                                },
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
                                onPressed: () {
                                  _onPressed(true, messageID);
                                },
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
            child: Column(
              crossAxisAlignment: isParentSenderCurrentUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Center(
                  child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: double.infinity,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                            color: Color(0xffd2d2d2),
                            // borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: Color(0xffd2d2d2), width: 1)),
                        child: Padding(
                          padding: EdgeInsets.all(0),
                          child: Image.network(
                            content,
                            fit: BoxFit.cover,
                          ),
                        ),
                      )),
                ),
                _messageContent.reactions!.isNotEmpty && !isHoverPreview
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                    color: Color(0xffd2d2d2), width: 1),
                                borderRadius: BorderRadius.circular(10)),
                            child: Padding(
                              padding: EdgeInsets.only(
                                  top: 1, bottom: 1, left: 2, right: 2),
                              child: Row(
                                children: [
                                  ..._messageContent.reactions!
                                      .map((reaction) => Text(reaction.emoji))
                                ],
                              ),
                            ),
                          )
                        ],
                      )
                    : SizedBox(
                        height: 0,
                      )
              ],
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
                                onPressed: () {
                                  _onPressed(true, messageID);
                                },
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
                                onPressed: () {
                                  _onPressed(true, messageID);
                                },
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
            child: Column(
              crossAxisAlignment: isParentSenderCurrentUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  color: Colors.black,
                  child: VideoPlayerScreen(
                      videoUrl: content
                          .split("%%%")[0]
                          .replaceAll("###", "%23%23%23")),
                ),
                _messageContent.reactions!.isNotEmpty && !isHoverPreview
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                    color: Color(0xffd2d2d2), width: 1),
                                borderRadius: BorderRadius.circular(10)),
                            child: Padding(
                              padding: EdgeInsets.only(
                                  top: 1, bottom: 1, left: 2, right: 2),
                              child: Row(
                                children: [
                                  ..._messageContent.reactions!
                                      .map((reaction) => Text(reaction.emoji))
                                ],
                              ),
                            ),
                          )
                        ],
                      )
                    : SizedBox(
                        height: 0,
                      )
              ],
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
                                onPressed: () {
                                  _onPressed(true, messageID);
                                },
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
    } else if (messageType.contains("audio")) {
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
                                onPressed: () {
                                  _onPressed(true, messageID);
                                },
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
            child: Column(
              crossAxisAlignment: isParentSenderCurrentUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  color: Colors.transparent,
                  child: AudioPlayerWidget(
                      audioUrl: content
                          .split("%%%")[0]
                          .replaceAll("###", "%23%23%23")),
                ),
                _messageContent.reactions!.isNotEmpty && !isHoverPreview
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                    color: Color(0xffd2d2d2), width: 1),
                                borderRadius: BorderRadius.circular(10)),
                            child: Padding(
                              padding: EdgeInsets.only(
                                  top: 1, bottom: 1, left: 2, right: 2),
                              child: Row(
                                children: [
                                  ..._messageContent.reactions!
                                      .map((reaction) => Text(reaction.emoji))
                                ],
                              ),
                            ),
                          )
                        ],
                      )
                    : SizedBox(
                        height: 0,
                      )
              ],
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
                                onPressed: () {
                                  _onPressed(true, messageID);
                                },
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
                                onPressed: () {
                                  _onPressed(true, messageID);
                                },
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
            child: Column(
              crossAxisAlignment: isParentSenderCurrentUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xffe4e4e4),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: EdgeInsets.only(
                            top: 0, bottom: 0, left: 0, right: 0)),
                    onPressed: () {},
                    child: Container(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10)),
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
                              style:
                                  TextStyle(fontSize: 14, color: Colors.black),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ))
                          ],
                        ),
                      ),
                    )),
                _messageContent.reactions!.isNotEmpty && !isHoverPreview
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                    color: Color(0xffd2d2d2), width: 1),
                                borderRadius: BorderRadius.circular(10)),
                            child: Padding(
                              padding: EdgeInsets.only(
                                  top: 1, bottom: 1, left: 2, right: 2),
                              child: Row(
                                children: [
                                  ..._messageContent.reactions!
                                      .map((reaction) => Text(reaction.emoji))
                                ],
                              ),
                            ),
                          )
                        ],
                      )
                    : SizedBox(
                        height: 0,
                      )
              ],
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
                                onPressed: () {
                                  _onPressed(true, messageID);
                                },
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

  Widget messageDeletedItem(String messageType, bool isParentSenderCurrentUser,
      bool isCurrentUser, bool isReply) {
    return Row(
      mainAxisAlignment:
          isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        !isParentSenderCurrentUser
            ? SizedBox(
                width: 0,
              )
            : Expanded(
                child: SizedBox(
                height: 0,
              )),
        SizedBox(
          width: 5,
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 270),
          child: Container(
            decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border.all(color: Color(0xFFdedede), width: 1),
                borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: EdgeInsets.only(top: 10, bottom: 10, left: 7, right: 7),
              child: Text(
                "Message deleted",
                style: TextStyle(fontSize: 14, color: Color(0xFFdedede)),
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
                child: SizedBox(
                height: 0,
              ))
      ],
    );
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
                      child: _messageContent.replyedmessage?[0].isDeleted
                              as bool
                          ? messageDeletedItem(
                              _messageContent.replyedmessage?[0].messageType
                                  as String,
                              _messageContent.sender == _currentUserID,
                              _messageContent.replyedmessage?[0].sender ==
                                  _currentUserID,
                              true)
                          : messageTypeSwitch(
                              _messageContent.replyedmessage?[0].content
                                  as String,
                              _messageContent.replyedmessage?[0].messageType
                                  as String,
                              _messageContent.replyedmessage?[0].messageID
                                  as String,
                              _messageContent.sender == _currentUserID,
                              _messageContent.replyedmessage?[0].sender ==
                                  _currentUserID,
                              true,
                              false),
                    )
                  ],
                )
              : SizedBox(
                  height: 0,
                ),
          _messageContent.isDeleted as bool
              ? messageDeletedItem(
                  _messageContent.messageType,
                  _messageContent.sender == _currentUserID,
                  _messageContent.sender == _currentUserID,
                  false)
              : GestureDetector(
                  onLongPress: () async {
                    Navigator.of(context).push(
                      HeroDialogRoute(
                        builder: (context) {
                          return ReactionsDialogWidget(
                            id: _messageContent
                                .messageID, // unique id for message
                            messageWidget: _messageContent.messageType
                                    .contains("audio")
                                ? ConstrainedBox(
                                    constraints: BoxConstraints(
                                        maxWidth: 270, minHeight: 70),
                                    child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Color(0xffe4e4e4),
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10)),
                                            padding: EdgeInsets.only(
                                                top: 0,
                                                bottom: 0,
                                                left: 0,
                                                right: 0)),
                                        onPressed: () {},
                                        child: Container(
                                          decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(10)),
                                          child: Padding(
                                            padding: EdgeInsets.only(
                                                top: 10,
                                                bottom: 10,
                                                left: 10,
                                                right: 10),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.max,
                                              children: [
                                                Icon(
                                                  Icons.play_arrow,
                                                  color: Colors.black,
                                                  size: 22,
                                                ),
                                                SizedBox(
                                                  width: 10,
                                                ),
                                                Expanded(
                                                    child: Text(
                                                  _messageContent.content
                                                      .split("%%%")[1],
                                                  style: TextStyle(
                                                      fontSize: 14,
                                                      color: Colors.black),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ))
                                              ],
                                            ),
                                          ),
                                        )),
                                  )
                                : messageTypeSwitch(
                                    _messageContent.content,
                                    _messageContent.messageType,
                                    _messageContent.messageID,
                                    _messageContent.sender == _currentUserID,
                                    _messageContent.sender == _currentUserID,
                                    false,
                                    true), // message widget
                            onReactionTap: (reaction) {
                              print('reaction: $reaction');

                              if (reaction == '➕') {
                                // show emoji picker container
                              } else {
                                // add reaction to message
                              }
                            },
                            onContextMenuTap: (menuItem) {
                              if (menuItem.label == "Reply") {
                                _onPressed(true, _messageContent.messageID);
                              }
                              // handle context menu item
                            },
                          );
                        },
                      ),
                    );
                  },
                  child: Hero(
                      tag: _messageContent.messageID,
                      child: messageTypeSwitch(
                          _messageContent.content,
                          _messageContent.messageType,
                          _messageContent.messageID,
                          _messageContent.sender == _currentUserID,
                          _messageContent.sender == _currentUserID,
                          false,
                          false)),
                )
        ],
      ),
    );
  }
}
