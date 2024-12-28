import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/requests/http_requests.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
    if (contactsList.isEmpty) {
      getContactsProcess();
    }
    return MaterialApp(
      home: Scaffold(
        body: Center(
            child: Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 40, left: 5, right: 5),
            child: ListView.builder(
                shrinkWrap: true,
                // controller: _scrollController,
                itemCount: contactsList.length,
                itemBuilder: (context, index) {
                  return Text(contactsList[index].contactID);
                }),
          ),
        )),
      ),
    );
  }
}
