import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/requests/http_requests.dart';
import 'package:chatterloop_app/core/reusables/widgets/contacts_item.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:chatterloop_app/models/view_prop_models/conversation_view_props.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class ContactsView extends StatefulWidget {
  const ContactsView({super.key});

  @override
  ContactsStateView createState() => ContactsStateView();
}

class ContactsStateView extends State<ContactsView> {
  @override
  void initState() {
    super.initState();
  }

  List<UserContacts> contactsList = [];

  Future<void> getContactsProcess() async {
    EncodedResponse? getContactsResponse =
        await APIRequests().getContactsRequest();

    if (getContactsResponse != null) {
      Map<String, dynamic>? decodedContactsList =
          jwt.verifyJwt(getContactsResponse.result, secretKey);

      List<dynamic> rawContactsList = decodedContactsList?["contacts"];

      List<UserContacts> spreadedContactsList = rawContactsList
          .map((contact) => UserContacts.fromJson(contact))
          .toList();

      setState(() {
        contactsList = spreadedContactsList;
      });

      if (kDebugMode) {
        print(rawContactsList);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AppState>(builder: (context, state) {
      if (contactsList.isEmpty) {
        getContactsProcess();
      }
      return MaterialApp(
        home: Scaffold(
          body: Center(
              child: Container(
            color: Color(0xfff0f2f5),
            width: MediaQuery.of(context).size.width,
            child: Padding(
              padding: EdgeInsets.only(top: 5, left: 5, right: 5),
              child: Column(
                children: [
                  SizedBox(
                    width: MediaQuery.of(context).size.width,
                    height: 50,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.contact_page_sharp,
                          size: 30,
                          color: Color(0xffff7043),
                        ),
                        SizedBox(
                          width: 5,
                        ),
                        Text("Contacts",
                            style: TextStyle(
                                fontSize: 17,
                                color: Color(0xFF565656),
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                        padding: EdgeInsets.only(
                            top: 0, bottom: 10, left: 10, right: 10),
                        shrinkWrap: true,
                        // controller: _scrollController,
                        itemCount: contactsList.length,
                        itemBuilder: (context, index) {
                          if (contactsList[index].type == "single") {
                            if (contactsList[index]
                                    .userdetails
                                    .userone
                                    .userID ==
                                state.userAuth.user.userID) {
                              return ContactsItemWidget(
                                contact:
                                    contactsList[index].userdetails.usertwo!,
                                conversationMetaData: ConversationViewProps(
                                    contactsList[index].contactID,
                                    contactsList[index].type),
                              );
                            } else {
                              return ContactsItemWidget(
                                contact:
                                    contactsList[index].userdetails.userone,
                                conversationMetaData: ConversationViewProps(
                                    contactsList[index].contactID,
                                    contactsList[index].type),
                              );
                            }
                          }

                          return SizedBox(
                            height: 0,
                          );
                        }),
                  )
                ],
              ),
            ),
          )),
        ),
      );
    }, converter: (store) {
      return store.state;
    });
  }
}
