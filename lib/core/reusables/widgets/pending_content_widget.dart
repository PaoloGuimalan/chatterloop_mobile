import 'package:chatterloop_app/core/design/tokens.dart';
import 'dart:io';

import 'package:chatterloop_app/core/reusables/players/voice_message_player.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/media/media_uploader.dart';
import 'package:flutter/material.dart';

class PendingContentWidget extends StatefulWidget {
  final String messageID;
  final String content;
  final String contentType;

  /// "replied to X" and the quote, over a reply that is still sending - the
  /// conversation builds it, since the quoted message lives there.
  final Widget? replyHeader;
  const PendingContentWidget(
      {super.key,
      required this.messageID,
      required this.content,
      required this.contentType,
      this.replyHeader});

  @override
  PendingContentWidgetState createState() => PendingContentWidgetState();
}

class PendingContentWidgetState extends State<PendingContentWidget> {
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
                  color:
                      isCurrentUser ? CLAccent.of(context) : Color(0xffdedede),
                  borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding:
                    EdgeInsets.only(top: 10, bottom: 10, left: 7, right: 7),
                child: Text(
                  content,
                  style: TextStyle(
                      fontSize: CLType.title,
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
                // A pending video's content is the local file being
                // uploaded. While it sends it is a still with a play badge,
                // as it was in the picked-files strip; the player comes with
                // the sent message.
                child: content.startsWith('http')
                    ? VideoPlayerScreen(videoUrl: content)
                    : _PendingVideo(path: content),
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
                      style: TextStyle(
                          fontSize: CLType.caption, color: Color(0xFF565656)),
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
                          // The picked file's own name - it's still local.
                          fileNameOf(content),
                          style: TextStyle(
                              fontSize: CLType.title, color: Colors.black),
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
          if (widget.replyHeader != null) widget.replyHeader!,
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
                    // The upload's progress while the bytes go up
                    // (MediaUploader, keyed by this pending id), then
                    // "...sending" while the server makes the message.
                    ValueListenableBuilder<double?>(
                      valueListenable: UploadProgress.of(widget.messageID),
                      builder: (context, progress, _) => Text(
                        progress == null
                            ? "...sending"
                            : "Uploading ${(progress * 100).round()}%",
                        style: TextStyle(
                          fontSize: CLType.caption,
                          color: Color(0xFF565656),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
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

/// A video still being sent: its first frame with a play badge, at the
/// video's shape - the same still it showed in the picked-files strip. No
/// player (and no decoder) until the message is sent.
class _PendingVideo extends StatefulWidget {
  final String path;

  const _PendingVideo({required this.path});

  @override
  State<_PendingVideo> createState() => _PendingVideoState();
}

class _PendingVideoState extends State<_PendingVideo> {
  late double? _ratio = VideoFirstFrame.knownAspectRatio(widget.path);

  @override
  void initState() {
    super.initState();
    if (_ratio == null) {
      VideoFirstFrame.aspectRatioOf(widget.path).then((ratio) {
        if (mounted && ratio != null) setState(() => _ratio = ratio);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // A tall phone video is kept to 4:5, like a post's, filled.
    final ratio = (_ratio ?? 16 / 9).clamp(0.8, 1.91);
    return AspectRatio(
      aspectRatio: ratio,
      child: VideoFirstFrame(source: widget.path, isLocalFile: true),
    );
  }
}
