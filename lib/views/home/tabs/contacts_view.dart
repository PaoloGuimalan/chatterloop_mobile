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

  /// Both sides of a contact pair are stored as separate rows sharing the
  /// same connection_id (server_service/user/views.py's UserContacts.post -
  /// one row per direction, so each user's own "who acted" perspective is
  /// consistent) - the Django list endpoint returns both rows for either
  /// party, so dedupe by connection_id here the way webapp's Contacts.tsx
  /// implicitly assumes a single row per relationship.
  List<Contact> _dedupedContacts(List<Contact> raw) {
    final seen = <String>{};
    final result = <Contact>[];
    for (final c in raw) {
      if (c.type != "single") continue;
      if (!seen.add(c.connectionId)) continue;
      result.add(c);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return StoreConnector<AppState, AppState>(builder: (context, state) {
      List<Contact> contactsList = _dedupedContacts(state.contacts);
      if (!isContactsInitialized) {
        getContactsProcess(context);
      }
      return Scaffold(
        backgroundColor: p.bg,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: !isContactsInitialized
              ? const Padding(
                  key: ValueKey('loading'),
                  padding: EdgeInsets.all(12),
                  child: CLListSkeleton(),
                )
              : contactsList.isEmpty
                  ? Center(
                      key: const ValueKey('empty'),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          "No contacts yet - use search to find people and send a contact request.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.text2),
                        ),
                      ),
                    )
                  : Padding(
                      key: const ValueKey('list'),
                      padding: const EdgeInsets.all(12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: p.surface,
                          border: Border.all(color: p.border),
                          borderRadius: BorderRadius.circular(CLRadii.md),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: contactsList.length,
                          separatorBuilder: (context, index) =>
                              Divider(height: 1, color: p.border),
                          itemBuilder: (context, index) {
                            final contact = contactsList[index];
                            final other = contact.other(state.userAuth.user.id);
                            final otherEntityId =
                                contact.otherEntityId(state.userAuth.user.id);
                            return ContactsItemWidget(
                              contact: contact,
                              other: other,
                              online: state.presence[otherEntityId]?.online ??
                                  false,
                            );
                          },
                        ),
                      ),
                    ),
        ),
      );
    }, converter: (store) {
      return store.state;
    });
  }
}
