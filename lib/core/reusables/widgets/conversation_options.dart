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
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/views/realm/realm_manage_view.dart';
import 'package:flutter/material.dart';

enum ConversationAction { archive, unarchive, delete }

/// The value the server's /chathistory route expects. "clear" rather than
/// "delete" - the thread itself is kept, only this participant's view of it is
/// dropped.
String conversationActionSlug(ConversationAction action) => switch (action) {
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
/// Pass [conversationId] AND a non-single [conversationType] to offer the
/// admin-only Manage entry. Unlike the conversation screen, a list row has no
/// conversation info to read `is_admin` from, so it is fetched - only for a
/// group, and only on a long-press, so single chats cost nothing.
Future<ConversationAction?> showConversationOptionsSheet(
  BuildContext context, {
  required String title,
  bool isArchived = false,
  String? conversationId,
  String conversationType = "single",
}) async {
  final p = cl(context);

  // Resolved BEFORE the sheet opens: a sheet that grows an extra row under the
  // user's finger a moment after appearing is worse than one that opens a beat
  // later with its final shape.
  final canManage = conversationId != null &&
      conversationId.isNotEmpty &&
      conversationType != "single" &&
      ((await ConversationsApi().getConversationInfoModelRequest(
                  conversationId, conversationType))
              ?.isAdmin ??
          false);
  if (!context.mounted) return null;

  return showModalBottomSheet<ConversationAction>(
    context: context,
    useRootNavigator: true,
    backgroundColor: p.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    // The LARGER of a comfortable 12 and the system inset.
    //
    // This was flat 12, on the reasoning that the sheet is short enough that
    // the nav bar never reaches it - which held on a device with gesture
    // navigation and a ~0 inset, and failed on one with a real button bar,
    // where Delete sat under it. Taking the max keeps the tight look where
    // there is no inset (the band of dead space that flat padding was avoiding)
    // and clears the bar where there is one.
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: clSheetBottomGap(sheetContext)),
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
          if (canManage)
            ListTile(
              dense: true,
              visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
              horizontalTitleGap: 10,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Icon(Icons.tune, size: 18, color: p.text2),
              minLeadingWidth: 0,
              title: Text('Manage group',
                  style: TextStyle(color: p.text, fontSize: CLType.body)),
              // Closes with no action - managing isn't one of the three chat
              // history verbs, so the caller must not treat this as one.
              onTap: () {
                Navigator.of(sheetContext).pop();
                openRealmManage(context, conversationId);
              },
            ),
          _optionTile(
            sheetContext,
            p,
            icon:
                isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
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
