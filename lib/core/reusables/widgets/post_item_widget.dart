import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/models/post_models/user_post_model.dart';
import 'package:flutter/material.dart';

class PostItemWidget extends StatefulWidget {
  final UserPost post;

  const PostItemWidget({super.key, required this.post});

  @override
  PostItemWidgetState createState() => PostItemWidgetState();
}

class PostItemWidgetState extends State<PostItemWidget> {
  late UserPost _post;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
  }

  ButtonStyle _buttonStyle(bool fromHeader) {
    return ElevatedButton.styleFrom(
        backgroundColor: fromHeader ? Colors.white : Colors.white,
        fixedSize: Size(50, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(60), // Rounded corners if needed
        ),
        elevation: 0,
        padding: EdgeInsets.zero,
        iconColor: Color(0xFF565656),
        overlayColor: Color(0xFF565656));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                    top: BorderSide(width: 0.5, color: Color(0xffd2d2d2)),
                    bottom: BorderSide(width: 0.5, color: Color(0xffd2d2d2)))),
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 5),
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                          top: 15, bottom: 5, right: 5, left: 5),
                      child: Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(left: 15, right: 15),
                            child: Center(
                              child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                      maxHeight: 50, maxWidth: 50),
                                  child: Container(
                                    decoration: BoxDecoration(
                                        color: Color(0xffd2d2d2),
                                        border: Border.all(
                                            color: Color(0xffd2d2d2), width: 1),
                                        borderRadius:
                                            BorderRadius.circular(50)),
                                    child: Padding(
                                      padding: EdgeInsets.all(10),
                                      child: Image.network(
                                        'https://chatterloop.netlify.app/assets/default-e4788211.png',
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  )),
                            ),
                          ),
                          Expanded(
                              child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.start,
                            children: [
                              Text(
                                  "${_post.postOwner.fullName.firstName}${_post.postOwner.fullName.middleName == "N/A" ? "" : " ${_post.postOwner.fullName.middleName}"} ${_post.postOwner.fullName.lastName}",
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF565656),
                                      fontWeight: FontWeight.bold)),
                              _post.tagging.isTagged
                                  ? Text(" is with",
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF565656),
                                      ))
                                  : SizedBox(
                                      height: 0,
                                    ),
                              ..._post.taggedUsers.map((tagged) => Text(
                                  " ${tagged.fullName.firstName}${tagged.fullName.middleName == "N/A" ? "" : " ${tagged.fullName.middleName}"} ${tagged.fullName.lastName}",
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF565656),
                                      fontWeight: FontWeight.bold)))
                            ],
                          )),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        _post.content.data == ""
                            ? SizedBox(
                                height: 5,
                              )
                            : Padding(
                                padding: EdgeInsets.only(right: 12, left: 12),
                                child: Center(
                                  child: Text(_post.content.data),
                                ),
                              ),
                        SizedBox(
                          height: _post.content.data == "" ? 0 : 10,
                        ),
                        Container(
                          child: _post.type.contentType == "media"
                              ? Column(
                                  children: [
                                    ..._post.content.references.map(
                                        (reference) => reference
                                                    .referenceMediaType ==
                                                "image"
                                            ? Center(
                                                child: ConstrainedBox(
                                                    constraints: BoxConstraints(
                                                      maxWidth: double.infinity,
                                                    ),
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        color:
                                                            Color(0xffd2d2d2),
                                                      ),
                                                      child: Padding(
                                                        padding:
                                                            EdgeInsets.all(0),
                                                        child: Image.network(
                                                          reference.reference,
                                                          fit: BoxFit.cover,
                                                        ),
                                                      ),
                                                    )),
                                              )
                                            : reference.referenceMediaType ==
                                                    "video"
                                                ? Container(
                                                    color: Colors.black,
                                                    child: VideoPlayerScreen(
                                                        videoUrl: reference
                                                            .reference),
                                                  )
                                                : SizedBox(
                                                    height: 0,
                                                  ))
                                  ],
                                )
                              : SizedBox(
                                  height: 0,
                                ),
                        ),
                        SizedBox(
                          height: 5,
                        ),
                        Container(
                          decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border(
                                  top: BorderSide(
                                      width: 0.5, color: Color(0xffd2d2d2)))),
                          height: 50,
                          padding: EdgeInsets.all(5),
                          width: MediaQuery.of(context).size.width,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              ElevatedButton(
                                onPressed: () {},
                                style: _buttonStyle(false),
                                child: Center(
                                  child: Icon(
                                    Icons.thumb_up_alt_outlined,
                                    size: 23,
                                  ),
                                ),
                              ),
                              ElevatedButton(
                                  onPressed: () {},
                                  style: _buttonStyle(false),
                                  child: Icon(
                                    Icons.insert_comment_outlined,
                                    size: 23,
                                  )),
                              ElevatedButton(
                                  onPressed: () {},
                                  style: _buttonStyle(false),
                                  child: Icon(
                                    Icons.switch_access_shortcut_outlined,
                                    size: 23,
                                  )),
                            ],
                          ),
                        )
                      ],
                    )
                  ],
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
