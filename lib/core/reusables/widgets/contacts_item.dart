import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/contacts_api.dart';
import 'package:chatterloop_app/models/user_models/contact_model.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ContactsItemWidget extends StatefulWidget {
  final Contact contact;
  final ContactPersonDetails other;
  final VoidCallback? onRemoved;

  const ContactsItemWidget(
      {super.key, required this.contact, required this.other, this.onRemoved});

  @override
  State<ContactsItemWidget> createState() => _ContactsItemWidgetState();
}

class _ContactsItemWidgetState extends State<ContactsItemWidget> {
  bool isRemoving = false;

  Future<void> _remove() async {
    setState(() => isRemoving = true);
    final ok = await ContactsApi().declineContactRequest(
      connectionId: widget.contact.connectionId,
      toUserId: widget.other.id,
      action: "remove",
    );
    if (!mounted) return;
    setState(() => isRemoving = false);
    if (ok) widget.onRemoved?.call();
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
              id: widget.other.id,
              name: widget.other.displayName,
              src: widget.other.profile != "none" ? widget.other.profile : null,
              size: 46,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  widget.other.displayName.isEmpty
                      ? widget.other.username
                      : widget.other.displayName,
                  style: TextStyle(
                      color: p.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ),
            CLIconBtn(
              icon: Icons.messenger_outline_rounded,
              color: p.brand,
              onPressed: () =>
                  context.push("/conversation/${widget.contact.connectionId}"),
            ),
            isRemoving
                ? SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: p.pink))),
                  )
                : CLIconBtn(
                    icon: Icons.person_remove_outlined,
                    color: p.pink,
                    tooltip: "Remove contact",
                    onPressed: _remove,
                  ),
          ],
        ),
      ),
    );
  }
}
