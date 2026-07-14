import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/models/user_models/contact_model.dart';
import 'package:chatterloop_app/models/view_prop_models/conversation_view_props.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Mirrors webapp's Contacts.tsx row: avatar + name (tap -> profile) +
/// a single Message action. The remove/unfriend action is commented out
/// there too, not something webapp currently exposes on this screen.
class ContactsItemWidget extends StatelessWidget {
  final Contact contact;
  final ContactPersonDetails other;

  const ContactsItemWidget(
      {super.key, required this.contact, required this.other});

  void _openProfile(BuildContext context) {
    context.push('/user/${other.username}');
  }

  void _openMessage(BuildContext context) {
    context.push("/conversation/${contact.connectionId}",
        extra: ConversationViewProps(
            contact.connectionId,
            "single",
            ConversationPreview(
                other.profile != null && other.profile != "none"
                    ? other.profile!
                    : "",
                other.displayName.isEmpty
                    ? other.username
                    : other.displayName)));
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CLCard(
        child: Row(
          children: [
            CLAvatar(
              id: other.id,
              name: other.displayName,
              src: other.profile != "none" ? other.profile : null,
              size: 46,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () => _openProfile(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                          other.displayName.isEmpty
                              ? other.username
                              : other.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                    ),
                    if (other.isBadged) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.verified, size: 15, color: p.brand),
                    ],
                  ],
                ),
              ),
            ),
            CLIconBtn(
              icon: Icons.messenger_outline_rounded,
              color: p.brand,
              tooltip: "Message",
              onPressed: () => _openMessage(context),
            ),
          ],
        ),
      ),
    );
  }
}
