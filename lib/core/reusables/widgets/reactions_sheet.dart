// Who reacted to a message - mobile counterpart of the webapp's
// ReactionsModal.tsx, opened by tapping a message's reaction pill.
//
// A reactor may be a person OR a page (you can react while switched to one),
// so every row is built from one normalized shape and falls back to the handle
// rather than rendering a blank row with a lone emoji floating in it.
//
// Your own row is tappable to remove the reaction, matching the webapp's
// onRemoveOwn. Everyone else's is read-only - reactions are entity-scoped and
// the server only ever lets you touch your own.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/models/messages_models/message_item_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:flutter/material.dart';

/// Display name for a reactor, mirroring the webapp's `reactorName`.
///
/// The middle name arrives as the "N/A" sentinel for realms, which is skipped
/// rather than rendered literally.
String reactorDisplayName(UsersContactPreview? info, String fallbackId) {
  if (info == null) return "Someone";
  final middle = info.fullname.middleName;
  final parts = [
    info.fullname.firstName.trim(),
    (middle.trim().isNotEmpty && middle != "N/A") ? middle.trim() : "",
    info.fullname.lastName.trim(),
  ].where((part) => part.isNotEmpty);

  final name = parts.join(" ").trim();
  if (name.isNotEmpty) return name;
  return info.userID.isNotEmpty ? info.userID : "Someone";
}

Future<void> showMessageReactionsSheet(
  BuildContext context, {
  required List<ReactionItem> reactions,
  required List<UsersContactPreview> reactorsInfo,
  required String selfEntityID,
  required VoidCallback onRemoveOwn,
}) {
  final p = cl(context);

  // Joined by ENTITY id, not userID: a page reacts as itself, and the entity
  // is the only id both sides agree on.
  UsersContactPreview? infoFor(String entityID) {
    final match = reactorsInfo.where((info) => info.entityID == entityID);
    return match.isEmpty ? null : match.first;
  }

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: p.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    // viewPadding.bottom, not SafeArea: a modal bottom sheet is NOT inset for
    // the system nav bar, so the last row of a scrolled list sits underneath
    // it. Adding the inset explicitly keeps the gap exact - SafeArea plus the
    // sheet's own spacing stacked into a visible band of empty surface.
    builder: (sheetContext) => Padding(
      padding:
          EdgeInsets.only(bottom: clSheetBottomGap(sheetContext, minimum: 8)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: p.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  "Reactions",
                  style: TextStyle(
                    color: p.text,
                    fontSize: CLType.sectionTitle,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  "${reactions.length}",
                  style: TextStyle(color: p.text3, fontSize: CLType.caption),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Capped and scrollable - a busy message must not push the sheet
          // past the top of the screen.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: reactions.length,
              itemBuilder: (context, index) {
                final reaction = reactions[index];
                final entityID = reaction.entityID;
                final info = infoFor(entityID);
                final isMine = entityID == selfEntityID;
                final name = reactorDisplayName(info, entityID);

                return ListTile(
                  dense: true,
                  visualDensity:
                      const VisualDensity(horizontal: -2, vertical: -2),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: CLAvatar(
                    id: entityID,
                    name: name,
                    src: (info?.profile != null && info!.profile != "none")
                        ? info.profile
                        : null,
                    size: 32,
                  ),
                  title: Text(
                    isMine ? "$name (you)" : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.text, fontSize: CLType.body),
                  ),
                  subtitle: isMine
                      ? Text("Tap to remove",
                          style: TextStyle(
                              color: p.text3, fontSize: CLType.caption))
                      : null,
                  trailing: Text(reaction.emoji?.toString() ?? "",
                      style: const TextStyle(fontSize: 20)),
                  onTap: isMine
                      ? () {
                          Navigator.of(sheetContext).pop();
                          onRemoveOwn();
                        }
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
