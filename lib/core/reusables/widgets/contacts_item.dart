import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:chatterloop_app/models/view_prop_models/conversation_view_props.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ContactsItemWidget extends StatelessWidget {
  final UsersContactPreview contact;
  final ConversationViewProps conversationMetaData;

  const ContactsItemWidget(
      {super.key, required this.contact, required this.conversationMetaData});

  String get _displayName => [
        contact.fullname.firstName,
        if (contact.fullname.middleName.isNotEmpty &&
            contact.fullname.middleName != "N/A")
          contact.fullname.middleName,
        contact.fullname.lastName,
      ].where((part) => part.trim().isNotEmpty).join(" ");

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CLCard(
        child: Row(
          children: [
            CLAvatar(
              id: contact.userID,
              name: _displayName,
              src: contact.profile != "none" ? contact.profile : null,
              size: 46,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_displayName,
                  style: TextStyle(
                      color: p.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ),
            CLIconBtn(
              icon: Icons.messenger_outline_rounded,
              color: p.brand,
              onPressed: () => context.push(
                "/conversation/${conversationMetaData.conversationID}",
                extra: conversationMetaData,
              ),
            ),
            CLIconBtn(
              icon: Icons.person_remove_outlined,
              color: p.pink,
              tooltip: "Remove contact",
              onPressed: null,
            ),
          ],
        ),
      ),
    );
  }
}
