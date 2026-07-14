// ignore_for_file: use_build_context_synchronously

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/contacts_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/contacts_item.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/contact_model.dart';
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
    final result = await ContactsApi().getContactsRequest();

    if (!mounted) return;
    setState(() => isContactsInitialized = true);

    StoreProvider.of<AppState>(context)
        .dispatch(DispatchModel(setContactsListT, result.results));
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return StoreConnector<AppState, AppState>(builder: (context, state) {
      List<Contact> contactsList =
          state.contacts.where((c) => c.type == "single").toList();
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
        body: !isContactsInitialized
            ? Center(child: CircularProgressIndicator(color: p.brand))
            : contactsList.isEmpty
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
                      final contact = contactsList[index];
                      final other = contact.other(state.userAuth.user.id);
                      return ContactsItemWidget(
                        contact: contact,
                        other: other,
                        onRemoved: () => getContactsProcess(context),
                      );
                    },
                  ),
      );
    }, converter: (store) {
      return store.state;
    });
  }
}
