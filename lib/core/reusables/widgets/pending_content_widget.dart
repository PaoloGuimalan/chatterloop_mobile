import 'dart:io';

import 'package:chatterloop_app/core/reusables/players/voice_message_player.dart';
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
  /// Matches webapp's ContentHandler.tsx: "url%%%filename" is only used
  /// for legacy Google Cloud Storage uploads - every other upload (e.g.
  /// the DigitalOcean Spaces URLs this backend actually uses) is a plain
  /// URL with no delimiter, whose filename is just its last "/"-segment.
  String _fileNamePart(String content) {
    if (content.contains("storage.googleapis.com")) {
      final parts = content.split("%%%");
      return parts.length > 1 ? parts[1] : "File";
    }
    final segments = content.split("/");
    return segments.isNotEmpty && segments.last.isNotEmpty
        ? segments.last
        : "File";
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
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Color(0xffd2d2d2), width: 1)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: EdgeInsets.all(0),
                        // A pending image's content is always a local path
                        // (the file being uploaded), never a URL yet -
                        // Image.network can't read that, so this checks
                        // which one it's looking at rather than assuming.
                        child: content.startsWith('http')
                            ? Image.network(content, fit: BoxFit.cover)
                            : Image.file(File(content), fit: BoxFit.cover),
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                color: Colors.black,
                // A pending video's content is always a local path (the
                // file being uploaded) - no %%%/### legacy-URL handling
                // applies to it, unlike a confirmed message's content.
                child: content.startsWith('http')
                    ? VideoPlayerScreen(
                        videoUrl: content
                            .split("%%%")[0]
                            .replaceAll("###", "%23%23%23"))
                    : VideoPlayerScreen(videoUrl: content, isLocalFile: true),
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
            // A pending voice message's content is always a local recording
            // path, never a URL yet - matches the sent-message
            // VoiceMessagePlayer used in message_content_widget.dart so a
            // recording doesn't visually swap widgets the moment it's
            // actually uploaded.
            child: VoiceMessagePlayer(
              src: content,
              isSender: isCurrentUser,
              isLocalFile: true,
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
                          _fileNamePart(content),
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
                    widget.content,
                    widget.contentType,
                    widget.messageID,
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
