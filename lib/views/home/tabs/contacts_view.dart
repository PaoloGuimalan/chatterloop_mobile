// ignore_for_file: use_build_context_synchronously

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/contacts_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/contacts_item.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/contact_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class ContactsView extends StatefulWidget {
  const ContactsView({super.key});

  @override
  ContactsStateView createState() => ContactsStateView();
}

class ContactsStateView extends State<ContactsView> {
  bool isContactsInitialized = false;
  int _page = 1;
  bool _hasNext = false;
  bool _loadingMore = false;

  Future<void> getContactsProcess(BuildContext context) async {
    final result = await ContactsApi().getContactsRequest();

    if (!mounted) return;
    setState(() {
      isContactsInitialized = true;
      _page = 1;
      _hasNext = result.hasNext;
    });

    StoreProvider.of<AppState>(context)
        .dispatch(DispatchModel(setContactsListT, result.results));
  }

  /// Fetch the next page of raw contact rows and APPEND to Redux (deduped for
  /// display in _dedupedContacts). Guarded against overlapping requests.
  Future<void> _loadMore(BuildContext context) async {
    if (!_hasNext || _loadingMore) return;
    setState(() => _loadingMore = true);
    final store = StoreProvider.of<AppState>(context);
    final result = await ContactsApi().getContactsRequest(page: _page + 1);
    if (!mounted) return;
    store.dispatch(DispatchModel(
        setContactsListT, [...store.state.contacts, ...result.results]));
    setState(() {
      _page += 1;
      _hasNext = result.hasNext;
      _loadingMore = false;
    });
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
    // The whole contacts list previously re-deduped + rebuilt on every
    // dispatch. Narrow to the three slices used (contacts + own id + presence)
    // so it only rebuilds when a contact changes or a contact's presence
    // flips - not on message/typing/notification traffic.
    return StoreConnector<
        AppState,
        ({
          List<Contact> contacts,
          UserAuth userAuth,
          Map<String, PresenceInfo> presence
        })>(
        distinct: true,
        builder: (context, state) {
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
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if (n.metrics.pixels >=
                                n.metrics.maxScrollExtent - 240) {
                              _loadMore(context);
                            }
                            return false;
                          },
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount:
                                contactsList.length + (_loadingMore ? 1 : 0),
                            separatorBuilder: (context, index) =>
                                Divider(height: 1, color: p.border),
                            itemBuilder: (context, index) {
                              if (index >= contactsList.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                      child: SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))),
                                );
                              }
                              final contact = contactsList[index];
                              final other =
                                  contact.other(state.userAuth.user.id);
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
        ),
      );
    }, converter: (store) => (
          contacts: store.state.contacts,
          userAuth: store.state.userAuth,
          presence: store.state.presence,
        ));
  }
}
