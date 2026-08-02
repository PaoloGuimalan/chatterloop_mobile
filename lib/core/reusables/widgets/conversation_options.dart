// Conversation options - Archive / Unarchive / Delete.
//
// ONE definition shared by the two places that offer them: the info button in
// a conversation's header (conversation_view.dart) and a long-press on a
// conversation in the messages list (message_item.dart). They present
// differently - a popup menu there, a bottom sheet here, which is what a
// long-press should feel like on mobile - but the option set and what each one
// DOES live here so the two cannot drift apart.
//
// Webapp parity: these mirror ConversationV2's options, minus Minimize, which
// is desktop-only.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:flutter/material.dart';

enum ConversationAction { archive, unarchive, delete }

/// The value the server's /chathistory route expects. "clear" rather than
/// "delete" - the thread itself is kept, only this participant's view of it is
/// dropped.
String conversationActionSlug(ConversationAction action) =>
    switch (action) {
      ConversationAction.archive => 'archive',
      ConversationAction.unarchive => 'unarchive',
      ConversationAction.delete => 'clear',
    };

/// Runs the action and refreshes the conversation list so an archived or
/// deleted thread drops off it.
///
/// Deliberately does NOT navigate - the header menu leaves the thread
/// afterwards, the list stays put, so that choice belongs to the caller.
Future<bool> applyConversationAction(
    String conversationID, ConversationAction action) async {
  final ok = await ConversationsApi()
      .updateChatHistoryRequest(conversationID, conversationActionSlug(action));
  if (!ok) return false;

  final res = await ConversationsApi().getConversationListRequest();
  if (res != null) {
    appStore.dispatch(DispatchModel(setMessagesListT, res.items));
  }
  return true;
}

/// Bottom sheet for a long-press on a conversation in the list.
///
/// `isArchived` picks Archive vs Unarchive. The messages list only ever shows
/// unarchived conversations - archiving drops a thread off it - so callers
/// from there pass false.
Future<ConversationAction?> showConversationOptionsSheet(
  BuildContext context, {
  required String title,
  bool isArchived = false,
}) {
  final p = cl(context);

  return showModalBottomSheet<ConversationAction>(
    context: context,
    backgroundColor: p.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    // Flat padding, NOT viewPadding/SafeArea. Verified on device: this sheet
    // is short enough that the system nav bar never covers Delete, and adding
    // the inset put a visible band of empty surface under it. The reactions
    // sheet DOES need the inset - it scrolls, so its last row can reach the
    // bottom edge - which is why the two differ.
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.text,
                  fontSize: CLType.sectionTitle,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 4),
          _optionTile(
            sheetContext,
            p,
            icon: isArchived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined,
            iconColor: p.text2,
            label: isArchived ? 'Unarchive' : 'Archive',
            labelColor: p.text,
            action: isArchived
                ? ConversationAction.unarchive
                : ConversationAction.archive,
          ),
          _optionTile(
            sheetContext,
            p,
            icon: Icons.delete_outline,
            iconColor: p.pink,
            label: 'Delete',
            labelColor: p.pink,
            action: ConversationAction.delete,
          ),
        ],
      ),
    ),
  );
}

/// One option row.
///
/// Sized from CLType rather than left to ListTile's Material defaults, which
/// render at 16 - larger than anything in this app's scale (sectionTitle is
/// 15) and visibly out of place next to the rest of the UI. The icon and
/// density are pulled down to match.
Widget _optionTile(
  BuildContext context,
  CLPalette p, {
  required IconData icon,
  required Color iconColor,
  required String label,
  required Color labelColor,
  required ConversationAction action,
}) {
  return ListTile(
    dense: true,
    visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
    horizontalTitleGap: 10,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    leading: Icon(icon, size: 18, color: iconColor),
    minLeadingWidth: 0,
    title: Text(
      label,
      style: TextStyle(color: labelColor, fontSize: CLType.body),
    ),
    onTap: () => Navigator.of(context).pop(action),
  );
}
