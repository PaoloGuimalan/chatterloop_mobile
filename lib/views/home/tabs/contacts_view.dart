// ignore_for_file: use_build_context_synchronously

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/contacts_api.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/reusables/widgets/contacts_item.dart';
import 'package:chatterloop_app/core/utils/content_validator.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:chatterloop_app/models/view_prop_models/conversation_view_props.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

class ContactsView extends StatefulWidget {
  const ContactsView({super.key});

  @override
  ContactsStateView createState() => ContactsStateView();
}

class ContactsStateView extends State<ContactsView> {
  bool isContactsInitialized = false;

  Future<void> getContactsProcess(BuildContext context) async {
    EncodedResponse? getContactsResponse =
        await ContactsApi().getContactsRequest();

    if (getContactsResponse != null) {
      Map<String, dynamic>? decodedContactsList =
          JwtCodec.decode(getContactsResponse.result);

      List<dynamic> rawContactsList = decodedContactsList?["contacts"];

      List<UserContacts> spreadedContactsList = rawContactsList
          .map((contact) => UserContacts.fromJson(contact))
          .toList();

      if (!mounted) return;
      setState(() => isContactsInitialized = true);

      StoreProvider.of<AppState>(context)
          .dispatch(DispatchModel(setContactsListT, spreadedContactsList));

      if (kDebugMode) {
        print(rawContactsList);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return StoreConnector<AppState, AppState>(builder: (context, state) {
      List<UserContacts> contactsList = state.contacts;
      if (!isContactsInitialized) {
        getContactsProcess(context);
      }
      return Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(
          title: const Text("Contacts"),
          actions: [
            CLIconBtn(
                icon: Icons.search, onPressed: () => context.push('/search')),
            const SizedBox(width: 6),
          ],
        ),
        body: contactsList.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    "No contacts yet - use search to find people and send a contact request.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.text2),
                  ),
                ),
              )
            : ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                itemCount: contactsList.length,
                itemBuilder: (context, index) {
                  if (contactsList[index].type != "single") {
                    return const SizedBox(height: 0);
                  }

                  final isUserOne =
                      contactsList[index].userdetails.userone.userID ==
                          state.userAuth.user.id;
                  final other = isUserOne
                      ? contactsList[index].userdetails.usertwo!
                      : contactsList[index].userdetails.userone;
                  final previewName = [
                    other.fullname.firstName,
                    if (other.fullname.middleName.isNotEmpty &&
                        other.fullname.middleName != "N/A")
                      other.fullname.middleName,
                    other.fullname.lastName,
                  ].where((part) => part.trim().isNotEmpty).join(" ");
                  final previewProfile = ContentValidator()
                      .validateConversationProfile(
                          other.profile, contactsList[index].type);

                  return ContactsItemWidget(
                    contact: other,
                    conversationMetaData: ConversationViewProps(
                      contactsList[index].contactID,
                      contactsList[index].type,
                      ConversationPreview(previewProfile, previewName),
                    ),
                  );
                },
              ),
      );
    }, converter: (store) {
      return store.state;
    });
  }
}
