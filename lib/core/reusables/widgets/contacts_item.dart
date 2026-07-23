import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/models/user_models/contact_model.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Mirrors webapp's Contacts.tsx row: avatar + name (tap -> profile) +
/// a single Message action. The remove/unfriend action is commented out
/// there too, not something webapp currently exposes on this screen.
class ContactsItemWidget extends StatelessWidget {
  final Contact contact;
  final ContactPersonDetails other;
  final bool online;

  /// Counterpart is a page rather than a person. Contacts are entity<->entity
  /// now, so a page can appear in this list; its name/handle arrive through
  /// the same first_name/username fields (the backend maps a realm's
  /// name/slug onto them), only presence and the badge differ.
  final bool isRealm;

  const ContactsItemWidget(
      {super.key,
      required this.contact,
      required this.other,
      this.isRealm = false,
      this.online = false});

  /// Pages live at /realm/:slug, people at /user/:username. Both screens
  /// parse different response shapes, so routing a page into the user screen
  /// yields a blank profile with dead buttons - `other.username` holds the
  /// realm's slug for a page (the backend maps slug onto that field), so the
  /// only thing distinguishing them is [isRealm].
  void _openProfile(BuildContext context) {
    context.push(
        isRealm ? '/realm/${other.username}' : '/user/${other.username}');
  }

  void _openMessage(BuildContext context) {
    // ConversationView only needs the id - it resolves the header name/
    // avatar itself via GET /m/conversation/:id, same as every other entry
    // point (Messages list, Profile, Search).
    context.push("/conversation/${contact.connectionId}");
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    // Flat row (no per-item card/border/shadow) inside ContactsView's single
    // bordered list container - mirrors webapp's .cl-contact-row, which is
    // just padding + hover highlight, not an individually-boxed card. The
    // Message button stays a sibling of the tappable avatar/name area
    // (not nested inside its InkWell) - nesting two independent tap
    // recognizers over the same pointer both fire in Flutter, so tapping
    // Message would also have triggered the profile navigation underneath.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _openProfile(context),
              borderRadius: BorderRadius.circular(CLRadii.sm),
              child: Row(
                children: [
                  CLAvatar(
                    id: other.id,
                    name: other.displayName,
                    src: other.profile != "none" ? other.profile : null,
                    size: 46,
                    online: online,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
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
                                      fontSize: 14.5)),
                            ),
                            if (other.isBadged) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.verified, size: 15, color: p.brand),
                            ],
                            if (isRealm) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.flag_outlined,
                                  size: 14, color: p.text3),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text("@${other.username}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.text2, fontSize: 12.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          CLIconBtn(
            icon: Icons.messenger_outline_rounded,
            color: p.brand,
            tooltip: "Message",
            onPressed: () => _openMessage(context),
          ),
        ],
      ),
    );
  }
}
