import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ContactsItemWidget extends StatefulWidget {
  final UsersContactPreview contact;
  const ContactsItemWidget({super.key, required this.contact});

  @override
  ContactsItemWidgetState createState() => ContactsItemWidgetState();
}

class ContactsItemWidgetState extends State<ContactsItemWidget> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width,
      child: Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 400, minHeight: 60),
            child: Center(
              child: Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 15, right: 15),
                    child: Center(
                      child: ConstrainedBox(
                          constraints:
                              BoxConstraints(maxHeight: 50, maxWidth: 50),
                          child: Container(
                            decoration: BoxDecoration(
                                color: Color(0xffd2d2d2),
                                border: Border.all(
                                    color: Color(0xffd2d2d2), width: 1),
                                borderRadius: BorderRadius.circular(50)),
                            child: Padding(
                              padding: EdgeInsets.all(10),
                              child: Image.network(
                                widget.contact.profile != "" &&
                                        widget.contact.profile != "none"
                                    ? widget.contact.profile
                                    : 'https://chatterloop.netlify.app/assets/default-e4788211.png',
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
                          "${widget.contact.fullname.firstName}${widget.contact.fullname.middleName == "N/A" ? "" : " ${widget.contact.fullname.middleName}"} ${widget.contact.fullname.lastName}",
                          style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF565656),
                              fontWeight: FontWeight.bold))
                    ],
                  )),
                  SizedBox(
                    width: 5,
                  ),
                  Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (kDebugMode) {
                              print("Message");
                            }
                          },
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: Center(
                              child: Icon(
                                color: Color(0xff9cc2ff),
                                Icons.messenger_outline_rounded,
                                size: 23,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 5,
                        ),
                        GestureDetector(
                          onTap: () {
                            if (kDebugMode) {
                              print("Unfriend");
                            }
                          },
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: Center(
                              child: Icon(
                                color: Color(0xffff6675),
                                Icons.person_remove_outlined,
                                size: 23,
                              ),
                            ),
                          ),
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
          SizedBox(
            height: 2,
          )
        ],
      ),
    );
  }
}